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
#import "PGDocument.h"

// Models
#import "PGNode.h"
#import "PGGenericImageAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGSubscription.h"
#import "PGBookmark.h"

// Views
#import "PGImageView.h"

// Controllers
#import "PGDocumentController.h"
#import "PGBookmarkController.h"
#import "PGDisplayController.h"

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

NSString *const PGDocumentWillRemoveNodesNotification          = @"PGDocumentWillRemoveNodes";
NSString *const PGDocumentSortedNodesDidChangeNotification     = @"PGDocumentSortedNodesDidChange";
NSString *const PGDocumentNodeIsViewableDidChangeNotification  = @"PGDocumentNodeIsViewableDidChange";
NSString *const PGDocumentNodeThumbnailDidChangeNotification   = @"PGDocumentNodeThumbnailDidChange";
NSString *const PGDocumentNodeDisplayNameDidChangeNotification = @"PGDocumentNodeDisplayNameDidChange";

NSString *const PGDocumentNodeKey = @"PGDocumentNode";
NSString *const PGDocumentRemovedChildrenKey = @"PGDocumentRemovedChildren";
NSString *const PGDocumentUpdateRecursivelyKey = @"PGDocumentUpdateRecursively";

//#define PGDocumentMaxCachedNodes 3	//	too small (machines now have 8GB+ of RAM)
#define PGDocumentMaxCachedNodes 128	//	2023/10/21 this should not be a hardcoded number; it should use a heuristic based on the app's resource useage

#if __has_feature(objc_arc)

@interface PGDocument ()

@property (nonatomic, strong) PGSubscription *subscription;
@property (nonatomic, strong) NSMutableArray<PGNode *> *cachedNodes;
@property (nonatomic, strong) NSOperationQueue *operationQueue;

@property (nonatomic, strong) PGNode *storedNode;
@property (nonatomic, strong) PGImageView *storedImageView;
@property (nonatomic, assign) NSSize storedOffset;
@property (nonatomic, strong) NSString *storedQuery;
@property (nonatomic, assign) NSRect storedFrame;

@property (nonatomic, strong) PGDisplayableIdentifier *initialIdentifier;
@property (nonatomic, assign) BOOL openedBookmark;
//@property (nonatomic, strong) PGDisplayController *displayController;
@property (nonatomic, strong) NSMenu *pageMenu;
@property (nonatomic, strong) PGActivity *activity;

@property (nonatomic, assign) NSUInteger processingNodeCount;
@property (nonatomic, assign) BOOL sortedChildrenChanged;

- (PGNode *)_initialNode;
- (void)_setInitialIdentifier:(PGResourceIdentifier *)ident;
- (void)_closeWithFileSystemObjectDeleted:(BOOL)deleted;

@end

#else

@interface PGDocument(Private)

- (PGNode *)_initialNode;
- (void)_setInitialIdentifier:(PGResourceIdentifier *)ident;
- (void)_closeWithFileSystemObjectDeleted:(BOOL)deleted;

@end

#endif

//	MARK: -
@implementation PGDocument

- (instancetype)initWithIdentifier:(PGDisplayableIdentifier *)ident
{
	if((self = [self init])) {
#if __has_feature(objc_arc)
		_rootIdentifier = ident;
#else
		_rootIdentifier = [ident retain];
#endif
		_node = [[PGNode alloc] initWithParent:self identifier:ident];
		_node.dataProvider = [PGDataProvider providerWithResourceIdentifier:ident];
		[_rootIdentifier PG_addObserver:self selector:@selector(identifierIconDidChange:) name:PGDisplayableIdentifierIconDidChangeNotification];
#if __has_feature(objc_arc)
		_subscription = [_rootIdentifier subscriptionWithDescendents:YES];
#else
		_subscription = [[_rootIdentifier subscriptionWithDescendents:YES] retain];
#endif
		[_subscription PG_addObserver:self selector:@selector(subscriptionEventDidOccur:) name:PGSubscriptionEventDidOccurNotification];
		[self noteSortedChildrenDidChange];
	}
	return self;
}
- (instancetype)initWithURL:(NSURL *)aURL
{
	return [self initWithIdentifier:aURL.PG_displayableIdentifier];
}
- (instancetype)initWithBookmark:(PGBookmark *)aBookmark
{
	if((self = [self initWithIdentifier:aBookmark.documentIdentifier])) {
		[self openBookmark:aBookmark];
	}
	return self;
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGDisplayController *)displayController
{
	return [[_displayController retain] autorelease];
}
#endif
- (void)setDisplayController:(PGDisplayController *)controller
{
	if(controller == _displayController) return;
	if(_displayController.activeDocument == self)
		[_displayController setActiveDocument:nil closeIfAppropriate:YES];
#if __has_feature(objc_arc)
	_displayController = controller;
#else
	[_displayController release];
	_displayController = [controller retain];
#endif
	[_displayController setActiveDocument:self closeIfAppropriate:NO];
	[_displayController synchronizeWindowTitleWithDocumentName];
}
- (BOOL)isOnline
{
	return !self.rootIdentifier.isFileIdentifier;
}
- (NSMenu *)pageMenu
{
	return _pageMenu;
}
- (BOOL)isProcessingNodes
{
	return _processingNodeCount > 0;
}
- (void)setProcessingNodes:(BOOL)flag
{
	NSParameterAssert(flag || _processingNodeCount);
	_processingNodeCount += flag ? 1 : -1;
	if(!_processingNodeCount && _sortedChildrenChanged) [self noteSortedChildrenDidChange];
}

//	MARK: -

- (void)getStoredNode:(out PGNode **)outNode imageView:(out PGImageView **)outImageView offset:(out NSSize *)outOffset query:(out NSString **)outQuery
{
	if(_storedNode) {
#if __has_feature(objc_arc)
		*outNode = _storedNode;
#else
		*outNode = [_storedNode autorelease];
#endif
		_storedNode = nil;

#if __has_feature(objc_arc)
		*outImageView = _storedImageView;
#else
		*outImageView = [_storedImageView autorelease];
#endif
		_storedImageView = nil;

		*outOffset = _storedOffset;
#if __has_feature(objc_arc)
		*outQuery = _storedQuery;
#else
		*outQuery = [_storedQuery autorelease];
#endif
		_storedQuery = nil;
	} else {
		*outNode = self._initialNode;
#if __has_feature(objc_arc)
		*outImageView = [PGImageView new];
#else
		*outImageView = [[[PGImageView alloc] init] autorelease];
#endif
		*outQuery = @"";
	}
}
- (void)storeNode:(PGNode *)node imageView:(PGImageView *)imageView offset:(NSSize)offset query:(NSString *)query
{
#if __has_feature(objc_arc)
	_storedNode = node;
	_storedImageView = imageView;
#else
	[_storedNode autorelease];
	_storedNode = [node retain];
	[_storedImageView autorelease];
	_storedImageView = [imageView retain];
#endif
	_storedOffset = offset;
#if !__has_feature(objc_arc)
	[_storedQuery autorelease];
#endif
	_storedQuery = [query copy];
}

- (BOOL)getStoredWindowFrame:(out NSRect *)outFrame
{
	if(NSEqualRects(_storedFrame, NSZeroRect)) return NO;
	if(outFrame) *outFrame = _storedFrame;
	_storedFrame = NSZeroRect;
	return YES;
}
- (void)storeWindowFrame:(NSRect)frame
{
	NSParameterAssert(!NSEqualRects(frame, NSZeroRect));
	_storedFrame = frame;
}

//	MARK: -

- (void)createUI
{
	BOOL const new = !self.displayController;
	if(new) self.displayController = [PGDocumentController sharedDocumentController].displayControllerForNewDocument;
	else [self.displayController setActiveDocument:self closeIfAppropriate:NO];
	[[PGDocumentController sharedDocumentController] noteNewRecentDocument:self];
	[self.displayController showWindow:self];
	if(new && !_openedBookmark) {
		PGBookmark *const bookmark = [[PGBookmarkController sharedBookmarkController] bookmarkForIdentifier:self.rootIdentifier];
		if(bookmark && [self.node.resourceAdapter nodeForIdentifier:bookmark.fileIdentifier]) [self.displayController offerToOpenBookmark:bookmark];
	}
}
- (void)close
{
	[self _closeWithFileSystemObjectDeleted:NO];
}
- (void)openBookmark:(PGBookmark *)aBookmark
{
	[self _setInitialIdentifier:aBookmark.fileIdentifier];
	PGNode *const initialNode = self._initialNode;
	if(PGEqualObjects(initialNode.identifier, aBookmark.fileIdentifier)) {
		_openedBookmark = YES;
		[self.displayController activateNode:initialNode];
		[[PGBookmarkController sharedBookmarkController] removeBookmark:aBookmark];
	} else NSBeep();
}

//	MARK: -

- (void)noteNode:(PGNode *)node willRemoveNodes:(NSArray *)anArray
{
	PGNode *newStoredNode = [_storedNode.resourceAdapter sortedViewableNodeNext:YES afterRemovalOfChildren:anArray fromNode:node];
	if(!newStoredNode) newStoredNode = [_storedNode.resourceAdapter sortedViewableNodeNext:NO afterRemovalOfChildren:anArray fromNode:node];
	if(_storedNode != newStoredNode) {
#if __has_feature(objc_arc)
		_storedNode = newStoredNode;
#else
		[_storedNode release];
		_storedNode = [newStoredNode retain];
#endif
		_storedOffset = PGRectEdgeMaskToSizeWithMagnitude(PGReadingDirectionAndLocationToRectEdgeMask(self.readingDirection, PGHomeLocation), CGFLOAT_MAX);
	}
	[self PG_postNotificationName:PGDocumentWillRemoveNodesNotification userInfo:@{PGDocumentNodeKey: node, PGDocumentRemovedChildrenKey: anArray}];
}
- (void)noteSortedChildrenDidChange
{
	if(self.processingNodes) {
		_sortedChildrenChanged = YES;
		return;
	}
	NSInteger const numberOfOtherItems = [PGDocumentController sharedDocumentController].defaultPageMenu.numberOfItems;
	while(_pageMenu.numberOfItems > numberOfOtherItems) [_pageMenu removeItemAtIndex:numberOfOtherItems];
	[self.node addToMenu:_pageMenu flatten:YES];
	if(_pageMenu.numberOfItems > numberOfOtherItems) [_pageMenu insertItem:[NSMenuItem separatorItem] atIndex:numberOfOtherItems];
	[self PG_postNotificationName:PGDocumentSortedNodesDidChangeNotification];
}
- (void)noteNodeIsViewableDidChange:(PGNode *)node
{
	if(_node) [self PG_postNotificationName:PGDocumentNodeIsViewableDidChangeNotification userInfo:@{PGDocumentNodeKey: node}];
}
- (void)noteNodeThumbnailDidChange:(PGNode *)node recursively:(BOOL)flag
{
	if(node) [self PG_postNotificationName:PGDocumentNodeThumbnailDidChangeNotification userInfo:@{PGDocumentNodeKey: node, PGDocumentUpdateRecursivelyKey: @(flag)}];
}
- (void)noteNodeDisplayNameDidChange:(PGNode *)node
{
	if(!_node) return;
	if(self.node == node) [self.displayController synchronizeWindowTitleWithDocumentName];
	[self PG_postNotificationName:PGDocumentNodeDisplayNameDidChangeNotification userInfo:@{PGDocumentNodeKey: node}];
}
- (void)noteNodeDidCache:(PGNode *)node
{
	if(!_node) return;
	[_cachedNodes removeObjectIdenticalTo:node];
	[_cachedNodes insertObject:node atIndex:0];
	while(_cachedNodes.count > PGDocumentMaxCachedNodes) {
		[_cachedNodes.lastObject.resourceAdapter clearCache];
		[_cachedNodes removeLastObject];
	}
}
- (void)addOperation:(NSOperation *)operation
{
	[_operationQueue addOperation:operation];
}

//	MARK: -

- (void)identifierIconDidChange:(NSNotification *)aNotif
{
	[self.displayController synchronizeWindowTitleWithDocumentName];
}
- (void)subscriptionEventDidOccur:(NSNotification *)aNotif
{
	NSParameterAssert(aNotif);
	NSDictionary *const userInfo = aNotif.userInfo;
	NSString *const path = userInfo[PGSubscriptionPathKey];
	NSUInteger const flags = [userInfo[PGSubscriptionRootFlagsKey] unsignedIntegerValue];
	BOOL const isDeleteOrRevoke = !!(flags & (NOTE_DELETE | NOTE_REVOKE));
	PGResourceIdentifier *const ident = isDeleteOrRevoke ? nil : [path PG_fileURL].PG_resourceIdentifier;
	//	NB: if the identifier is a PGAliasIdentifier instance, the call to
	//	-isEqual: will update the internal bookmark and trigger the posting
	//	of a PGDisplayableIdentifierDisplayNameDidChangeNotification to
	//	-[PGDocumentController recentDocumentIdentifierDidChange:]
	BOOL const isEventForRootNode = ident ? [_rootIdentifier isEqual:ident] :
		[[NSURL fileURLWithPath:path] isEqual:[_rootIdentifier URLByFollowingAliases:NO]];

	if(isDeleteOrRevoke) {
		//	if the root node represents the deleted object then this
		//	document must be removed from the Open Recent sub-menu;
		//	do this by passing YES to -_closeWithFileSystemObjectDeleted:
		return [self _closeWithFileSystemObjectDeleted:isEventForRootNode];
	}

	//	if the root node represents the moved/renamed file/folder then
	//	update the represented document in NSDocument; this will then
	//	update the title bar's document icon and command-clicking
	//	the title bar will display the file/folder's new location/name
	if(isEventForRootNode) {
		[_displayController synchronizeWindowTitleWithDocumentName];
		return;	//	no children need updating so exit now
	}

	PGNode *const node = [self.node.resourceAdapter nodeForIdentifier:ident];
	if(node)
		[node noteFileEventDidOccurDirect:YES];
}

//	MARK: - PGDocument(Private)

- (PGNode *)_initialNode
{
	PGNode *const node = [self.node.resourceAdapter nodeForIdentifier:_initialIdentifier];
	return node ? node : [self.node.resourceAdapter sortedViewableNodeFirst:YES];
}
- (void)_setInitialIdentifier:(PGResourceIdentifier *)ident
{
	if(ident == _initialIdentifier) return;
	NSAssert([ident isKindOfClass:PGDisplayableIdentifier.class], @"");
#if __has_feature(objc_arc)
	_initialIdentifier = (PGDisplayableIdentifier *)ident;
#else
	[_initialIdentifier release];
	_initialIdentifier = (PGDisplayableIdentifier *)[ident retain];
#endif
}
- (void)_closeWithFileSystemObjectDeleted:(BOOL)deleted
{	//	2023/10/31
	PGDocumentController *dc = [PGDocumentController sharedDocumentController];
	if(deleted)
		[dc noteDeletedRecentDocument:self];
	else
		[dc noteNewRecentDocument:self];
	[self setDisplayController:nil];
	[dc removeDocument:self];
}

//	MARK: - PGPrefObject

- (void)setShowsInfo:(BOOL)flag
{
	super.showsInfo = flag;
	[[PGPrefObject globalPrefObject] setShowsInfo:flag];
}
- (void)setShowsThumbnails:(BOOL)flag
{
	super.showsThumbnails = flag;
	[[PGPrefObject globalPrefObject] setShowsThumbnails:flag];
}
- (void)setReadingDirection:(PGReadingDirection)aDirection
{
	super.readingDirection = aDirection;
	[[PGPrefObject globalPrefObject] setReadingDirection:aDirection];
}
- (void)setImageScaleMode:(PGImageScaleMode)aMode
{
	super.imageScaleMode = aMode;
	[[PGPrefObject globalPrefObject] setImageScaleMode:aMode];
}
- (void)setImageScaleFactor:(CGFloat)factor animate:(BOOL)flag
{
	[super setImageScaleFactor:factor animate:flag];
	[[PGPrefObject globalPrefObject] setImageScaleFactor:factor animate:flag];
}
- (void)setAnimatesImages:(BOOL)flag
{
	super.animatesImages = flag;
	[[PGPrefObject globalPrefObject] setAnimatesImages:flag];
}
- (void)setSortOrder:(PGSortOrder)anOrder
{
	if(self.sortOrder != anOrder) {
		super.sortOrder = anOrder;
		[self.node noteSortOrderDidChange];
		[self noteSortedChildrenDidChange];
	}
	[[PGPrefObject globalPrefObject] setSortOrder:anOrder];
}
- (void)setTimerInterval:(NSTimeInterval)interval
{
	super.timerInterval = interval;
	[[PGPrefObject globalPrefObject] setTimerInterval:interval];
}
- (void)setBaseOrientation:(PGOrientation)anOrientation
{
	super.baseOrientation = anOrientation;
	[[PGPrefObject globalPrefObject] setBaseOrientation:anOrientation];
}

//	MARK: - NSObject

- (instancetype)init
{
	if((self = [super init])) {
		_pageMenu = [[PGDocumentController sharedDocumentController].defaultPageMenu copy];
		[_pageMenu addItem:[NSMenuItem separatorItem]];
		_cachedNodes = [NSMutableArray new];
		_operationQueue = [[NSOperationQueue alloc] init];
		_operationQueue.maxConcurrentOperationCount = 2; // Our operations (thumbnail generation) are usually IO-bound, so too much concurrency is detrimental to performance.
		_activity = [[PGActivity alloc] initWithOwner:self];
		_activity.parentActivity = [PGActivity applicationActivity];
	}
	return self;
}
- (void)dealloc
{
	[self PG_removeObserver];
	[_node.resourceAdapter.activity cancel:self];
	[_node detachFromTree];
	[_operationQueue cancelAllOperations];
	[_activity invalidate];

#if !__has_feature(objc_arc)
	[_rootIdentifier release];
	[_node release];
	[_subscription release];
	[_cachedNodes release];
	[_operationQueue release];
	[_storedNode release];
	[_storedImageView release];
	[_storedQuery release];
	[_initialIdentifier release];
	[_displayController release];
	[_pageMenu release];
	[_activity release];
	[super dealloc];
#endif
}

//	MARK: - <PGActivityOwner>

- (PGActivity *)activity
{
#if __has_feature(objc_arc)
	return _activity;
#else
	return [[_activity retain] autorelease];
#endif
}
- (NSString *)descriptionForActivity:(PGActivity *)activity
{
	return self.node.identifier.displayName;
}

//	MARK: - <PGNodeParent>

- (PGDocument *)document
{
	return self;
}
- (PGContainerAdapter *)containerAdapter
{
	return nil;
}

@end
