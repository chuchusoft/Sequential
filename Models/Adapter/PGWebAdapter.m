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
#import "PGWebAdapter.h"

// Models
#import "PGNode.h"
#import "PGContainerAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGDataProvider.h"
#import "PGURLLoad.h"

// Controllers
#import "PGDocumentController.h"

// Other Sources
#import "PGFoundationAdditions.h"

@interface PGWebDataProvider : PGDataProvider
#if !__has_feature(objc_arc)
{
	@private
	PGResourceIdentifier *_identifier;
}
#endif

- (instancetype)initWithResourceIdentifier:(PGResourceIdentifier *)identifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

//	MARK: -

#if __has_feature(objc_arc)

@interface PGWebAdapter ()

@property (nonatomic, strong) PGURLLoad *mainLoad;
@property (nonatomic, strong) PGURLLoad *faviconLoad;

@end

#endif

//	MARK: -

@implementation PGWebAdapter

//	MARK: +PGDataProviderCustomizing

+ (PGDataProvider *)customDataProviderWithResourceIdentifier:(PGResourceIdentifier *)ident displayableName:(NSString *)name
{
	if(ident.isFileIdentifier) return nil;
	NSURL *const URL = ident.URL;
	if([@[@"http", @"https"] containsObject:URL.scheme])
#if __has_feature(objc_arc)
		return [[PGWebDataProvider alloc] initWithResourceIdentifier:ident];
#else
		return [[[PGWebDataProvider alloc] initWithResourceIdentifier:ident] autorelease];
#endif
	return nil;
}

//	MARK: - PGResourceAdapter

- (void)load
{
	NSURL *const URL = ((PGDataProvider *)self.dataProvider).identifier.URL;
	if(URL.fileURL) return [self.node fallbackFromFailedAdapter:self];
	[_faviconLoad cancelAndNotify:NO];
#if !__has_feature(objc_arc)
	[_faviconLoad release];
#endif
	_faviconLoad = [[PGURLLoad alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"/favicon.ico" relativeToURL:URL] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:15.0f] parent:self delegate:self];
	[_mainLoad cancelAndNotify:NO];
#if !__has_feature(objc_arc)
	[_mainLoad release];
#endif
	_mainLoad = [[PGURLLoad alloc] initWithRequest:[NSURLRequest requestWithURL:URL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:15.0f] parent:self delegate:self];
}

//	MARK: -NSObject

- (void)dealloc
{
	[_mainLoad cancelAndNotify:NO];
#if !__has_feature(objc_arc)
	[_mainLoad release];
#endif

	[_faviconLoad cancelAndNotify:NO];
#if !__has_feature(objc_arc)
	[_faviconLoad release];

	[super dealloc];
#endif
}

//	MARK: - <PGActivityOwner>

- (CGFloat)progressForActivity:(PGActivity *)activity
{
	return _mainLoad.activity.progress;
}

//	MARK: - <PGURLLoadDelegate>

- (void)loadLoadingDidProgress:(PGURLLoad *)sender
{
	if(sender == _mainLoad) [self.node PG_postNotificationName:PGNodeLoadingDidProgressNotification];
}
- (void)loadDidReceiveResponse:(PGURLLoad *)sender
{
	if(sender != _mainLoad) return;
	id const resp = sender.response;
	if([resp respondsToSelector:@selector(statusCode)] && ([resp statusCode] < 200 || [resp statusCode] >= 300)) {
		[_mainLoad cancelAndNotify:NO];
		[_faviconLoad cancelAndNotify:NO];
		self.error = [NSError PG_errorWithDomain:PGNodeErrorDomain code:PGGenericError localizedDescription:[NSString stringWithFormat:NSLocalizedString(@"The error %ld %@ was generated while loading the URL %@.", @"The URL returned a error status code. %ld is replaced by the status code, the first %@ is replaced by the human-readable error (automatically localized), the second %@ is replaced by the full URL."), (long)[resp statusCode], [NSHTTPURLResponse localizedStringForStatusCode:[resp statusCode]], [resp URL]] userInfo:nil];
		[self.node loadFinishedForAdapter:self];
		return;
	}
	PGDataProvider *const potentialDataProvider = [PGDataProvider providerWithURLResponse:resp data:nil];
#if __has_feature(objc_arc)
	NSMutableArray *const potentialAdapterClasses = [[potentialDataProvider adapterClassesForNode:self.node] mutableCopy];
#else
	NSMutableArray *const potentialAdapterClasses = [[[potentialDataProvider adapterClassesForNode:[self node]] mutableCopy] autorelease];
#endif
	if(!self.shouldRecursivelyCreateChildren)
#if __has_feature(objc_arc)
		for(Class const adapterClass in [potentialAdapterClasses copy])
#else
		for(Class const adapterClass in [[potentialAdapterClasses copy] autorelease])
#endif
			if([adapterClass isKindOfClass:[PGContainerAdapter class]])
				[potentialAdapterClasses removeObjectIdenticalTo:adapterClass]; // Instead of using -isKindOfClass:, add a class method or something.
	if(potentialAdapterClasses.count) return;
	[_mainLoad cancelAndNotify:NO];
	[_faviconLoad cancelAndNotify:NO];
	[self.node fallbackFromFailedAdapter:self];
}
- (void)loadDidSucceed:(PGURLLoad *)sender
{
	if(sender == _mainLoad) {
		[_faviconLoad cancelAndNotify:NO];
		self.node.dataProvider = [PGDataProvider providerWithURLResponse:_mainLoad.response data:_mainLoad.data];
	} else if(sender == _faviconLoad) {
#if __has_feature(objc_arc)
		NSImage *const favicon = [[NSImage alloc] initWithData:_faviconLoad.data];
#else
		NSImage *const favicon = [[[NSImage alloc] initWithData:[_faviconLoad data]] autorelease];
#endif
		if(favicon) self.node.identifier.icon = favicon; // Don't clear the favicon we already have if we can't load a new one.
	}
}
- (void)loadDidFail:(PGURLLoad *)sender
{
	if(sender != _mainLoad) return;
	[_faviconLoad cancelAndNotify:NO];
	self.error = [NSError PG_errorWithDomain:PGNodeErrorDomain code:PGGenericError localizedDescription:[NSString stringWithFormat:NSLocalizedString(@"The URL %@ could not be loaded.", @"The URL could not be loaded for an unknown reason. %@ is replaced by the full URL."), _mainLoad.request.URL] userInfo:nil];
	[self.node loadFinishedForAdapter:self];
}
- (void)loadDidCancel:(PGURLLoad *)sender
{
	if(sender != _mainLoad) return;
	[_faviconLoad cancelAndNotify:NO];
	[self.node loadFinishedForAdapter:self];
}

@end

//	MARK: -
#if __has_feature(objc_arc)
@interface PGWebDataProvider ()
@property (nonatomic, strong) PGResourceIdentifier *identifierWDP;
@end
#endif

//	MARK: -
@implementation PGWebDataProvider

- (instancetype)initWithResourceIdentifier:(PGResourceIdentifier *)identifier
{
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_identifierWDP = identifier;
#else
		_identifier = [identifier retain];
#endif
	}
	return self;
}

#if __has_feature(objc_arc)
- (PGResourceIdentifier *)identifier {
	return _identifierWDP;
}
#else
@synthesize identifier = _identifier;
#endif

//	MARK: - PGDataProvider(PGResourceAdapterLoading)

- (NSArray *)adapterClassesForNode:(PGNode *)node
{
	return @[[PGWebAdapter class]];
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_identifier release];
	[super dealloc];
}
#endif

@end
