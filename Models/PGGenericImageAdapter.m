/* Copyright © 2007-2009, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGGenericImageAdapter.h"

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGResourceIdentifier.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGGeometry.h"

static NSBitmapImageRep *PGImageSourceImageRepAtIndex(CGImageSourceRef source, size_t i)
{
	if(!source) return nil;
	CGImageRef const image = CGImageSourceCreateImageAtIndex(source, i, NULL);
	NSBitmapImageRep *const rep = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
	CGImageRelease(image);
	return rep;
}

@interface PGGenericImageAdapter(Private)

- (NSDictionary *)_imageSourceOptions;
- (void)_setImageProperties:(NSDictionary *)properties;
- (void)_readFinishedWithImageRep:(NSImageRep *)aRep;

@end

#pragma mark -
@implementation PGGenericImageAdapter

#pragma mark Private Protocol

- (NSDictionary *)_imageSourceOptions
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[[self dataProvider] UTIType], kCGImageSourceTypeIdentifierHint,
		nil];
}
- (void)_setImageProperties:(NSDictionary *)properties
{
	_orientation = PGOrientationWithTIFFOrientation([[properties objectForKey:(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue]);
	[_imageProperties release];
	_imageProperties = [properties copy];
}
- (void)_readFinishedWithImageRep:(NSImageRep *)aRep
{
	_reading = NO;
	_readFailed = !aRep;
	[[self node] noteIsViewableDidChange];
	[_cachedRep release];
	_cachedRep = [aRep retain];
	[[self document] noteNodeDidCache:[self node]];
	[[self node] readFinishedWithImageRep:aRep];
}

#pragma mark PGResourceAdapting Protocol

- (BOOL)canSaveData
{
	return YES;
}

#pragma mark -

- (void)load
{
	[self clearCache];
	_readFailed = NO;
	[[self node] noteIsViewableDidChange];
	[[self node] loadFinishedForAdapter:self];
}

#pragma mark -

- (NSDictionary *)imageProperties
{
	return [[_imageProperties retain] autorelease];
}
- (PGOrientation)orientationWithBase:(BOOL)flag
{
	return PGAddOrientation(_orientation, [super orientationWithBase:flag]);
}
- (void)clearCache
{
	[_imageProperties release];
	_imageProperties = nil;
	[_cachedRep release];
	_cachedRep = nil;
}

#pragma mark PGResourceAdapter

- (BOOL)adapterIsViewable
{
	return !_readFailed;
}
- (void)read
{
	if(_cachedRep) {
		[[self document] noteNodeDidCache:[self node]];
		[[self node] readFinishedWithImageRep:_cachedRep];
		return;
	}
	if(_reading) return;
	_reading = YES;
	_readFailed = NO;

	[self _startGeneratingImages];	//	2023/10/21
}
- (BOOL)canGenerateRealThumbnail
{
	return YES;
}

#pragma mark - <PGResourceAdapterImageGeneration>

- (void)generateImagesInOperation:(NSOperation *)operation
					thumbnailSize:(NSSize)size {	//	2023/10/21
	if(_cachedRep) {
		//	the only time this executes is when a main image exists but
		//	no thumbnail exists (because the thumbnail views were hidden
		//	when the main image was created but they are now visible)
		NSAssert(nil == [self realThumbnail], @"realThumbnail is nil");
		if(_imageProperties) {
			//	single image in image file: no need to build another
			//	ImageRep instance: just use _cachedRep and _orientation
			[self _setThumbnailImageInOperation:operation
									   imageRep:_cachedRep
								  thumbnailSize:size
									orientation:_orientation
										 opaque:NO
					setParentContainerThumbnail:NO];
			return;
		}

		//	fall through to slower code (e.g., for an animated image)
	}

	NSData *const data = [[self dataProvider] data];
	if(!data || [operation isCancelled])
		return;
	CGImageSourceRef const source = CGImageSourceCreateWithData((CFDataRef)data, (CFDictionaryRef)[self _imageSourceOptions]);
	if(!source)
		return;
	size_t const count = CGImageSourceGetCount(source);
	if(!count || [operation isCancelled]) {
		CFRelease(source);
		return;
	}

	//	main image generation
	NSBitmapImageRep *rep0 = nil;
	CFDictionaryRef image0properties = NULL;
	if(!_cachedRep) {
		NSImageRep *rep = nil;
		if(count) {
			//	2022/10/15 if this container file only has 1 image in it then add
			//	the properties of the container to the properties dictionary; this
			//	allows the Inspector panel to show metadata such as file size
			{
				CFDictionaryRef	sourceProperties = 1 == count ? CGImageSourceCopyProperties(source, NULL) : NULL;
				CFDictionaryRef	properties = 1 == count ? CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) : NULL;
				if(properties)
					image0properties	=	CFRetain(properties);
				const NSUInteger capacity =
					(properties ? CFDictionaryGetCount(properties) : 0) +
					(sourceProperties ? CFDictionaryGetCount(sourceProperties) : 0);
				NSMutableDictionary<NSString*, NSObject*>* md = capacity ?
					[NSMutableDictionary dictionaryWithCapacity:capacity] : 0;
				if(sourceProperties) {
					if(md)
						[md addEntriesFromDictionary:(NSDictionary *)sourceProperties];
					CFRelease(sourceProperties);
				}
				if(properties) {
					if(md)
						[md addEntriesFromDictionary:(NSDictionary *)properties];
					CFRelease(properties);
				}

				if(md && ![operation isCancelled])
					//	-performSelectorOnMainThread:withObject:waitUntilDone: will
					//	retain md; after -_setImageProperties: finishes, md is released
					[self performSelectorOnMainThread:@selector(_setImageProperties:)
										   withObject:md
										waitUntilDone:NO];
			}

			//	if the image is animated, use the entire image source
			if(count > 1)
				rep = [NSBitmapImageRep imageRepWithData:data];
			else
				rep = rep0 = PGImageSourceImageRepAtIndex(source, 0);
		}

		if(rep && ![operation isCancelled])
			//	-performSelectorOnMainThread:withObject:waitUntilDone: will retain
			//	rep; after -_readFinishedWithImageRep: finishes, rep is released
			[self performSelectorOnMainThread:@selector(_readFinishedWithImageRep:)
								   withObject:rep
								waitUntilDone:NO];
	}

	//	thumbnail generation
	if([[self document] showsThumbnails])
	{
		size_t const thumbnailFrameIndex = count / 10;
		NSBitmapImageRep *const repForThumb = 0 == thumbnailFrameIndex && rep0 ?
			rep0 : PGImageSourceImageRepAtIndex(source, thumbnailFrameIndex);
		if(!repForThumb || [operation isCancelled])
			return;
		NSDictionary *const properties = 0 == thumbnailFrameIndex && image0properties ?
			(NSDictionary *)image0properties :
			[(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, thumbnailFrameIndex, NULL) autorelease];

		PGOrientation const orientation = PGOrientationWithTIFFOrientation([[properties objectForKey:(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue]);
		[self _setThumbnailImageInOperation:operation
								   imageRep:repForThumb
							  thumbnailSize:size
								orientation:orientation
									 opaque:NO
				setParentContainerThumbnail:NO];
	}

	if(image0properties)
		CFRelease(image0properties);
	if(source)
		CFRelease(source);
}

#pragma mark NSObject

- (void)dealloc
{
	[_imageProperties release];
	[_cachedRep release];
	[super dealloc];
}

@end
