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
#import "PGResourceAdapter.h"

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGContainerAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGDataProvider.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGDebug.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

NSString *const PGPasswordKey = @"PGPassword";

static NSString *const PGBundleTypeFourCCsKey = @"PGBundleTypeFourCCs";
static NSString *const PGLSItemContentTypes = @"LSItemContentTypes";
static NSString *const PGCFBundleTypeMIMETypesKey = @"CFBundleTypeMIMETypes";
static NSString *const PGCFBundleTypeOSTypesKey = @"CFBundleTypeOSTypes";
static NSString *const PGCFBundleTypeExtensionsKey = @"CFBundleTypeExtensions";

//static NSString *const PGOrientationKey = @"PGOrientation";

#define PGThumbnailSize 128.0f

@interface PGGenerateImageOperation : NSOperation {
@private
	NSObject<PGResourceAdapterImageGeneratorCompletion, PGResourceAdapterImageGeneration> *_adapter;
}

- (id)initWithResourceAdapter:(PGResourceAdapter *)adapter;
@end

#if __has_feature(objc_arc)

@interface PGResourceAdapter ()

@property (nonatomic, strong) PGActivity *activity;
@property (nonatomic, strong) NSImage *realThumbnail;
@property (nonatomic, strong) NSOperation *generateImageOperation;	//	2023/10/21 generates full image and/or thumbnail if neither exist

- (void)_stopGeneratingImagesInOperation:(NSOperation *)operation;

@end

#else

@interface PGResourceAdapter (Private)

- (void)_stopGeneratingImagesInOperation:(NSOperation *)operation;

@end

#endif

#pragma mark -
@implementation PGResourceAdapter

#pragma mark +PGResourceAdapter

+ (NSDictionary *)typesDictionary
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"PGResourceAdapterClasses"];
}
+ (NSArray *)supportedFileTypes
{
	NSMutableArray *const fileTypes = [NSMutableArray array];
	NSDictionary *const types = [self typesDictionary];
	for(NSString *const classString in types) {
		id const adapterClass = NSClassFromString(classString);
		if(!adapterClass) continue;
		NSDictionary *const typeDict = [types objectForKey:classString];
		[fileTypes addObjectsFromArray:[typeDict objectForKey:PGCFBundleTypeExtensionsKey]];
		for(NSString *const type in [typeDict objectForKey:PGCFBundleTypeOSTypesKey]) [fileTypes addObject:PGOSTypeToStringQuoted(PGOSTypeFromString(type), YES)];
	}
	return fileTypes;
}
+ (NSArray *)supportedMIMETypes
{
	NSMutableArray *const MIMETypes = [NSMutableArray array];
	NSDictionary *const types = [self typesDictionary];
	for(NSString *const classString in types) {
		id const adapterClass = NSClassFromString(classString);
		if(!adapterClass) continue;
		NSDictionary *const typeDict = [types objectForKey:classString];
		[MIMETypes addObjectsFromArray:[typeDict objectForKey:PGCFBundleTypeMIMETypesKey]];
	}
	return MIMETypes;
}

#pragma mark -PGResourceAdapter

- (id)initWithNode:(PGNode *)node dataProvider:(PGDataProvider *)dataProvider
{
	if((self = [super init])) {
		_node = node;
#if __has_feature(objc_arc)
		_dataProvider = dataProvider;
#else
		_dataProvider = [dataProvider retain];
#endif
		_activity = [[PGActivity alloc] initWithOwner:self];
	}
	return self;
}

#pragma mark -

- (PGContainerAdapter *)containerAdapter
{
	return [self parentAdapter];
}
- (PGContainerAdapter *)rootContainerAdapter
{
	return [[self parentAdapter] rootContainerAdapter];
}
- (NSUInteger)depth
{
	return [[self parentAdapter] depth] + 1;
}
- (PGRecursionPolicy)recursionPolicy
{
	PGContainerAdapter *const p = [self parentAdapter];
	return p ? [p descendantRecursionPolicy] : PGRecurseToMaxDepth;
}
- (BOOL)shouldRecursivelyCreateChildren
{
	switch([self recursionPolicy]) {
		case PGRecurseToMaxDepth: return [self depth] <= [[[NSUserDefaults standardUserDefaults] objectForKey:PGMaxDepthKey] unsignedIntegerValue] + 1;
		case PGRecurseToAnyDepth: return YES;
		case PGRecurseNoFurther: return NO;
	}
	PGAssertNotReached(@"Invalid recursion policy.");
	return NO;
}

#pragma mark -

- (NSData *)data
{
	return [_dataProvider data];
}
- (uint64_t)dataByteSize
{
	return [_dataProvider dataByteSize];
}
- (BOOL)canGetData
{
	return [_dataProvider hasData];
}
- (BOOL)hasNodesWithData
{
	return [self canGetData];
}

#pragma mark -

- (BOOL)isContainer
{
	return NO;
}
- (BOOL)hasChildren
{
	return NO;
}
/* - (NSInteger)childCount // returns NSNotFound when isContainer = NO
{
	return NSNotFound;
}
- (NSUInteger)folderAndImageCount
{
	return NSUIntegerMax;
} */
- (uint64_t)byteSizeAndFolderAndImageCount
{
	return ULONG_MAX;
}
- (uint64_t)byteSizeOfAllChildren
{
	return ULONG_MAX;
}
- (BOOL)isSortedFirstViewableNodeOfFolder
{
	PGContainerAdapter *const container = [self containerAdapter];
	return !container || [container sortedFirstViewableNodeInFolderFirst:YES] == [self node];
}
- (BOOL)hasRealThumbnail
{
	return !!_realThumbnail;
}
- (BOOL)isResolutionIndependent
{
	return NO;
}
- (BOOL)canSaveData
{
	return NO;
}
- (BOOL)hasSavableChildren
{
	return NO;
}

#pragma mark -

- (NSUInteger)viewableNodeIndex
{
	return [[self parentAdapter] viewableIndexOfChild:[self node]];
}
- (NSUInteger)viewableNodeCount
{
	return [[self node] isViewable] ? 1 : 0;
}
- (BOOL)hasViewableNodeCountGreaterThan:(NSUInteger)anInt
{
	return [self viewableNodeCount] > anInt;
}

#pragma mark -

- (BOOL)adapterIsViewable
{
	return NO;
}
- (void)loadIfNecessary
{
	@autoreleasepool { // We load recursively, so memory use can be a problem.
		[self load];
	}
}
- (void)load
{
	[[self node] loadFinishedForAdapter:self];
}
- (void)read
{
	[[self node] readFinishedWithImageRep:nil];
}

#pragma mark -

- (NSImage *)thumbnail
{
	NSImage *const realThumbnail = [self realThumbnail];
	if(realThumbnail) return realThumbnail;

	if([self canGenerateRealThumbnail])
		[self _startGeneratingImages];	//	2023/10/21
	else if ([(NSObject<PGResourceAdapterImageGeneration>*)self respondsToSelector:@selector(generateThumbnailForContainer)])
		//	2023/10/22 currently, only PGPDFAdapter implements -generateThumbnailForContainer
		//	because PDF files are a suitable container (because PDF files have a definite
		//	notion of a first page whereas an archive does not [you can sort an archive's
		//	contents by mod-date, for example, so what is then the first page?]).
		[(NSObject<PGResourceAdapterImageGeneration>*)self generateThumbnailForContainer];

	return [self fastThumbnail];
}
- (NSImage *)fastThumbnail
{
	NSImage *const thumbnail = _dataProvider.icon;
	thumbnail.size	=	NSMakeSize(PGThumbnailSize, PGThumbnailSize);
	return thumbnail;
}
#if !__has_feature(objc_arc)
- (NSImage *)realThumbnail
{
	return [[_realThumbnail retain] autorelease];
}
#endif
- (void)_setRealThumbnail:(NSImage *)anImage
{
	//	2023/10/22 if this adapter represents a container (such as a PDF file), allow
	//	the thumbnail image of this container to be set; _generateImageOperation will
	//	be non-nil only on the instance that is generating the thumbnail (e.g., in the
	//	page 0 instance for a PDF file)
	if(!_generateImageOperation && !self.isContainer)
		return;

	if(anImage != _realThumbnail) {
#if __has_feature(objc_arc)
		_realThumbnail = anImage;
#else
		[_realThumbnail release];
		_realThumbnail = [anImage retain];
#endif
		[[self document] noteNodeThumbnailDidChange:[self node] recursively:NO];
	}
}
- (BOOL)canGenerateRealThumbnail
{
	return NO;
}
- (void)invalidateThumbnail
{
	if(![self canGenerateRealThumbnail]) return;

	[self _stopGeneratingImagesInOperation:_generateImageOperation];
#if !__has_feature(objc_arc)
	[_realThumbnail release];
#endif
	_realThumbnail = nil;

	(void)[self thumbnail];
}

#pragma mark -

- (NSDictionary *)imageProperties
{
	return nil;
}
- (PGOrientation)orientationWithBase:(BOOL)flag
{
	return flag ? [[self document] baseOrientation] : PGUpright;
}
- (void)clearCache {}
- (void)addChildrenToMenu:(NSMenu *)menu {}

#pragma mark -

- (PGNode *)nodeForIdentifier:(PGResourceIdentifier *)ident
{
	return PGEqualObjects(ident, [[self node] identifier]) ? [self node] : nil;
}

- (PGNode *)sortedViewableNodeFirst:(BOOL)flag
{
	return [self sortedViewableNodeFirst:flag stopAtNode:nil includeSelf:YES];
}
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag stopAtNode:(PGNode *)descendent includeSelf:(BOOL)includeSelf
{
	return includeSelf && [[self node] isViewable] && [self node] != descendent ? [self node] : nil;
}

- (PGNode *)sortedViewableNodeNext:(BOOL)flag
{
	return [self sortedViewableNodeNext:flag includeChildren:YES];
}
- (PGNode *)sortedViewableNodeNext:(BOOL)flag includeChildren:(BOOL)children
{
	return [[self parentAdapter] outwardSearchForward:flag fromChild:[self node] inclusive:NO withSelector:@selector(sortedViewableNodeFirst:) context:nil];
}
- (PGNode *)sortedViewableNodeNext:(BOOL)flag afterRemovalOfChildren:(NSArray *)removedChildren fromNode:(PGNode *)changedNode
{
	if(!removedChildren) return [self node];
	PGNode *const potentiallyRemovedAncestor = [[self node] ancestorThatIsChildOfNode:changedNode];
	if(!potentiallyRemovedAncestor || NSNotFound == [removedChildren indexOfObjectIdenticalTo:potentiallyRemovedAncestor]) return [self node];
	return [[[self sortedViewableNodeNext:flag] resourceAdapter] sortedViewableNodeNext:flag afterRemovalOfChildren:removedChildren fromNode:changedNode];
}

- (PGNode *)sortedFirstViewableNodeInFolderNext:(BOOL)forward inclusive:(BOOL)inclusive
{
	PGNode *const node = [[self parentAdapter] outwardSearchForward:forward fromChild:[self node] inclusive:inclusive withSelector:@selector(sortedFirstViewableNodeInFolderFirst:) context:nil];
	return node || forward ? node : [[self rootContainerAdapter] sortedViewableNodeFirst:YES stopAtNode:[self node] includeSelf:YES];
}
- (PGNode *)sortedFirstViewableNodeInFolderFirst:(BOOL)flag
{
	return nil;
}
- (PGNode *)sortedViewableNodeInFolderFirst:(BOOL)flag
{
	PGContainerAdapter *ancestor = [self parentAdapter];
	while(ancestor) {
		PGNode *const node = [ancestor sortedViewableNodeFirst:flag];
		if([self node] != node) return node;
		ancestor = [ancestor parentAdapter];
	}
	return nil;
}

- (PGNode *)sortedViewableNodeNext:(BOOL)flag matchSearchTerms:(NSArray *)terms
{
	PGNode *const node = [[self parentAdapter] outwardSearchForward:flag fromChild:[self node] inclusive:NO withSelector:@selector(sortedViewableNodeFirst:matchSearchTerms:stopAtNode:) context:terms];
	return node ? node : [[self rootContainerAdapter] sortedViewableNodeFirst:flag matchSearchTerms:terms stopAtNode:[self node]];
}
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag matchSearchTerms:(NSArray *)terms stopAtNode:(PGNode *)descendent
{
	return [[self node] isViewable] && [self node] != descendent && [[[[self node] identifier] displayName] PG_matchesSearchTerms:terms] ? [self node] : nil;
}

- (BOOL)nodeIsFirstOrLastOfFolder:(BOOL)testForFirst { // 2022/11/04 added
	//	-sortedViewableNodeInFolderFirst: always excludes self.node so it
	//	can never produce the correct answer to the question; thus this
	//	function exists to correctly answer the question
	PGContainerAdapter *ancestor = [self parentAdapter];
	if(!ancestor)
		return NO;

	return self.node == [ancestor sortedViewableNodeFirst:testForFirst];
}

- (BOOL)nodeIsFirstOfFolder { // 2022/11/04 added
	return [self nodeIsFirstOrLastOfFolder:YES];
}

- (BOOL)nodeIsLastOfFolder { // 2022/11/04 added
	return [self nodeIsFirstOrLastOfFolder:NO];
}

#pragma mark -

- (void)noteResourceDidChange {}

- (void)_startGeneratingImages {	//	2023/10/21
	NSAssert(NSThread.isMainThread, @"");
	if(!_generateImageOperation) {
		[[self node] setIsReading:YES];

		NSAssert([self conformsToProtocol:@protocol(PGResourceAdapterImageGeneration)],
					@"PGResourceAdapterImageGeneration");
		_generateImageOperation = [[PGGenerateImageOperation alloc] initWithResourceAdapter:self];
		[[self document] addOperation:_generateImageOperation];
	}
}

- (void)_stopGeneratingImagesInOperation:(NSOperation *)operation {	//	2023/10/21
	NSAssert(NSThread.isMainThread, @"");
	[[self node] setIsReading:NO];

	NSParameterAssert(_generateImageOperation == operation);

	if(_generateImageOperation) {
		[_generateImageOperation cancel];
#if !__has_feature(objc_arc)
		[_generateImageOperation release];
#endif
		_generateImageOperation = nil;
	}
}

static
NSBitmapImageRep *
ThumbnailOf(NSImageRep *imageRep, NSSize size, PGOrientation orientation, BOOL opaque) {
	if(!imageRep) return nil;
	NSSize const originalSize = PGRotated90CCW & orientation ? NSMakeSize([imageRep pixelsHigh], [imageRep pixelsWide]) : NSMakeSize([imageRep pixelsWide], [imageRep pixelsHigh]);
	NSSize const s = PGIntegralSize(PGScaleSizeByFloat(originalSize, MIN(1.0f, MIN(size.width / originalSize.width, size.height / originalSize.height))));
#if __has_feature(objc_arc)
	NSBitmapImageRep *const thumbRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
																			   pixelsWide:s.width
																			   pixelsHigh:s.height
																			bitsPerSample:8
																		  samplesPerPixel:4
																				 hasAlpha:YES
																				 isPlanar:NO
																		   colorSpaceName:NSDeviceRGBColorSpace
																			  bytesPerRow:0
																			 bitsPerPixel:0];
#else
	NSBitmapImageRep *const thumbRep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:s.width pixelsHigh:s.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
#endif
	if(!thumbRep) return nil;
	NSGraphicsContext *const context = [NSGraphicsContext graphicsContextWithBitmapImageRep:thumbRep];
	[NSGraphicsContext setCurrentContext:context];
	[context setImageInterpolation:NSImageInterpolationHigh];
	NSRect rect = NSMakeRect(0.0f, 0.0f, s.width, s.height);
	if(PGUpright != orientation) [[NSAffineTransform PG_transformWithRect:&rect orientation:orientation] concat];
	if(opaque) {
		[[NSColor whiteColor] set];
		NSRectFill(rect);
	}
	[imageRep drawInRect:rect];
	[context flushGraphics];
	return thumbRep;
}

- (void)_setThumbnailImageInOperation:(NSOperation *)operation
							 imageRep:(NSImageRep *)rep
						thumbnailSize:(NSSize)size
						  orientation:(PGOrientation)orientation
							   opaque:(BOOL)opaque
		  setParentContainerThumbnail:(BOOL)setParentContainerThumbnail {
	NSImageRep *thumbRep = ThumbnailOf(rep, size, orientation, opaque);
	if(!thumbRep || [operation isCancelled])
		return;

#if __has_feature(objc_arc)
	NSImage *const thumbImage = [[NSImage alloc] initWithSize:NSMakeSize(thumbRep.pixelsWide, thumbRep.pixelsHigh)];
#else
	NSImage *const thumbImage = [[[NSImage alloc] initWithSize:NSMakeSize([thumbRep pixelsWide], [thumbRep pixelsHigh])] autorelease];
#endif
	if(!thumbImage || [operation isCancelled])
		return;
	[thumbImage addRepresentation:thumbRep];
	if([operation isCancelled])
		return;
	[self performSelectorOnMainThread:@selector(_setRealThumbnail:)
						   withObject:thumbImage
						waitUntilDone:NO];

	if(setParentContainerThumbnail)	//	2023/10/22
		[[self parentAdapter] performSelectorOnMainThread:@selector(_setRealThumbnail:)
											   withObject:thumbImage
											waitUntilDone:NO];
}

#pragma mark -NSObject

- (id)init
{
	PGAssertNotReached(@"Invalid initializer, use -initWithNode:dataProvider: instead.");
#if __has_feature(objc_arc)
	self = nil;
#else
	[self release];
#endif
	return nil;
}
- (void)dealloc
{
	[_activity invalidate];

#if !__has_feature(objc_arc)
	[_dataProvider release];
	[_activity release];
	[_error release];
	[_realThumbnail release];
	[_generateImageOperation release];	//	2023/10/21
	[super dealloc];
#endif
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %@>", [self class], self, _dataProvider];
}

#pragma mark -<PGActivityOwner>

#if !__has_feature(objc_arc)
- (PGActivity *)activity
{
	return [[_activity retain] autorelease];
}
#endif
- (NSString *)descriptionForActivity:(PGActivity *)activity
{
	return [[[self node] identifier] displayName];
}

#pragma mark -<PGResourceAdapting>

- (PGNode *)parentNode
{
	return [[self parentAdapter] node];
}
- (PGContainerAdapter *)parentAdapter
{
	return [_node parentAdapter];
}
- (PGNode *)rootNode
{
	return [[self node] rootNode];
}
- (PGDocument *)document
{
	return [_node document];
}

#pragma mark -

- (void)noteFileEventDidOccurDirect:(BOOL)flag {}
- (void)noteSortOrderDidChange {}

#pragma mark - <PGResourceAdapterImageGeneratorCompletion>

- (void)generationDidCompleteInOperation:(NSOperation *)operation {
	[self _stopGeneratingImagesInOperation:operation];
}

@end

#pragma mark -
@implementation PGGenerateImageOperation

- (id)initWithResourceAdapter:(NSObject<PGResourceAdapterImageGeneratorCompletion, PGResourceAdapterImageGeneration> *)adapter
{
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_adapter = adapter;
#else
		_adapter = [adapter retain];
#endif
	}
	return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_adapter release];
	[super dealloc];
}
#endif

#pragma mark NSOperation

- (void)main
{
	@try {	//	2023/08/20 added exception wrapper
		if([self isCancelled]) return;
		[_adapter generateImagesInOperation:self thumbnailSize:NSMakeSize(PGThumbnailSize, PGThumbnailSize)];	//	2023/10/21
	}
	@catch(...) {
		// Do not rethrow exceptions.
	}
	@finally {
		[_adapter performSelectorOnMainThread:@selector(generationDidCompleteInOperation:)
								   withObject:self
								waitUntilDone:NO];
	}
}

@end

#pragma mark -
@implementation PGDataProvider(PGResourceAdapterLoading)

- (NSUInteger)_matchPriorityForTypeDictionary:(NSDictionary *)dict
							   withFourCCData:(uint8_t*)fourCCData
{
	//	2023/10/14 optimized to reduce I/O requests:
	//	calls to -fourCCData occur only when necessary and only occur once
	id o = [dict objectForKey:PGBundleTypeFourCCsKey];
	if(o) {
		if(0 == *fourCCData) {
			NSData *const self_fourCCData = [self fourCCData];
			if(self_fourCCData)
				[self_fourCCData getBytes:fourCCData length:(NSUInteger)sizeof(uint32_t)];
			else
				fourCCData[3] = fourCCData[2] = fourCCData[1] = fourCCData[0] = 0xFF;
		}

		//	if an attempt to read the 4CC was done
		if(0 != fourCCData[0] || 0 != fourCCData[1] || 0 != fourCCData[2] || 0 != fourCCData[3]) {
			//	if the 4CC was successfully read in
			if(0xFF != fourCCData[0] || 0xFF != fourCCData[1] || 0xFF != fourCCData[2] || 0xFF != fourCCData[3]) {
				//	then do comparisons
				for(NSData* d in o) {
					if(sizeof(uint32_t) != d.length)
						continue;
					uint8_t bytes[4];
					[d getBytes:bytes length:(NSUInteger)sizeof(bytes)];
					if(0 == memcmp(fourCCData, bytes, sizeof(bytes)))
						return 5;
				}
			}
		}
	}

	o = [dict objectForKey:PGLSItemContentTypes];
	if(o && [o containsObject:[self UTIType]]) return 4;

	o = [dict objectForKey:PGCFBundleTypeMIMETypesKey];
	if(o && [o containsObject:[self MIMEType]]) return 3;

	o = [dict objectForKey:PGCFBundleTypeOSTypesKey];
	if(o && [o containsObject:PGOSTypeToStringQuoted([self typeCode], NO)]) return 2;

	o = [dict objectForKey:PGCFBundleTypeExtensionsKey];
	if(o && [o containsObject:[[self extension] lowercaseString]]) return 1;

	//	the original code:
//	if([[dict objectForKey:PGBundleTypeFourCCsKey] containsObject:[self fourCCData]]) return 5;
//	if([[dict objectForKey:PGLSItemContentTypes] containsObject:[self UTIType]]) return 4;
//	if([[dict objectForKey:PGCFBundleTypeMIMETypesKey] containsObject:[self MIMEType]]) return 3;
//	if([[dict objectForKey:PGCFBundleTypeOSTypesKey] containsObject:PGOSTypeToStringQuoted([self typeCode], NO)]) return 2;
//	if([[dict objectForKey:PGCFBundleTypeExtensionsKey] containsObject:[[self extension] lowercaseString]]) return 1;
	return 0;
}

- (NSArray *)adapterClassesForNode:(PGNode *)node
{
	NSParameterAssert(node);
	NSDictionary *const types = [PGResourceAdapter typesDictionary];
	NSMutableDictionary *const adapterByPriority = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:0], [PGResourceAdapter class], nil];
	uint8_t fourCCData[4] = {0,0,0,0};	//	2023/10/14
	for(NSString *const classString in types) {
		Class const class = NSClassFromString(classString);
		if(!class) continue;
		NSDictionary *const typeDict = [types objectForKey:classString];
		NSUInteger const p = [self _matchPriorityForTypeDictionary:typeDict withFourCCData:fourCCData];
		if(p) [adapterByPriority setObject:[NSNumber numberWithUnsignedInteger:p] forKey:(id<NSCopying>)class];
	}
	return [adapterByPriority keysSortedByValueUsingSelector:@selector(compare:)];
}

- (NSArray *)adaptersForNode:(PGNode *)node
{
	NSMutableArray *const adapters = [NSMutableArray array];
	for(Class const class in [self adapterClassesForNode:node])
#if __has_feature(objc_arc)
		[adapters addObject:[[class alloc] initWithNode:node dataProvider:self]];
#else
		[adapters addObject:[[[class alloc] initWithNode:node dataProvider:self] autorelease]];
#endif
	return adapters;
}

@end
