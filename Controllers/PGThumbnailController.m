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
#import "PGThumbnailController.h"

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGContainerAdapter.h"
#import "PGResourceIdentifier.h"

// Views
#import "PGClipView.h"
#import "PGBezelPanel.h"
#import "PGThumbnailBrowser.h"
#import "PGThumbnailView.h"
#import "PGThumbnailInfoView.h"

// Controllers
#import "PGDisplayController.h"
#import "PGDocumentController.h"
#import "PGFullSizeContentController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

//	should match #define in PGDisplayController.m
	//	does not work well so disabled until it's fixed
#define FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE	false

NSString *const PGThumbnailControllerContentInsetDidChangeNotification = @"PGThumbnailControllerContentInsetDidChange";

#define PGMaxVisibleColumns (NSUInteger)3

//	MARK: -

#if __has_feature(objc_arc)

@interface PGThumbnailController () <PGFullSizeContentDelegate>

@property (nonatomic, strong) PGBezelPanel *window;
@property (nonatomic, weak) PGThumbnailBrowser *browser;

@property (nonatomic, strong) PGBezelPanel *infoWindow;	//	2023/10/02 added
@property (nonatomic, weak) NSView *infoView;	//	2023/10/02 added [PGThumbnailInfoView]

#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
@property (nonatomic, strong) NSTrackingArea *browserTrackingArea;
@property (nonatomic, assign) BOOL parentWindowIsAnimating;
#else
@property (nonatomic, assign) BOOL parentWindowIsAnimating;
#endif

- (void)_updateInfoWindowFrame;	//	2023/10/02
- (void)_updateWindowFrame;

@end

#else

@interface PGThumbnailController(Private) <PGFullSizeContentProtocol>

- (void)_updateInfoWindowFrame;	//	2023/10/02
- (void)_updateWindowFrame;

@end

#endif

//	MARK: -
@implementation PGThumbnailController

+ (BOOL)canShowThumbnailsForDocument:(PGDocument *)aDoc
{
	return [[[aDoc node] resourceAdapter] hasViewableNodeCountGreaterThan:1];
}
+ (BOOL)shouldShowThumbnailsForDocument:(PGDocument *)aDoc
{
	return [aDoc showsThumbnails] && [self canShowThumbnailsForDocument:aDoc];
}

//	MARK: - PGThumbnailController

#if !__has_feature(objc_arc)
@synthesize displayController = _displayController;
#endif
- (void)setDisplayController:(PGDisplayController *)aController
{
	if(aController == _displayController) return;
	[[_window parentWindow] removeChildWindow:_window];
	[_displayController PG_removeObserver:self name:PGDisplayControllerActiveNodeDidChangeNotification];
	[_displayController PG_removeObserver:self name:PGDisplayControllerActiveNodeWasReadNotification];
	[[_displayController clipView] PG_removeObserver:self name:PGClipViewBoundsDidChangeNotification];
	[[_displayController window] PG_removeObserver:self name:NSWindowDidResizeNotification];
	[[_displayController windowForSheet] PG_removeObserver:self name:NSWindowWillBeginSheetNotification];
	[[_displayController windowForSheet] PG_removeObserver:self name:NSWindowDidEndSheetNotification];
	_displayController = aController;
	[_displayController PG_addObserver:self selector:@selector(displayControllerActiveNodeDidChange:) name:PGDisplayControllerActiveNodeDidChangeNotification];
	[_displayController PG_addObserver:self selector:@selector(displayControllerActiveNodeWasRead:) name:PGDisplayControllerActiveNodeWasReadNotification];
	[[_displayController clipView] PG_addObserver:self selector:@selector(clipViewBoundsDidChange:) name:PGClipViewBoundsDidChangeNotification];
	[[_displayController window] PG_addObserver:self selector:@selector(parentWindowDidResize:) name:NSWindowDidResizeNotification];
	[[_displayController windowForSheet] PG_addObserver:self selector:@selector(parentWindowWillBeginSheet:) name:NSWindowWillBeginSheetNotification];
	[[_displayController windowForSheet] PG_addObserver:self selector:@selector(parentWindowDidEndSheet:) name:NSWindowDidEndSheetNotification];
	[_window setIgnoresMouseEvents:!![[_displayController windowForSheet] attachedSheet]];
	[self setDocument:[_displayController activeDocument]];
	[self display];
}
#if !__has_feature(objc_arc)
@synthesize document = _document;
#endif
- (void)setDocument:(PGDocument *)aDoc
{
	if(aDoc == _document) return;
	[_document PG_removeObserver:self name:PGPrefObjectBaseOrientationDidChangeNotification];
	[_document PG_removeObserver:self name:PGDocumentNodeThumbnailDidChangeNotification];
	[_document PG_removeObserver:self name:PGDocumentSortedNodesDidChangeNotification];
	[_document PG_removeObserver:self name:PGDocumentNodeIsViewableDidChangeNotification];
	_document = aDoc;
	[_document PG_addObserver:self selector:@selector(documentNodeThumbnailDidChange:) name:PGDocumentNodeThumbnailDidChangeNotification];
	[_document PG_addObserver:self selector:@selector(documentSortedNodesDidChange:) name:PGDocumentSortedNodesDidChangeNotification];
	[_document PG_addObserver:self selector:@selector(documentNodeIsViewableDidChange:) name:PGDocumentNodeIsViewableDidChangeNotification];
	[_document PG_addObserver:self selector:@selector(documentBaseOrientationDidChange:) name:PGPrefObjectBaseOrientationDidChangeNotification];
	[self _updateWindowFrame];
	[self _updateInfoWindowFrame];	//	2023/10/02
	[self displayControllerActiveNodeDidChange:nil];
	[self documentBaseOrientationDidChange:nil];
//	[self _updateWindowFrame];
}
- (PGInset)contentInset
{
	return PGMakeInset(NSWidth(_window.frame), 0.0f, 0.0f, 0.0f);
}
- (NSSet *)selectedNodes
{
	return [_browser selection];
}
- (void)setSelectedNodes:(NSSet *)selectedNodes {	//	2023/10/02 was readonly
	_browser.selection = selectedNodes;
}

//	MARK: -

- (void)selectAll {
	[_browser selectAll];
}
- (void)display
{
#if !__has_feature(objc_arc)
	if(_selfRetained) [self autorelease];
	_selfRetained = NO;
#endif

	[[[self displayController] window] addChildWindow:_window ordered:NSWindowAbove];
	[self _updateWindowFrame];

	[_window removeChildWindow:_infoWindow];
	[_window addChildWindow:_infoWindow ordered:NSWindowAbove];	//	2023/10/02
//NSLog(@"[_window addChildWindow:_infoWindow]");
	[self _updateInfoWindowFrame];	//	2023/10/02
}
- (void)selectionNeedsDisplay {	//	2023/11/12
	[_browser selectionNeedsDisplay];
}
- (void)fadeOut
{
#if !__has_feature(objc_arc)
	if(!_selfRetained) [self retain];
	_selfRetained = YES;
#endif
	_infoView.hidden = YES;
	[_window fadeOut];
}

//	MARK: -

- (void)displayControllerActiveNodeDidChange:(NSNotification *)aNotif
{
	//	2023/08/21 only process notifications which are targeting this instance;
	//	this stops the app from crashing when the thumbnail view is shown/hidden
	//	while in fullscreen with more than 1 document opened.
	if(aNotif) {
		if([aNotif.userInfo objectForKey:@"PGDocument"] != _document)
			return;

		PGNode *const node = [aNotif.userInfo objectForKey:@"PGNode"];
		NSAssert(node, @"node");
		[_browser setSelection:node ? [NSSet setWithObject:node] : nil];
	} else
		[_browser setSelection:[[self displayController] selectedNodes]];
}
- (void)displayControllerActiveNodeWasRead:(NSNotification *)aNotif
{
	[self clipViewBoundsDidChange:nil];
}
- (void)clipViewBoundsDidChange:(NSNotification *)aNotif
{
	[_browser redisplayItem:[[self displayController] activeNode] recursively:NO];

//	[self _updateInfoWindowFrame];	//	2023/10/14
}
- (void)parentWindowDidResize:(NSNotification *)aNotif
{
	[self _updateWindowFrame];
	[self _updateInfoWindowFrame];	//	2023/10/14
}
- (void)parentWindowWillTransitionToScreenFrame:(NSRect)parentWindowFrame {
	[self _updateWindowFrameWithContentRect:parentWindowFrame
							  usingAnimator:YES
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
							 titleBarHeight:0
#endif
	];

	if(_infoView.hidden)
		return;

	parentWindowFrame = NSMakeRect(NSMinX(parentWindowFrame), NSMinY(parentWindowFrame),
									_window.frame.size.width, NSHeight(parentWindowFrame));
	[self _updateInfoWindowFrameWithContentRect:parentWindowFrame usingAnimator:YES];
}
//- (void)parentWindowWillExitFullScreenToScreenFrame:(NSRect)parentWindowFrame {
//	[self _updateWindowFrameWithContentRect:parentWindowFrame usingAnimator:YES];
//}
- (void)parentWindowWillBeginSheet:(NSNotification *)aNotif
{
	[_window setIgnoresMouseEvents:YES];
}
- (void)parentWindowDidEndSheet:(NSNotification *)aNotif
{
	[_window setIgnoresMouseEvents:NO];
}

//	MARK: -

- (void)documentNodeThumbnailDidChange:(NSNotification *)aNotif
{
	[_browser redisplayItem:[[aNotif userInfo] objectForKey:PGDocumentNodeKey] recursively:[[[aNotif userInfo] objectForKey:PGDocumentUpdateRecursivelyKey] boolValue]];
}
- (void)documentBaseOrientationDidChange:(NSNotification *)aNotif
{
	[_browser setThumbnailOrientation:[[self document] baseOrientation]];
}
- (void)documentSortedNodesDidChange:(NSNotification *)aNotif
{
	[_browser setSelection:[_browser selection]];
}
- (void)documentNodeIsViewableDidChange:(NSNotification *)aNotif
{
	[_browser redisplayItem:[[aNotif userInfo] objectForKey:PGDocumentNodeKey] recursively:NO];
}

//	MARK: - PGThumbnailController(Private)

//	ensures that whether in macOS-fullscreen or Sequential-fullscreen,
//	the app behaves the same
- (BOOL)_isInAnyFullScreenMode {
	return PGDocumentController.sharedDocumentController.fullscreen ||
			0 != (self.window.styleMask & NSWindowStyleMaskFullScreen);
}

- (void)_updateInfoWindowFrameWithContentRect:(NSRect)r usingAnimator:(BOOL)useAnimator
{
	NSRect const cf = [(PGThumbnailInfoView*)_infoView bezelPanel:_infoWindow
											  frameForContentRect:r
															scale:(CGFloat)1.0f];
	CGFloat const infoWindowHeight = NSHeight(cf);
#if 1	//	2023/10/14 Info window is displayed at the top of thumbnail view
	//	2023/10/14 when in "use entire screen" mode, the info window actually appears
	//	below the menu bar (notch) area but why it does so is unknown: the frame rect
	//	Y co-ord is actually correct and *should* make the Info window appear in the
	//	notch area but the OS must be clipping it to under the notch somehow.
	NSRect const infoWindowFrame = NSMakeRect(NSMaxX(r) - _browser.columnWidth,
												NSMaxY(r) - infoWindowHeight,	//	Y co-ords are bottom-upwards
												_browser.columnWidth, infoWindowHeight);
#else	//	info window is displayed at the bottom of thumbnail view
	NSRect const infoWindowFrame = NSMakeRect(NSMaxX(r) - _browser.columnWidth,
												NSMinY(r),	//	Y co-ords are bottom-upwards
												_browser.columnWidth, infoWindowHeight);
#endif
//NSLog(@"infoWindowFrame = (%5.2f, %5.2f) [%5.2f x %5.2f]",
//infoWindowFrame.origin.x, infoWindowFrame.origin.y, infoWindowFrame.size.width, infoWindowFrame.size.height);

	if(NSEqualRects(infoWindowFrame, _infoWindow.frame))
		return;

	if(useAnimator)
		[_infoWindow.animator setFrame:infoWindowFrame display:YES];
	else
		[_infoWindow setFrame:infoWindowFrame display:YES];
}

- (void)_updateInfoWindowFrame	//	2023/10/02
{
	if(_infoView.hidden)
		return;

	[self _updateInfoWindowFrameWithContentRect:_window.frame usingAnimator:NO];
}

- (void)_updateWindowFrameWithContentRect:(NSRect)r
							usingAnimator:(BOOL)useAnimator
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
						   titleBarHeight:(CGFloat)titleBarHeight
#endif
{
#if 1	//	2021/07/21 modernized
	NSRect const newFrame = NSMakeRect(NSMinX(r), NSMinY(r),
									   MIN(_browser.numberOfColumns, PGMaxVisibleColumns) * _browser.columnWidth,
									   NSHeight(r));
#else
	NSRect const newFrame = NSMakeRect(NSMinX(r), NSMinY(r),
		(MIN([_browser numberOfColumns], PGMaxVisibleColumns) * [_browser columnWidth]) * [_window userSpaceScaleFactor],
									   NSHeight(r));
#endif

//NSLog(@"_updateWindowFrameWithContentRect:usingAnimator:titleBarHeight: equal-rects %u", NSEqualRects(newFrame, _window.frame));
	if(!NSEqualRects(newFrame, _window.frame)) {
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
		if(_browserTrackingArea) {
//NSLog(@"-_browser removeTrackingArea:");
			[_browser removeTrackingArea:_browserTrackingArea];
	#if !__has_feature(objc_arc)
			[_browserTrackingArea release];
	#endif
			_browserTrackingArea = nil;
		}
#else
#endif

		if(useAnimator)
			[_window.animator setFrame:newFrame display:YES];
		else
			[_window setFrame:newFrame display:YES];
	}

#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
	if(0 == titleBarHeight || useAnimator || _browserTrackingArea || [self _isInAnyFullScreenMode])
		return;

	//	if in full-size-content mode and not animating and not already tracking
	//	and not in full-screen mode then create a tracking area to show/hide
	//	the standard close/miniaturize/zoom buttons when the mouse moves in/out
	//	of the tracking area

	//	for unknown reasons, -convertRect: does not convert to _browser's co-ord system
	//	so just create the tracking rect directly:
	NSRect const trackingRect = NSMakeRect(0, NSHeight(newFrame) - titleBarHeight,
											NSWidth(newFrame), titleBarHeight);
//	NSRect const trackingRect = [_browser convertRect:NSMakeRect(NSMinX(newFrame), NSMaxY(newFrame) - titleBarHeight,
//																 NSWidth(newFrame), titleBarHeight)
//											 fromView:nil];
	_browserTrackingArea = [[NSTrackingArea alloc] initWithRect:trackingRect
													//	options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways)
														options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
														  owner:self
													   userInfo:nil];//(nullable NSDictionary<id, id> *)userInfo
	[_browser addTrackingArea:_browserTrackingArea];

//NSLog(@"newFrame = (%5.2f, %5.2f) [%5.2f x %5.2f]",
//newFrame.origin.x, newFrame.origin.y, newFrame.size.width, newFrame.size.height);

//NSLog(@"-_browser addTrackingArea: (%5.2f, %5.2f) [%5.2f x %5.2f]",
//trackingRect.origin.x, trackingRect.origin.y, trackingRect.size.width, trackingRect.size.height);
#else
#endif
}

- (void)_updateWindowFrame
{
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
#else
	if(_parentWindowIsAnimating) return;
#endif
	NSWindow *const p = [_displayController window];
	if(!p) return;
	NSRect r = [p PG_contentRect];
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
	//	if not in full-screen mode and in full-size-content mode and the
	//	parent window is not animating then ensure that a tracking area
	//	is created so that mousing into that area will allow the parent
	//	window's standard close/miniaturize/zoom buttons to be shown
	CGFloat const titleBarHeight = ![self _isInAnyFullScreenMode] &&
		0 != (p.styleMask & NSWindowStyleMaskFullSizeContentView) &&
		!_parentWindowIsAnimating ?
		[p standardWindowButton:NSWindowCloseButton].superview.frame.size.height: 0;

	[self _updateWindowFrameWithContentRect:r usingAnimator:NO titleBarHeight:titleBarHeight];
#else
	//	if (1) not in full-screen mode, and (2) in full-size-content mode
	//	then make sure the thumbnail columns do not obscure the window's
	//	standard close/miniaturize/zoom buttons
	if(![self _isInAnyFullScreenMode] && // was: if(!PGDocumentController.sharedDocumentController.fullscreen &&
		0 != (p.styleMask & NSWindowStyleMaskFullSizeContentView)) {
		CGFloat const titleBarHeight =
			[p standardWindowButton:NSWindowCloseButton].superview.frame.size.height;
		r.size.height -= titleBarHeight;
	}
	[self _updateWindowFrameWithContentRect:r usingAnimator:NO];
#endif
	[self PG_postNotificationName:PGThumbnailControllerContentInsetDidChangeNotification];
}

//	MARK: - NSObject

- (id)init
{
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_window = [PGThumbnailBrowser PG_bezelPanel];
#else
		_window = [[PGThumbnailBrowser PG_bezelPanel] retain];
#endif
		[_window setAutorecalculatesKeyViewLoop:YES];
		[_window setReleasedWhenClosed:NO];
		[_window setDelegate:self];
		[_window setAcceptsEvents:YES];

		_browser = [_window content];
		NSParameterAssert(nil != _browser && [_browser isKindOfClass:[PGThumbnailBrowser class]]);
		[_browser setDelegate:self];
		[_browser setDataSource:self];

#if __has_feature(objc_arc)
		_infoWindow = [PGThumbnailInfoView PG_bezelPanel];	//	2023/10/02 added
#else
		_infoWindow = [[PGThumbnailInfoView PG_bezelPanel] retain];	//	2023/10/02 added
#endif
		[_infoWindow setAutorecalculatesKeyViewLoop:NO];
		[_infoWindow setReleasedWhenClosed:NO];
		_infoView = [_infoWindow content];	//	2023/10/02 added
		_infoView.hidden = YES;
	}
	return self;
}
- (void)dealloc
{
	//	Instances of this class are owned by PGDisplayController.
//NSLog(@"PGThumbnailController -dealloc %p", self);
	[self PG_removeObserver];

#if !__has_feature(objc_arc)
	[_infoWindow release];	//	2023/10/02 added
#endif

	//	2023/08/16 bugfix: stop thumbnail browser from accessing this
	//	deallocated object
	[_browser setDelegate:nil];
	//	2023/08/16 bugfix: stop thumbnail browser and thumbnail views
	//	from accessing this deallocated object
	[_browser setDataSource:nil];

	//	2023/08/21 bugfix: stop displaying the thumbnail browser
	[_window orderOut:self];
	[_window setDelegate:nil];
#if !__has_feature(objc_arc)
	[_window release];
	#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
	[_browserTrackingArea release];
	#else
	#endif

	[super dealloc];
#endif
}

//	MARK: - <NSWindowDelegate>

- (void)windowDidBecomeKey:(NSNotification *)aNotif
{
	[[self displayController] thumbnailPanelDidBecomeKey:aNotif];
}
- (void)windowDidResignKey:(NSNotification *)aNotif
{
	[[self displayController] thumbnailPanelDidResignKey:aNotif];
}
- (void)windowWillClose:(NSNotification *)aNotif
{
#if !__has_feature(objc_arc)
	if(_selfRetained) [self autorelease];
	_selfRetained = NO;
#endif
}

//	MARK: - <NSTrackingArea owner>

#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
- (void)mouseEntered:(NSEvent *)event {
	NSAssert(nil != _browserTrackingArea, @"");
//NSLog(@"-mouseEntered:");
	_browser.needsDisplay = YES;
}
/* - (void)mouseMoved:(NSEvent *)event {
	NSAssert(nil != _browserTrackingArea, @"");
NSLog(@"-mouseMoved:");

	[_displayController mouseMoved:event];
} */
- (void)mouseExited:(NSEvent *)event {
	NSAssert(nil != _browserTrackingArea, @"");
//NSLog(@"-mouseExited:");
	_browser.needsDisplay = YES;
}
#endif

//	MARK: - <PGFullSizeContentProtocol>

- (void)fullSizeContentController:(PGFullSizeContentController *)controller
			   willStartAnimating:(NSWindow *)window {
//NSLog(@"-[PGThumbnailController fullSizeContentController:willStartAnimating:]");
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
	_parentWindowIsAnimating = YES;
#else
	_parentWindowIsAnimating = YES;	//	disable browser window resizing
#endif
}
- (void)fullSizeContentController:(PGFullSizeContentController *)controller
			   didFinishAnimating:(NSWindow *)window {
//NSLog(@"-[PGThumbnailController fullSizeContentController:didFinishAnimating:]");
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
	_parentWindowIsAnimating = NO;
	[self _updateWindowFrame];
#else
	_parentWindowIsAnimating = NO;	//	enable browser window resizing
#endif
}

//	MARK: - <PGThumbnailBrowserDataSource>

- (id)thumbnailBrowser:(PGThumbnailBrowser *)sender parentOfItem:(id)item
{
	PGNode *const parent = [(PGNode *)item parentNode];
	return [[self document] node] == parent && ![parent isViewable] ? nil : parent;
}
- (BOOL)thumbnailBrowser:(PGThumbnailBrowser *)sender itemCanHaveChildren:(id)item
{
	return [[item resourceAdapter] isContainer];
}

//	MARK: - <PGThumbnailBrowserDelegate>

- (void)thumbnailBrowserSelectionDidChange:(PGThumbnailBrowser *)sender
{
	NSSet *const selection = [sender selection];
	PGNode *const item = [selection anyObject];
	NSUInteger const count = [selection count];
	(void)[self.displayController tryToSetActiveNode:[(count == 1 ? item : [(PGNode *)item parentNode]) viewableAncestor]
											 forward:YES];

	//	2023/10/02 when > 1 node is selected, show and update the Info window
	//	otherwise hide it
	BOOL const showInfoWindow = count > 1;
	_infoView.hidden = !showInfoWindow;
	if(showInfoWindow) {
		uint64_t byteSizeTotal = 0;
		for(PGNode *const node in selection) {
//NSLog(@"\t%@: isContainer %u", node.identifier.displayName, node.resourceAdapter.isContainer);
		//	NSParameterAssert(!node.resourceAdapter.isContainer);
		//	NSParameterAssert(node.isViewable);
			NSParameterAssert(node.dataProvider);
			if(node.dataProvider.hasData)
				byteSizeTotal += node.dataProvider.dataByteSize;
			else {
				uint64_t const bsoac = node.resourceAdapter.byteSizeOfAllChildren;
				if(ULONG_MAX != bsoac)
					byteSizeTotal += bsoac;
			}
		//	NSParameterAssert(node.dataProvider.dataLength);
		//	byteSizeTotal += node.dataProvider.dataLength.unsignedLongValue;
		}
		[(PGThumbnailInfoView*)_infoView setImageCount:count byteSizeTotal:byteSizeTotal];
		[self _updateInfoWindowFrame];
	}
/*	else {	//	show the address of the active node (this is a debugging aid)
		static uint8_t ii = 0;
		[(PGThumbnailInfoView*)_infoView setImageCount:++ii % 10
										 byteSizeTotal:_displayController.activeNode];
		_infoView.hidden = NO;
		[self _updateInfoWindowFrame];
	}	*/
}
- (void)thumbnailBrowser:(PGThumbnailBrowser *)sender numberOfColumnsDidChangeFrom:(NSUInteger)oldCount
{
	if(MIN(oldCount, PGMaxVisibleColumns) != MIN([sender numberOfColumns], PGMaxVisibleColumns))
		[self _updateWindowFrame];
}

//	MARK: - <PGThumbnailViewDataSource>

- (NSArray *)itemsForThumbnailView:(PGThumbnailView *)sender
{
	PGNode *const item = [sender representedObject];
	if(item)
		return [[item resourceAdapter] isContainer] ?
				[(PGContainerAdapter *)[item resourceAdapter] sortedChildren] : nil;

	PGNode *const root = [[self document] node];
	if([root isViewable])
		return [root PG_asArray];

	return [[root resourceAdapter] isContainer] ?
			[(PGContainerAdapter *)[root resourceAdapter] sortedChildren] : nil;
}
- (NSImage *)thumbnailView:(PGThumbnailView *)sender thumbnailForItem:(id)item
{
	return [[item resourceAdapter] thumbnail];
}
- (NSString *)thumbnailView:(PGThumbnailView *)sender labelForItem:(id)item
{
	return [[(PGNode *)item identifier] displayName];
}
- (BOOL)thumbnailView:(PGThumbnailView *)sender canSelectItem:(id)item;
{
	return [[item resourceAdapter] hasViewableNodeCountGreaterThan:0];
}
- (BOOL)thumbnailView:(PGThumbnailView *)sender isContainerItem:(id)item
{
	return [[item resourceAdapter] isContainer];
}
- (OSType)thumbnailView:(PGThumbnailView *)sender typeCodeForItem:(id)item {
	return [[(PGNode *)item dataProvider] typeCode];	//	2023/10/22
}
- (NSURL *)thumbnailView:(PGThumbnailView *)sender urlForItem:(id)item
{
	NSAssert([item isKindOfClass:[PGNode class]], @"item is PGNode*");
	return [[(PGNode *)item identifier] URL];
}
- (NSColor *)thumbnailView:(PGThumbnailView *)sender labelColorForItem:(id)item
{
#if 1
	return [[(PGNode *)item identifier] labelColor];
#else
	switch([[(PGNode *)item identifier] labelColor]) {
		case PGLabelRed: return [NSColor redColor];
		case PGLabelOrange: return [NSColor orangeColor];
		case PGLabelYellow: return [NSColor yellowColor];
		case PGLabelGreen: return [NSColor greenColor];
		case PGLabelBlue: return [NSColor blueColor];
		case PGLabelPurple: return [NSColor purpleColor];
		case PGLabelGray: return [NSColor grayColor];
		default: return nil;
	}
#endif
}
- (NSRect)thumbnailView:(PGThumbnailView *)sender highlightRectForItem:(id)item
{
	PGDisplayController *const d = [self displayController];
	NSRect const fullHighlight = NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f);
	if([d activeNode] != item || ![d isDisplayingImage]) return fullHighlight;
	if([d isReading]) return NSZeroRect;
	PGClipView *const clipView = [d clipView];
	NSRect const scrollableRect = [clipView scrollableRectWithBorder:NO];
	if(NSWidth(scrollableRect) <= 0.0001f && NSHeight(scrollableRect) <= 0.0001f) return fullHighlight; // We can't use NSIsEmptyRect() because it can be 0 in one direction but not the other.
	NSRect const f = [clipView documentFrame];
	NSRect r = PGScaleRect(NSOffsetRect(NSIntersectionRect(f, [clipView insetBounds]), -NSMinX(f), -NSMinY(f)), 1.0f / NSWidth(f), 1.0f / NSHeight(f));
	r.origin.y = 1.0f - NSMaxY(r);
	return r;
}

- (BOOL)thumbnailView:(PGThumbnailView *)sender hasRealThumbnailForItem:(id)item
{
	return [[item resourceAdapter] hasRealThumbnail];
}

/* - (NSInteger)thumbnailView:(PGThumbnailView *)sender directChildrenCountForItem:(id)item
{
	return [item resourceAdapter].childCount;
}

- (NSUInteger)thumbnailView:(PGThumbnailView *)sender folderAndImageDirectChildrenCountForItem:(id)item
{
	return [item resourceAdapter].folderAndImageCount;
} */

- (uint64_t)thumbnailView:(PGThumbnailView *)sender byteSizeAndFolderAndImageCountOfDirectChildrenForItem:(id)item {
	return [item resourceAdapter].byteSizeAndFolderAndImageCount;
}
- (uint64_t)thumbnailView:(PGThumbnailView *)sender byteSizeOfAllChildrenForItem:(id)item {
	return [item resourceAdapter].byteSizeOfAllChildren;
}
- (uint64_t)thumbnailView:(PGThumbnailView *)sender byteSizeOf:(id)item {
	return [item resourceAdapter].dataByteSize;
}

- (id)activeNodeForThumbnailView:(PGThumbnailView *)sender {
	return _displayController.activeNode;
}

- (BOOL)thumbnailView:(PGThumbnailView *)sender isParentOfActiveNode:(id)item {
	return [_displayController.activeNode isDescendantOfNode:item];
}

@end

//	MARK: -
@implementation PGDisplayController(PGThumbnailControllerCallbacks)

- (void)thumbnailPanelDidBecomeKey:(NSNotification *)aNotif {}
- (void)thumbnailPanelDidResignKey:(NSNotification *)aNotif {}

@end
