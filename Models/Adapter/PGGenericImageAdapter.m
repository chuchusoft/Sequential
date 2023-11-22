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

// Controllers
#import "PGThumbnailController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGGeometry.h"

static NSBitmapImageRep *PGImageSourceImageRepAtIndex(CGImageSourceRef source, size_t i)
{
	if(!source) return nil;
	CGImageRef const image = CGImageSourceCreateImageAtIndex(source, i, NULL);
#if __has_feature(objc_arc)
	NSBitmapImageRep *const rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
#else
	NSBitmapImageRep *const rep = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
#endif
	CGImageRelease(image);
	return rep;
}

#if __has_feature(objc_arc)

@interface PGGenericImageAdapter()

@property (nonatomic, assign) BOOL reading;
@property (nonatomic, assign) BOOL readFailed;
@property (nonatomic, assign) PGOrientation orientation;
@property (nonatomic, strong) NSImageRep *cachedRep;
@property (readonly) NSDictionary *imageSourceOptions;

- (void)_setImageProperties:(NSDictionary *)properties;
- (void)_readFinishedWithImageRep:(NSImageRep *)aRep;

@end

#else

@interface PGGenericImageAdapter(Private)

- (NSDictionary *)_imageSourceOptions;
- (void)_setImageProperties:(NSDictionary *)properties;
- (void)_readFinishedWithImageRep:(NSImageRep *)aRep;

@end

#endif

//	MARK: -
@implementation PGGenericImageAdapter

#if __has_feature(objc_arc)
@synthesize imageProperties = _imageProperties;

- (NSDictionary *)imageSourceOptions
{
	NSString *utiType = self.dataProvider.UTIType;
	if(!utiType)
		return @{};

	return @{ (NSString *)kCGImageSourceTypeIdentifierHint: self.dataProvider.UTIType };
}
#else
- (NSDictionary *)_imageSourceOptions
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[[self dataProvider] UTIType], kCGImageSourceTypeIdentifierHint,
		nil];
}
#endif

- (void)_setImageProperties:(NSDictionary *)properties
{
	_orientation = PGOrientationWithTIFFOrientation([[properties objectForKey:(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue]);
#if !__has_feature(objc_arc)
	[_imageProperties release];
#endif
	_imageProperties = [properties copy];
}
- (void)_readFinishedWithImageRep:(NSImageRep *)aRep
{
	_reading = NO;
	_readFailed = !aRep;
	[[self node] noteIsViewableDidChange];
#if __has_feature(objc_arc)
	_cachedRep = aRep;
#else
	[_cachedRep release];
	_cachedRep = [aRep retain];
#endif
	[[self document] noteNodeDidCache:[self node]];
	[[self node] readFinishedWithImageRep:aRep];
}

//	MARK: - <PGResourceAdapting>

- (BOOL)canSaveData
{
	return YES;
}

//	MARK: -

- (void)load
{
	[self clearCache];
	_readFailed = NO;
	[[self node] noteIsViewableDidChange];
	[[self node] loadFinishedForAdapter:self];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (NSDictionary *)imageProperties
{
	return [[_imageProperties retain] autorelease];
}
#endif
- (PGOrientation)orientationWithBase:(BOOL)flag
{
	return PGAddOrientation(_orientation, [super orientationWithBase:flag]);
}
- (void)clearCache
{
#if !__has_feature(objc_arc)
	[_imageProperties release];
#endif
	_imageProperties = nil;
#if !__has_feature(objc_arc)
	[_cachedRep release];
#endif
	_cachedRep = nil;
}

//	MARK: - PGResourceAdapter

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

//	MARK: - <PGResourceAdapterImageGeneration>

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

	NSData *const data = !operation.isCancelled ? [[self dataProvider] data] : nil;
	CGImageSourceRef const source = data && !operation.isCancelled ?
		CGImageSourceCreateWithData((CFDataRef)data,
									(CFDictionaryRef)self.imageSourceOptions) :
		NULL;
	size_t const count = source && !operation.isCancelled ? CGImageSourceGetCount(source) : 0;
	if(0 == count) {
		if(source)
			CFRelease(source);

		[self performSelectorOnMainThread:@selector(_readFinishedWithImageRep:)
							   withObject:nil	//	nil means "reading failed"
							waitUntilDone:NO];
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
#if __has_feature(objc_arc)
						[md addEntriesFromDictionary:(__bridge NSDictionary *)sourceProperties];
#else
						[md addEntriesFromDictionary:(NSDictionary *)sourceProperties];
#endif
					CFRelease(sourceProperties);
				}
				if(properties) {
					if(md)
#if __has_feature(objc_arc)
						[md addEntriesFromDictionary:(__bridge NSDictionary *)properties];
#else
						[md addEntriesFromDictionary:(NSDictionary *)properties];
#endif
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
	if([PGThumbnailController shouldShowThumbnailsForDocument:[self document]]) {
		size_t const thumbnailFrameIndex = count / 10;
		NSBitmapImageRep *const repForThumb = 0 == thumbnailFrameIndex && rep0 ?
			rep0 : PGImageSourceImageRepAtIndex(source, thumbnailFrameIndex);
		if(repForThumb && ![operation isCancelled]) {
#if __has_feature(objc_arc)
			CFDictionaryRef const properties = 0 == thumbnailFrameIndex && image0properties ?
				CFRetain(image0properties) :
				CGImageSourceCopyPropertiesAtIndex(source, thumbnailFrameIndex, NULL);

			CFNumberRef propertyOrientation = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
			CFRelease(properties);
			NSUInteger propOrientationValue = 0;
			if(propertyOrientation && CFNumberGetTypeID() == CFGetTypeID(propertyOrientation))
				(void) CFNumberGetValue(propertyOrientation, kCFNumberNSIntegerType, &propOrientationValue);

			PGOrientation const orientation = PGOrientationWithTIFFOrientation(propOrientationValue);
			[self _setThumbnailImageInOperation:operation
									   imageRep:repForThumb
								  thumbnailSize:size
									orientation:orientation
										 opaque:NO
					setParentContainerThumbnail:NO];
#else
			NSDictionary *const properties = 0 == thumbnailFrameIndex && image0properties ?
				(NSDictionary *)image0properties :
				[(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, thumbnailFrameIndex, NULL) autorelease];

			PGOrientation const orientation = PGOrientationWithTIFFOrientation(
				[[properties objectForKey:(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue]);
			[self _setThumbnailImageInOperation:operation
									   imageRep:repForThumb
								  thumbnailSize:size
									orientation:orientation
										 opaque:NO
					setParentContainerThumbnail:NO];
#endif
		}
	}

	if(image0properties)
		CFRelease(image0properties);
	if(source)
		CFRelease(source);
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_imageProperties release];
	[_cachedRep release];
	[super dealloc];
}
#endif

@end
