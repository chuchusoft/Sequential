/* Copyright © 2010, The Sequential Project
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
#import "PGDataProvider.h"

// Models
#import "PGResourceIdentifier.h"
#import "PGResourceDataProvider.h"

// Other Sources
//#import "PGFoundationAdditions.h"

@interface PGURLResponseDataProvider : PGDataProvider
#if !__has_feature(objc_arc)
{
	@private
	NSURLResponse *_response;
	NSData *_data;
}
#endif

- (id)initWithURLResponse:(NSURLResponse *)response data:(NSData *)data;

@end

//	MARK: -
@implementation PGDataProvider

//	MARK: +PGDataProvider(PGDataProviderCreation)

+ (id)providerWithResourceIdentifier:(PGResourceIdentifier *)ident displayableName:(NSString *)name
{
	for(NSString *const classString in [[[NSBundle bundleForClass:self] infoDictionary] objectForKey:@"PGDataProviderCustomizers"]) {
		Class const class = NSClassFromString(classString);
		if(![class respondsToSelector:@selector(customDataProviderWithResourceIdentifier:displayableName:)]) continue;
		PGDataProvider *const provider = [class customDataProviderWithResourceIdentifier:ident displayableName:name];
		if(provider) return provider;
	}
#if __has_feature(objc_arc)
	return [[PGResourceDataProvider alloc] initWithResourceIdentifier:ident displayableName:name];
#else
	return [[[PGResourceDataProvider alloc] initWithResourceIdentifier:ident displayableName:name] autorelease];
#endif
}
+ (id)providerWithResourceIdentifier:(PGResourceIdentifier *)ident
{
	return [self providerWithResourceIdentifier:ident displayableName:nil];
}
+ (id)providerWithURLResponse:(NSURLResponse *)response data:(NSData *)data
{
	for(NSString *const classString in [[[NSBundle bundleForClass:self] infoDictionary] objectForKey:@"PGDataProviderCustomizers"]) {
		Class const class = NSClassFromString(classString);
		if(![class respondsToSelector:@selector(customDataProviderWithURLResponse:data:)]) continue;
		PGDataProvider *const provider = [class customDataProviderWithURLResponse:response data:data];
		if(provider) return provider;
	}
#if __has_feature(objc_arc)
	return [[PGURLResponseDataProvider alloc] initWithURLResponse:response data:data];
#else
	return [[[PGURLResponseDataProvider alloc] initWithURLResponse:response data:data] autorelease];
#endif
}

//	MARK: - PGDataProvider

- (PGResourceIdentifier *)identifier
{
	return nil;
}
- (NSURLResponse *)response
{
	return nil;
}

//	MARK: -

- (NSData *)data
{
	return nil;
}
- (uint64_t)dataByteSize
{
	@autoreleasepool {
		NSData *const fullData = [self data];
		if(!fullData)
			return 0;
		return (uint64_t) [fullData length];	//	widening cast so OK
	}
}
- (NSDate *)dateModified
{
	return nil;
}
- (NSDate *)dateCreated
{
	return nil;
}

//	MARK: -

- (NSString *)UTIType
{
	return nil;
}
/* - (NSString *)MIMEType
{
	return nil;
}
- (OSType)typeCode
{
	return 0;
} */
- (NSString *)extension
{
	return nil;
}

//	MARK: -

- (BOOL)hasData
{
	@autoreleasepool {
		return !![self data];
	}
}
/*	2023/09/17 deprecated
- (NSNumber *)dataLength
{
	@autoreleasepool {
		NSData *const fullData = [self data];
		NSUInteger const size = [fullData length];
		return [NSNumber numberWithUnsignedInteger:size];
	}
} */
- (NSData *)fourCCData
{
	NSData *fourCCData;
	@autoreleasepool {
		NSData *const fullData = [self data];
#if __has_feature(objc_arc)
		fourCCData = [fullData length] > 4 ? [fullData subdataWithRange:NSMakeRange(0, 4)] : nil;
#else
		fourCCData = [fullData length] > 4 ? [[fullData subdataWithRange:NSMakeRange(0, 4)] retain] : nil;
#endif
	}
#if __has_feature(objc_arc)
	return fourCCData;
#else
	return [fourCCData autorelease];
#endif
}
- (NSImage *)icon
{
	NSString *const MIMEType = [self MIMEType];
	OSType typeCode = [self typeCode];
	if(MIMEType || typeCode) {
		IconRef iconRef = NULL;

		if('fold' == typeCode)
			typeCode = kGenericFolderIcon;
#if __has_feature(objc_arc)
		if(noErr == GetIconRefFromTypeInfo('????', typeCode, NULL, (__bridge CFStringRef)MIMEType,
											kIconServicesNormalUsageFlag, &iconRef) && iconRef) {
			NSImage *const icon = [[NSImage alloc] initWithIconRef:iconRef];
			ReleaseIconRef(iconRef);
			return icon;
		}
#else
		if(noErr == GetIconRefFromTypeInfo('????', typeCode, NULL, (CFStringRef)MIMEType,
											kIconServicesNormalUsageFlag, &iconRef) && iconRef) {
			NSImage *const icon = [[[NSImage alloc] initWithIconRef:iconRef] autorelease];
			ReleaseIconRef(iconRef);
			return icon;
		}
#endif
	}
	NSString *const extension = [self extension];
	if(extension) return [[NSWorkspace sharedWorkspace] iconForFileType:extension];
	return nil;
}
- (NSString *)kindString
{
	NSString *kind = [[NSWorkspace sharedWorkspace] localizedDescriptionForType:[self UTIType]]; // Ugly ("Portable Network Graphics image"), but more accurate than file extensions.
	if(kind) return kind;
#if 1
	#if __has_feature(objc_arc)
	CFStringRef desc = UTTypeCopyDescription((__bridge CFStringRef) [self UTIType]);
	#else
	CFStringRef desc = UTTypeCopyDescription((CFStringRef) [self UTIType]);
	#endif
	if(desc)
	#if __has_feature(objc_arc)
		return (NSString*)CFBridgingRelease(desc);
	#else
		return [(NSString*)desc autorelease];
	#endif
#else
	if(noErr == LSCopyKindStringForTypeInfo(kLSUnknownType, kLSUnknownCreator, (CFStringRef)[self extension], (CFStringRef *)&kind)) return [kind autorelease];
	if(noErr == LSCopyKindStringForMIMEType((CFStringRef)[self MIMEType], (CFStringRef *)&kind)) return [kind autorelease]; // Extremely ugly ("TextEdit.app Document"), worst case.
#endif
	return nil;
}

//	MARK: - <NSCopying>

- (id)copyWithZone:(NSZone *)zone
{
#if __has_feature(objc_arc)
	return self;
#else
	return [self retain];
#endif
}

@end

//	MARK: -
@implementation PGURLResponseDataProvider

#if __has_feature(objc_arc)
@synthesize response = _response;
@synthesize data = _data;
#endif

- (id)initWithURLResponse:(NSURLResponse *)response data:(NSData *)data
{
	if((self = [super init])) {
		_response = [response copy];
		_data = [data copy];
	}
	return self;
}

//	MARK: - PGDataProvider

- (PGResourceIdentifier *)identifier
{
	return [[_response URL] PG_resourceIdentifier];
}
#if !__has_feature(objc_arc)
- (NSURLResponse *)response
{
	return [[_response retain] autorelease];
}
#endif

//	MARK: -

#if !__has_feature(objc_arc)
- (NSData *)data
{
	return [[_data retain] autorelease];
}
#endif

//	MARK: -

- (NSString *)UTIType
{
#if __has_feature(objc_arc)
	return (NSString *)CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType,
													   (__bridge CFStringRef)[self MIMEType], NULL));
#else
	return [(NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (CFStringRef)[self MIMEType], NULL) autorelease];
#endif
}
- (NSString *)MIMEType
{
	return [_response MIMEType];
}
- (NSString *)extension
{
	return [[[_response suggestedFilename] pathExtension] lowercaseString];
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_response release];
	[_data release];
	[super dealloc];
}
#endif

@end
