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
#import "PGDisplayController.h"
#import <unistd.h>
#import <tgmath.h>

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGContainerAdapter.h"
#import "PGGenericImageAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGBookmark.h"

// Views
#import "PGDocumentWindow.h"
#import "PGClipView.h"
#import "PGImageView.h"
#import "PGBezelPanel.h"
#import "PGAlertView.h"
#import "PGInfoView.h"
#import "PGFindView.h"

// Controllers
#import "PGDocumentController.h"
#import "PGPreferenceWindowController.h"
#import "PGBookmarkController.h"
#import "PGThumbnailController.h"
#import "PGImageSaveAlert.h"
#import "PGFullSizeContentController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGDebug.h"
#import "PGDelayedPerforming.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"
#import "PGKeyboardLayout.h"

static
BOOL
SetDesktopImage(NSScreen *screen, NSURL *URL) {
	NSWorkspace *const ws = [NSWorkspace sharedWorkspace];
	return [ws setDesktopImageURL:URL
						forScreen:screen
						  options:[ws desktopImageOptionsForScreen:screen]
							error:NULL];
}

//	MARK: -
NSString *const PGDisplayControllerActiveNodeDidChangeNotification = @"PGDisplayControllerActiveNodeDidChange";
NSString *const PGDisplayControllerActiveNodeWasReadNotification = @"PGDisplayControllerActiveNodeWasRead";
NSString *const PGDisplayControllerTimerDidChangeNotification = @"PGDisplayControllerTimerDidChange";

#define PGWindowMinSize ((NSSize){350.0f, 200.0f})

enum {
	PGZoomNone = 0,
	PGZoomIn   = 1 << 0,
	PGZoomOut  = 1 << 1
};
typedef NSUInteger PGZoomDirection;

static inline NSSize PGConstrainSize(NSSize min, NSSize size, NSSize max)
{
	return NSMakeSize(MIN(MAX(min.width, size.width), max.width), MIN(MAX(min.height, size.height), max.height));
}

static
void
SetControlAttributedStringValue(NSControl *c, NSAttributedString *anObject) {
#if __has_feature(objc_arc)
	NSMutableAttributedString *const str = [anObject mutableCopy];
#else
	NSMutableAttributedString *const str = [[anObject mutableCopy] autorelease];
#endif
	[str addAttributes:[c.attributedStringValue attributesAtIndex:0 effectiveRange:NULL]
				 range:NSMakeRange(0, str.length)];
	[c setAttributedStringValue:str];
}


//	MARK: -

#if __has_feature(objc_arc)

@interface PGDisplayController ()

@property (nonatomic, weak) IBOutlet PGClipView *clipView;
@property (nonatomic, weak) IBOutlet PGFindView *findView;
@property (nonatomic, weak) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak) IBOutlet NSView *errorView;
@property (nonatomic, weak) IBOutlet NSTextField *errorLabel;
@property (nonatomic, weak) IBOutlet NSTextField *errorMessage;
@property (nonatomic, weak) IBOutlet NSButton *reloadButton;
//	the original code -retain'd passwordView but there appears to be no
//	valid reason for doing this because the view should not be released
//	while this instance is alive; for the ARC version, passwordView is
//	weak-referenced until it is proven that it needs a strong-reference
@property (nonatomic, weak) IBOutlet NSView *passwordView;
@property (nonatomic, weak) IBOutlet NSTextField *passwordLabel;
@property (nonatomic, weak) IBOutlet NSTextField *passwordField;

//	PGDocument *_activeDocument;
@property (nonatomic, strong) PGNode *activeNode;
@property (nonatomic, strong) PGImageView *imageView;
//	PGPageLocation _initialLocation;
//	BOOL _reading;
@property (nonatomic, assign) NSUInteger displayImageIndex;

@property (nonatomic, strong) PGBezelPanel *graphicPanel;
@property (nonatomic, strong) PGLoadingGraphic *loadingGraphic;
@property (nonatomic, strong) PGBezelPanel *infoPanel;

@property (nonatomic, strong) PGThumbnailController *thumbnailController;

@property (nonatomic, strong) PGBezelPanel *findPanel;
@property (nonatomic, strong) PGFindlessTextView *findFieldEditor;

@property (nonatomic, strong) NSDate *nextTimerFireDate;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) PGFullSizeContentController *fullSizeContentController;
@property (nonatomic, assign) NSRect windowFrameBeforeEnteringFullScreen;

- (void)_setClipViewBackground;
- (void)_setImageView:(PGImageView *)aView;
- (BOOL)_setActiveNode:(PGNode *)aNode;
- (void)_readActiveNode;
- (void)_readFinished;
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation;
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation scaleMode:(PGImageScaleMode)scaleMode factor:(float)factor;
- (void)_updateImageViewSizeAllowAnimation:(BOOL)flag;
- (void)_updateNodeIndex;
- (void)_updateInfoPanelText;
- (void)_setCopyAsDesktopPicturePanelDidEnd:(NSSavePanel *)savePanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
- (void)_offerToOpenBookmarkAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode bookmark:(PGBookmark *)bookmark;

@end

#else

@interface PGDisplayController(Private)

- (void)_setClipViewBackground;
- (void)_setImageView:(PGImageView *)aView;
- (BOOL)_setActiveNode:(PGNode *)aNode;
- (void)_readActiveNode;
- (void)_readFinished;
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation;
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation scaleMode:(PGImageScaleMode)scaleMode factor:(float)factor;
- (void)_updateImageViewSizeAllowAnimation:(BOOL)flag;
- (void)_updateNodeIndex;
- (void)_updateInfoPanelText;
- (void)_setCopyAsDesktopPicturePanelDidEnd:(NSSavePanel *)savePanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
- (void)_offerToOpenBookmarkAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode bookmark:(PGBookmark *)bookmark;

@end

#endif

//	MARK: -

@implementation PGDisplayController

+ (NSArray *)pasteboardTypes
{
	return [NSArray PG_arrayWithContentsOfArrays:[PGNode pasteboardTypes], [PGImageView pasteboardTypes], nil];
}

//	MARK: - NSObject

+ (void)initialize
{
	[NSApp registerServicesMenuSendTypes:[self pasteboardTypes] returnTypes:[NSArray array]];
}
- (NSUserDefaultsController *)userDefaults
{
	return [NSUserDefaultsController sharedUserDefaultsController];
}

//	MARK: - PGDisplayController

- (IBAction)reveal:(id)sender
{
	if([[self activeDocument] isOnline]) {
		if([[NSWorkspace sharedWorkspace] openURL:[[[self activeDocument] rootIdentifier] URLByFollowingAliases:NO]]) return;
	} else {
		NSString *const path = [[[[self activeNode] identifier] URLByFollowingAliases:NO] path];
		if([[PGDocumentController sharedDocumentController] pathFinderRunning]) {
#if __has_feature(objc_arc)
			if([[[NSAppleScript alloc] initWithSource:[NSString stringWithFormat:@"tell application \"Path Finder\"\nactivate\nreveal \"%@\"\nend tell", path]] executeAndReturnError:NULL])
				return;
#else
			if([[[[NSAppleScript alloc] initWithSource:[NSString stringWithFormat:@"tell application \"Path Finder\"\nactivate\nreveal \"%@\"\nend tell", path]] autorelease] executeAndReturnError:NULL]) return;
#endif
		} else {
		//	if([[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:nil]) return;
			NSString*	rootPath = [NSString stringWithUTF8String:
									self.activeDocument.rootIdentifier.URL.fileSystemRepresentation];
			if(!path) {
				//	2023/09/28 revealing an image in an archive will select the archive file
				if([[NSWorkspace sharedWorkspace] selectFile:rootPath inFileViewerRootedAtPath:[NSString string]])
					return;
			} else if([[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:rootPath])
				return;
		}
	}
	NSBeep();
}
- (IBAction)saveImagesTo:(id)sender
{
#if __has_feature(objc_arc)
	[[[PGImageSaveAlert alloc] initWithRoot:[[self activeDocument] node] initialSelection:[self selectedNodes]] beginSheetForWindow:[self windowForSheet]];
#else
	[[[[PGImageSaveAlert alloc] initWithRoot:[[self activeDocument] node] initialSelection:[self selectedNodes]] autorelease] beginSheetForWindow:[self windowForSheet]];
#endif
}
- (IBAction)setAsDesktopPicture:(id)sender
{
	PGResourceIdentifier *const ident = [[self activeNode] identifier];
//	if(![ident isFileIdentifier] || ![[NSScreen PG_mainScreen] PG_setDesktopImageURL:[ident URLByFollowingAliases:YES]]) NSBeep();
	if(!ident.isFileIdentifier ||
		!SetDesktopImage([NSScreen PG_mainScreen], [ident URLByFollowingAliases:YES]))
		NSBeep();
}
- (IBAction)setCopyAsDesktopPicture:(id)sender
{
	NSSavePanel *const savePanel = [NSSavePanel savePanel];
	[savePanel setTitle:NSLocalizedString(@"Save Copy as Desktop Picture", @"Title of save dialog when setting a copy as the desktop picture.")];
	PGDisplayableIdentifier *const ident = [[self activeNode] identifier];
//	[savePanel setRequiredFileType:[[ident naturalDisplayName] pathExtension]];
	[savePanel setAllowedFileTypes:@[ident.naturalDisplayName.pathExtension]];

	[savePanel setCanSelectHiddenExtension:YES];
	NSWindow *const window = [self windowForSheet];
	NSString *const file = [[ident naturalDisplayName] stringByDeletingPathExtension];
#if 1
	savePanel.directoryURL			=	self.activeDocument.rootIdentifier.URL;
	savePanel.nameFieldStringValue	=	file;
#endif
	if(window) {
#if 1
		[savePanel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
			[self _setCopyAsDesktopPicturePanelDidEnd:savePanel returnCode:result contextInfo:NULL];
		}];
#else
		[savePanel beginSheetForDirectory:nil file:file modalForWindow:window modalDelegate:self
						   didEndSelector:@selector(_setCopyAsDesktopPicturePanelDidEnd:returnCode:contextInfo:)
							  contextInfo:NULL];
#endif
	} else {
		NSModalResponse	response	=	[savePanel runModal];
	//	NSInteger		response	=	[savePanel runModalForDirectory:nil file:file];
		[self _setCopyAsDesktopPicturePanelDidEnd:savePanel
									   returnCode:response
									  contextInfo:NULL];
	}
}
- (IBAction)moveToTrash:(id)sender
{
//	BOOL movedAnything = NO;
	__block BOOL movedAnything = NO;
	for(PGNode *const node in [self selectedNodes]) {
#if 1
		[NSWorkspace.sharedWorkspace recycleURLs:@[node.identifier.URL]
							   completionHandler:^(NSDictionary<NSURL*,NSURL*>* newURLs, NSError* error) {
			if(!error)
				movedAnything = YES;
		}];
#else
		NSString *const path = [[[node identifier] URL] path];
		if([[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[path stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[path lastPathComponent]] tag:NULL])
			movedAnything = YES;
#endif
	}
	if(!movedAnything) NSBeep();	//	2021/07/21 this might be too early (block not completed yet)
}

//	MARK: -

- (IBAction)copy:(id)sender
{
	if(![self writeSelectionToPasteboard:[NSPasteboard generalPasteboard] types:[[self class] pasteboardTypes]]) NSBeep();
}
- (IBAction)selectAll:(id)sender {
	[_thumbnailController selectAll];
}
- (IBAction)performFindPanelAction:(id)sender
{
	switch([sender tag]) {
		case NSFindPanelActionShowFindPanel:
			[self setFindPanelShown:!([self findPanelShown] && [_findPanel isKeyWindow])];
			break;
		case NSFindPanelActionNext:
		case NSFindPanelActionPrevious:
		{
#if __has_feature(objc_arc)
			NSArray *const terms = [[_searchField stringValue] PG_searchTerms];
#else
			NSArray *const terms = [[searchField stringValue] PG_searchTerms];
#endif
			if(terms && [terms count] && ![self tryToSetActiveNode:[[[self activeNode] resourceAdapter] sortedViewableNodeNext:[sender tag] == NSFindPanelActionNext matchSearchTerms:terms] forward:YES]) NSBeep();
			break;
		}
		default:
			NSBeep();
	}
#if __has_feature(objc_arc)
	if([_findPanel isKeyWindow]) [_findPanel makeFirstResponder:_searchField];
#else
	if([_findPanel isKeyWindow]) [_findPanel makeFirstResponder:searchField];
#endif
}
- (IBAction)hideFindPanel:(id)sender
{
	[self setFindPanelShown:NO];
}

//	MARK: -

- (IBAction)toggleFullscreen:(id)sender
{
	PGDocumentController *const dc = PGDocumentController.sharedDocumentController;
	dc.fullscreen = !dc.fullscreen;

	//	2023/08/14 the background color now depends on whether the view's window
	//	is in fullscreen mode so the background color must be updated:
	[self _setClipViewBackground];
}

- (IBAction)toggleEntireWindowOrScreen:(id)sender	//	2023/08/14 added; 2023/11/16 renamed
{
	BOOL const isInFullscreen = PGDocumentController.sharedDocumentController.fullscreen;
	if(isInFullscreen) {
		PGDocumentController *const dc = PGDocumentController.sharedDocumentController;
		dc.usesEntireScreenWhenInFullScreen = !dc.usesEntireScreenWhenInFullScreen;
	} else
		[_fullSizeContentController toggleFullSizeContent];
}

- (IBAction)toggleInfo:(id)sender
{
	[[self activeDocument] setShowsInfo:![[self activeDocument] showsInfo]];
}

- (IBAction)toggleThumbnails:(id)sender
{
	[[self activeDocument] setShowsThumbnails:![[self activeDocument] showsThumbnails]];
}
- (IBAction)changeReadingDirection:(id)sender
{
	[[self activeDocument] setReadingDirection:[sender tag]];
}
- (IBAction)changeSortOrder:(id)sender
{
	[[self activeDocument] setSortOrder:([sender tag] & PGSortOrderMask) | ([[self activeDocument] sortOrder] & PGSortOptionsMask)];
}
- (IBAction)changeSortDirection:(id)sender
{
	[[self activeDocument] setSortOrder:([[self activeDocument] sortOrder] & ~PGSortDescendingMask) | [sender tag]];
}
- (IBAction)changeSortRepeat:(id)sender
{
	[[self activeDocument] setSortOrder:([[self activeDocument] sortOrder] & ~PGSortRepeatMask) | [sender tag]];
}
- (IBAction)revertOrientation:(id)sender
{
	[[self activeDocument] setBaseOrientation:PGUpright];
}
- (IBAction)changeOrientation:(id)sender
{
	[[self activeDocument] setBaseOrientation:PGAddOrientation([[self activeDocument] baseOrientation], [sender tag])];
}
- (IBAction)toggleAnimation:(id)sender
{
	NSParameterAssert([_imageView canAnimateRep]);
	BOOL const nowPlaying = ![[self activeDocument] animatesImages];
	[[_graphicPanel content] pushGraphic:[PGBezierPathIconGraphic graphicWithIconType:nowPlaying ? AEPlayIcon : AEPauseIcon] window:[self window]];
	[[self activeDocument] setAnimatesImages:nowPlaying];
}

//	MARK: -

- (IBAction)changeImageScaleMode:(id)sender
{
	//	see -documentImageScaleDidChange:
	[[self activeDocument] setImageScaleMode:[sender tag]];
}
- (IBAction)zoomIn:(id)sender
{
	if(![self zoomKeyDown:[[self window] currentEvent]]) [self zoomBy:2.0f animate:YES];
}
- (IBAction)zoomOut:(id)sender
{
	if(![self zoomKeyDown:[[self window] currentEvent]]) [self zoomBy:0.5f animate:YES];
}
- (IBAction)changeImageScaleFactor:(id)sender
{
	[[self activeDocument] setImageScaleFactor:pow(2.0f, (CGFloat)[sender doubleValue]) animate:NO];
	[[[PGDocumentController sharedDocumentController] scaleMenu] update];
}
- (IBAction)minImageScaleFactor:(id)sender
{
	[[self activeDocument] setImageScaleFactor:PGScaleMin];
	[[[PGDocumentController sharedDocumentController] scaleMenu] update];
}
- (IBAction)maxImageScaleFactor:(id)sender
{
	[[self activeDocument] setImageScaleFactor:PGScaleMax];
	[[[PGDocumentController sharedDocumentController] scaleMenu] update];
}

//	MARK: -

- (IBAction)previousPage:(id)sender
{
	[self tryToGoForward:NO allowAlerts:YES];
}
- (IBAction)nextPage:(id)sender
{
	[self tryToGoForward:YES allowAlerts:YES];
}

- (IBAction)firstPage:(id)sender
{
	[self setActiveNode:[[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:YES] forward:YES];
}
- (IBAction)lastPage:(id)sender
{
	[self setActiveNode:[[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:NO] forward:NO];
}

//	MARK: -

- (IBAction)firstOfPreviousFolder:(id)sender
{
	if([self tryToSetActiveNode:[[[self activeNode] resourceAdapter] sortedFirstViewableNodeInFolderNext:NO inclusive:NO] forward:YES]) return;
	[self prepareToLoop]; // -firstOfPreviousFolder: is an exception to our usual looping mechanic, so we can't use -loopForward:.
	PGNode *const last = [[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:NO];
	[self tryToLoopForward:NO toNode:[[last resourceAdapter] isSortedFirstViewableNodeOfFolder] ? last : [[last resourceAdapter] sortedFirstViewableNodeInFolderNext:NO inclusive:YES] pageForward:YES allowAlerts:YES];
}
- (IBAction)firstOfNextFolder:(id)sender
{
	if([self tryToSetActiveNode:[[[self activeNode] resourceAdapter] sortedFirstViewableNodeInFolderNext:YES inclusive:NO] forward:YES]) return;
	[self loopForward:YES];
}
- (IBAction)skipBeforeFolder:(id)sender
{
	if([self tryToSetActiveNode:[[[[self activeNode] resourceAdapter] containerAdapter] sortedViewableNodeNext:NO includeChildren:NO] forward:NO]) return;
	[self loopForward:NO];
}
- (IBAction)skipPastFolder:(id)sender
{
	if([self tryToSetActiveNode:[[[[self activeNode] resourceAdapter] containerAdapter] sortedViewableNodeNext:YES includeChildren:NO] forward:YES]) return;
	[self loopForward:YES];
}
- (IBAction)firstOfFolder:(id)sender
{
	[self setActiveNode:[[[self activeNode] resourceAdapter] sortedViewableNodeInFolderFirst:YES] forward:YES];
}
- (IBAction)lastOfFolder:(id)sender
{
	[self setActiveNode:[[[self activeNode] resourceAdapter] sortedViewableNodeInFolderFirst:NO] forward:NO];
}

//	MARK: -

- (IBAction)jumpToPage:(id)sender
{
	PGNode *node = [[(NSMenuItem *)sender representedObject] nonretainedObjectValue];
	if(![node isViewable]) node = [[node resourceAdapter] sortedViewableNodeFirst:YES];
	if([self activeNode] == node || !node) return;
	[self setActiveNode:node forward:YES];
}

//	MARK: -

- (IBAction)pauseDocument:(id)sender
{
	[[PGBookmarkController sharedBookmarkController] addBookmark:[[self activeNode] bookmark]];
}
- (IBAction)pauseAndCloseDocument:(id)sender
{
	[self pauseDocument:sender];
	[[self activeDocument] close];
}

//	MARK: -

- (IBAction)reload:(id)sender
{
#if __has_feature(objc_arc)
	[_reloadButton setEnabled:NO];
#else
	[reloadButton setEnabled:NO];
#endif
	[[self activeNode] reload];
	[self _readActiveNode];
}
- (IBAction)decrypt:(id)sender
{
	PGNode *const activeNode = [self activeNode];
	[activeNode PG_addObserver:self selector:@selector(nodeLoadingDidProgress:) name:PGNodeLoadingDidProgressNotification];
	[activeNode PG_addObserver:self selector:@selector(nodeReadyForViewing:) name:PGNodeReadyForViewingNotification];
	// TODO: Figure this out.
//	[[[activeNode resourceAdapter] info] setObject:[_passwordField stringValue] forKey:PGPasswordKey];
	[activeNode becomeViewed];
}

//	MARK: -

#if !__has_feature(objc_arc)
@synthesize activeDocument = _activeDocument;
@synthesize activeNode = _activeNode;
#endif
- (NSWindow *)windowForSheet
{
	return [self window];
}
- (NSSet *)selectedNodes
{
	NSSet *const thumbnailSelection = [_thumbnailController selectedNodes];
	if([thumbnailSelection count]) return thumbnailSelection;
	return [self activeNode] ? [NSSet setWithObject:[self activeNode]] : [NSSet set];
}
- (void)setSelectedNodes:(NSSet *)selectedNodes {	//	2023/10/02 was readonly
	_thumbnailController.selectedNodes = selectedNodes;
}

- (PGNode *)selectedNode
{
	NSSet *const selectedNodes = [self selectedNodes];
	return [selectedNodes count] == 1 ? [selectedNodes anyObject] : nil;
}
#if !__has_feature(objc_arc)
@synthesize clipView;
@synthesize initialLocation = _initialLocation;
@synthesize reading = _reading;
#endif
- (BOOL)isDisplayingImage
{
#if __has_feature(objc_arc)
	return [_clipView documentView] == _imageView;
#else
	return [clipView documentView] == _imageView;
#endif
}
- (BOOL)canShowInfo
{
	return YES;
}
- (BOOL)shouldShowInfo
{
	return [[self activeDocument] showsInfo] && [self canShowInfo];
}
- (BOOL)loadingIndicatorShown
{
	return _loadingGraphic != nil;
}
- (BOOL)findPanelShown
{
	return [_findPanel isVisible] && ![_findPanel isFadingOut];
}
- (void)setFindPanelShown:(BOOL)flag
{
	if(flag) {
	//	NSDisableScreenUpdates();	2021/07/21 deprecated
		[[self window] orderFront:self];
		if(![self findPanelShown]) [_findPanel displayOverWindow:[self window]];
		[_findPanel makeKeyWindow];
		[self documentReadingDirectionDidChange:nil];
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
	} else {
		[_findPanel fadeOut];
		[self documentReadingDirectionDidChange:nil];
		[[self window] makeKeyWindow];
	}
}
- (NSDate *)nextTimerFireDate
{
#if __has_feature(objc_arc)
	return _nextTimerFireDate;
#else
	return [[_nextTimerFireDate retain] autorelease];
#endif
}
- (BOOL)timerRunning
{
	return !!_timer;
}
- (void)setTimerRunning:(BOOL)run
{
#if !__has_feature(objc_arc)
	[_nextTimerFireDate release];
#endif
	[_timer invalidate];
#if !__has_feature(objc_arc)
	[_timer release];
#endif
	if(run) {
		_nextTimerFireDate = [[NSDate alloc] initWithTimeIntervalSinceNow:[[self activeDocument] timerInterval]];
#if __has_feature(objc_arc)
		_timer = [self PG_performSelector:@selector(advanceOnTimer)
							   withObject:nil
								 fireDate:_nextTimerFireDate
								 interval:0.0f
								  options:kNilOptions
									 mode:NSDefaultRunLoopMode];
#else
		_timer = [[self PG_performSelector:@selector(advanceOnTimer) withObject:nil fireDate:_nextTimerFireDate interval:0.0f options:kNilOptions mode:NSDefaultRunLoopMode] retain];
#endif
	} else {
		_nextTimerFireDate = nil;
		_timer = nil;
	}
	[self PG_postNotificationName:PGDisplayControllerTimerDidChangeNotification];
}

//	MARK: -

- (BOOL)setActiveDocument:(PGDocument *)document closeIfAppropriate:(BOOL)flag
{
	if(document == _activeDocument) return NO;
	if(_activeDocument) {
		if(_reading) [_imageView setImageRep:nil orientation:PGUpright size:NSZeroSize];
#if __has_feature(objc_arc)
		[_activeDocument storeNode:[self activeNode] imageView:_imageView offset:[_clipView pinLocationOffset] query:[_searchField stringValue]];
#else
		[_activeDocument storeNode:[self activeNode] imageView:_imageView offset:[clipView pinLocationOffset] query:[searchField stringValue]];
#endif
		[self _setImageView:nil];
		[_activeDocument PG_removeObserver:self name:PGDocumentWillRemoveNodesNotification];
		[_activeDocument PG_removeObserver:self name:PGDocumentSortedNodesDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGDocumentNodeDisplayNameDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGDocumentNodeIsViewableDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGPrefObjectBaseOrientationDidChangeNotification];

		[_activeDocument PG_removeObserver:self name:PGPrefObjectShowsInfoDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGPrefObjectShowsThumbnailsDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGPrefObjectReadingDirectionDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGPrefObjectImageScaleDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGPrefObjectAnimatesImagesDidChangeNotification];
		[_activeDocument PG_removeObserver:self name:PGPrefObjectTimerIntervalDidChangeNotification];

		//	2023/08/21 bugfix: the fullscreen controller is *shared* so it's possible to
		//	invoke this method on the shared instance which already has many member variables
		//	initialized. In particular, the thumbnail controller can already exist, which
		//	causes any call to -setActiveNode:forward: to send a notification which calls
		//	back to a notification receiver in the thumbnail browser/view which in turn
		//	operates on invalid data which crashes the app.
		//	The exact circumstances which cause the crash are:
		//	[1] open an archive with images
		//	[2] enter full screen mode
		//	[3] display thumbnails
		//	[4] in the Finder, drag and drop another archive with images onto the app
		//	[5] the app tries to set up the new document controller using the *shared*
		//		fullscreen controller, resulting in a notification about the active node
		//		changing being sent to the *existing* thumbnail browser (a member of the
		//		thumbnail controller in the fullscreen controller); that thumbnail browser
		//		still has state that references the first archive and not the archive
		//		being opened, so it fails to find an object and crashes when it accesses
		//		invalid memory.
		//	Solution: release the _thumbnailController.
		if(_thumbnailController) {
#if !__has_feature(objc_arc)
			[_thumbnailController release];
#endif
			_thumbnailController	=	nil;	//	2023/08/21 required to be nil
		}
	}
	if(flag && !document && _activeDocument) {
		_activeDocument = nil;
#if !__has_feature(objc_arc)
		[[self retain] autorelease]; // Necessary if the find panel is open.
#endif
		[[self window] close];
		return YES;
	}
	_activeDocument = document;
	if([[self window] isMainWindow]) [[PGDocumentController sharedDocumentController] setCurrentDocument:_activeDocument];
	[_activeDocument PG_addObserver:self selector:@selector(documentWillRemoveNodes:) name:PGDocumentWillRemoveNodesNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentSortedNodesDidChange:) name:PGDocumentSortedNodesDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentNodeDisplayNameDidChange:) name:PGDocumentNodeDisplayNameDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentNodeIsViewableDidChange:) name:PGDocumentNodeIsViewableDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentBaseOrientationDidChange:) name:PGPrefObjectBaseOrientationDidChangeNotification];

	[_activeDocument PG_addObserver:self selector:@selector(documentShowsInfoDidChange:) name:PGPrefObjectShowsInfoDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentShowsThumbnailsDidChange:) name:PGPrefObjectShowsThumbnailsDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentReadingDirectionDidChange:) name:PGPrefObjectReadingDirectionDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentImageScaleDidChange:) name:PGPrefObjectImageScaleDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentAnimatesImagesDidChange:) name:PGPrefObjectAnimatesImagesDidChangeNotification];
	[_activeDocument PG_addObserver:self selector:@selector(documentTimerIntervalDidChange:) name:PGPrefObjectTimerIntervalDidChangeNotification];
	[self setTimerRunning:NO];
	if(_activeDocument) {
		NSParameterAssert(nil == _thumbnailController);	//	2023/08/21 required to be nil
	//	NSDisableScreenUpdates();	2021/07/21 deprecated
		PGNode *node;
		PGImageView *view;
		NSSize offset;
		NSString *query;
		[_activeDocument getStoredNode:&node imageView:&view offset:&offset query:&query];
		[self _setImageView:view];
		if([view rep]) {
			[self _setActiveNode:node];
#if __has_feature(objc_arc)
			[_clipView setDocumentView:view];
#else
			[clipView setDocumentView:view];
#endif
			[view setImageRep:[view rep] orientation:[view orientation] size:[self _sizeForImageRep:[view rep] orientation:[view orientation]]];
#if __has_feature(objc_arc)
			[_clipView scrollPinLocationToOffset:offset animation:PGNoAnimation];
#else
			[clipView scrollPinLocationToOffset:offset animation:PGNoAnimation];
#endif
			[self _readFinished];
		} else {
#if __has_feature(objc_arc)
			[_clipView setDocumentView:view];
#else
			[clipView setDocumentView:view];
#endif
			[self setActiveNode:node forward:YES];
		}
		[self documentNodeIsViewableDidChange:nil]; // In case the node has become unviewable in the meantime.
#if __has_feature(objc_arc)
		[_searchField setStringValue:query];
#else
		[searchField setStringValue:query];
#endif

		[self documentReadingDirectionDidChange:nil];
		[self documentShowsInfoDidChange:nil];
		[self documentShowsThumbnailsDidChange:nil];	//	creates the thumbnailController
		[_thumbnailController setDocument:_activeDocument];
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
	}
	return NO;
}
- (void)activateDocument:(PGDocument *)document
{
	[self setActiveDocument:document closeIfAppropriate:NO];
	[[self window] makeKeyAndOrderFront:self];
}

//	MARK: -

- (void)setActiveNode:(PGNode *)aNode forward:(BOOL)flag
{
	if(![self _setActiveNode:aNode]) return;
	if([[[self window] currentEvent] modifierFlags] & NSEventModifierFlagControl) _initialLocation = PGPreserveLocation;
	else _initialLocation = flag ? PGHomeLocation : [[[NSUserDefaults standardUserDefaults] objectForKey:PGBackwardsInitialLocationKey] integerValue];
	[self _readActiveNode];
}
- (BOOL)tryToSetActiveNode:(PGNode *)aNode forward:(BOOL)flag
{
	if(!aNode) return NO;
	[self setActiveNode:aNode forward:flag];
	return YES;
}
- (BOOL)tryToGoForward:(BOOL)forward allowAlerts:(BOOL)flag
{
	if([self tryToSetActiveNode:[[[self activeNode] resourceAdapter] sortedViewableNodeNext:forward] forward:forward]) return YES;
	[self prepareToLoop];
	return [self tryToLoopForward:forward toNode:[[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:forward] pageForward:forward allowAlerts:flag];
}
- (void)loopForward:(BOOL)flag
{
	[self prepareToLoop];
	[self tryToLoopForward:flag toNode:[[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:flag] pageForward:flag allowAlerts:YES];
}
- (void)prepareToLoop
{
	PGSortOrder const o = [[self activeDocument] sortOrder];
	if(!(PGSortRepeatMask & o) || (PGSortOrderMask & o) != PGSortShuffle) return;
	PGDocument *const doc = [self activeDocument];
	[[doc node] noteSortOrderDidChange]; // Reshuffle.
	[doc noteSortedChildrenDidChange];
}
- (BOOL)tryToLoopForward:(BOOL)loopForward toNode:(PGNode *)node pageForward:(BOOL)pageForward allowAlerts:(BOOL)flag
{
	PGDocument *const doc = [self activeDocument];
	BOOL const left = ([doc readingDirection] == PGReadingDirectionLeftToRight) == !loopForward;
	PGSortOrder const o = [[self activeDocument] sortOrder];
	if(PGSortRepeatMask & o && [self tryToSetActiveNode:node forward:pageForward]) {
		if(flag) [[_graphicPanel content] pushGraphic:left ? [PGAlertGraphic loopedLeftGraphic] : [PGAlertGraphic loopedRightGraphic] window:[self window]];
		return YES;
	}
	if(flag) [[_graphicPanel content] pushGraphic:left ? [PGAlertGraphic cannotGoLeftGraphic] : [PGAlertGraphic cannotGoRightGraphic] window:[self window]];
	return NO;
}
- (void)activateNode:(PGNode *)node
{
	[self setActiveDocument:[node document] closeIfAppropriate:NO];
	[self setActiveNode:node forward:YES];
}

//	MARK: -

- (void)showLoadingIndicator
{
	if(_loadingGraphic) return;
#if __has_feature(objc_arc)
	_loadingGraphic = [PGLoadingGraphic loadingGraphic];
#else
	_loadingGraphic = [[PGLoadingGraphic loadingGraphic] retain];
#endif
	[_loadingGraphic setProgress:[[[[self activeNode] resourceAdapter] activity] progress]];
	[[_graphicPanel content] pushGraphic:_loadingGraphic window:[self window]];
}
- (void)offerToOpenBookmark:(PGBookmark *)bookmark
{
#if __has_feature(objc_arc)
	NSAlert *alert = [NSAlert new];
#else
	NSAlert *const alert = [NSAlert new];
#endif
	[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"This document has a bookmark for the page %@.", @"Offer to resume from bookmark alert message text. %@ is replaced with the page name."), [[bookmark fileIdentifier] displayName]]];
	[alert setInformativeText:NSLocalizedString(@"If you don't resume from this page, the bookmark will be kept and you will start from the first page as usual.", @"Offer to resume from bookmark alert informative text.")];
	[[alert addButtonWithTitle:NSLocalizedString(@"Resume", @"Do resume from bookmark button.")] setKeyEquivalent:@"\r"];
	[[alert addButtonWithTitle:NSLocalizedString(@"Don't Resume", @"Don't resume from bookmark button.")] setKeyEquivalent:@"\e"];
	NSWindow *const window = [self windowForSheet];
#if !__has_feature(objc_arc)
	[bookmark retain];
#endif
	if(window)
	//	[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(_offerToOpenBookmarkAlertDidEnd:returnCode:bookmark:) contextInfo:bookmark];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
			[self _offerToOpenBookmarkAlertDidEnd:alert returnCode:returnCode bookmark:bookmark];
		}];
	//	 (void (^ _Nullable)(NSModalResponse returnCode))handler];
	else {
		[self _offerToOpenBookmarkAlertDidEnd:alert returnCode:[alert runModal] bookmark:bookmark];
#if __has_feature(objc_arc)
		alert = nil;
#else
		[alert release];
#endif
	}
}
- (void)advanceOnTimer
{
	[self setTimerRunning:[self tryToGoForward:YES allowAlerts:YES]];
}

//	MARK: -

- (void)zoomBy:(CGFloat)factor animate:(BOOL)flag
{
	[[self activeDocument] setImageScaleFactor:MAX(PGScaleMin, MIN([_imageView averageScaleFactor] * factor, PGScaleMax)) animate:flag];
}
- (BOOL)zoomKeyDown:(NSEvent *)firstEvent
{
	[NSCursor setHiddenUntilMouseMoves:YES];
	[_imageView setUsesCaching:NO];
	[NSEvent startPeriodicEventsAfterDelay:0.0f withPeriod:PGAnimationFramerate];
	NSEvent *latestEvent = firstEvent;
	PGZoomDirection dir = PGZoomNone;
	BOOL stop = NO, didAnything = NO;
	do {
		NSEventType const type = [latestEvent type];
		if(NSEventTypeKeyDown == type || NSEventTypeKeyUp == type) {
			PGZoomDirection newDir = PGZoomNone;
			switch([latestEvent keyCode]) {
				case PGKeyEquals:
				case PGKeyPadPlus:
					newDir = PGZoomIn; break;
				case PGKeyMinus:
				case PGKeyPadMinus:
					newDir = PGZoomOut; break;
			}
			switch(type) {
				case NSEventTypeKeyDown: dir |= newDir;  break;
				case NSEventTypeKeyUp:   dir &= ~newDir; break;
				default: break;
			}
		} else {
			switch(dir) {
				case PGZoomNone: stop = YES; break;
				case PGZoomIn:  [self zoomBy:1.1f animate:NO]; break;
				case PGZoomOut: [self zoomBy:1.0f / 1.1f animate:NO]; break;
			}
			if(!stop) didAnything = YES;
		}
	} while(!stop && (latestEvent = [[self window] nextEventMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskPeriodic untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES]));
	[NSEvent stopPeriodicEvents];
	[[self window] discardEventsMatchingMask:NSEventMaskAny beforeEvent:latestEvent];
	[_imageView setUsesCaching:YES];
	return didAnything;
}

//	MARK: -

- (void)clipViewFrameDidChange:(NSNotification *)aNotif
{
	[self _updateImageViewSizeAllowAnimation:NO];
}

//	MARK: -

- (void)nodeLoadingDidProgress:(NSNotification *)aNotif
{
	NSParameterAssert([aNotif object] == [self activeNode]);
	[_loadingGraphic setProgress:[[[[self activeNode] resourceAdapter] activity] progress]];
}
- (void)nodeReadyForViewing:(NSNotification *)aNotif
{
	NSParameterAssert([aNotif object] == [self activeNode]);
	NSError *const error = [[[self activeNode] resourceAdapter] error];
	if(!error) {
#if __has_feature(objc_arc)
		NSPoint const relativeCenter = [_clipView relativeCenter];
#else
		NSPoint const relativeCenter = [clipView relativeCenter];
#endif
		NSImageRep *const rep = [[aNotif userInfo] objectForKey:PGImageRepKey];
		PGOrientation const orientation = [[[self activeNode] resourceAdapter] orientationWithBase:YES];
		[_imageView setImageRep:rep orientation:orientation size:[self _sizeForImageRep:rep orientation:orientation]];
#if __has_feature(objc_arc)
		[_clipView setDocumentView:_imageView];
		if(PGPreserveLocation == _initialLocation)
			[_clipView scrollRelativeCenterTo:relativeCenter animation:PGNoAnimation];
		else
			[_clipView scrollToLocation:_initialLocation animation:PGNoAnimation];
		[[self window] makeFirstResponder:_clipView];
#else
		[clipView setDocumentView:_imageView];
		if(PGPreserveLocation == _initialLocation)
			[clipView scrollRelativeCenterTo:relativeCenter animation:PGNoAnimation];
		else
			[clipView scrollToLocation:_initialLocation animation:PGNoAnimation];
		[[self window] makeFirstResponder:clipView];
#endif
	} else if(PGEqualObjects([error domain], PGNodeErrorDomain)) switch([error code]) {
		case PGGenericError:
#if __has_feature(objc_arc)
			SetControlAttributedStringValue(_errorLabel,
				[_activeNode.resourceAdapter.dataProvider attributedString]);
		//	[_errorLabel PG_setAttributedStringValue:[[[_activeNode resourceAdapter] dataProvider] attributedString]];
			[_errorMessage setStringValue:[error localizedDescription]];
			[_errorView setFrameSize:NSMakeSize(NSWidth([_errorView frame]), NSHeight([_errorView frame]) - NSHeight([_errorMessage frame]) + [[_errorMessage cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, NSWidth([_errorMessage frame]), CGFLOAT_MAX)].height)];
			[_reloadButton setEnabled:YES];
			[_clipView setDocumentView:_errorView];
#else
			SetControlAttributedStringValue(errorLabel,
				[_activeNode.resourceAdapter.dataProvider attributedString]);
		//	[errorLabel PG_setAttributedStringValue:[[[_activeNode resourceAdapter] dataProvider] attributedString]];
			[errorMessage setStringValue:[error localizedDescription]];
			[errorView setFrameSize:NSMakeSize(NSWidth([errorView frame]), NSHeight([errorView frame]) - NSHeight([errorMessage frame]) + [[errorMessage cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, NSWidth([errorMessage frame]), CGFLOAT_MAX)].height)];
			[reloadButton setEnabled:YES];
			[clipView setDocumentView:errorView];
#endif
			break;
		case PGPasswordError:
#if __has_feature(objc_arc)
			SetControlAttributedStringValue(_passwordLabel,
				[_activeNode.resourceAdapter.dataProvider attributedString]);
		//	[_passwordLabel PG_setAttributedStringValue:[[[_activeNode resourceAdapter] dataProvider] attributedString]];
			[_passwordField setStringValue:@""];
			[_clipView setDocumentView:_passwordView];
#else
			SetControlAttributedStringValue(passwordLabel,
				[_activeNode.resourceAdapter.dataProvider attributedString]);
		//	[passwordLabel PG_setAttributedStringValue:[[[_activeNode resourceAdapter] dataProvider] attributedString]];
			[passwordField setStringValue:@""];
			[clipView setDocumentView:passwordView];
#endif
			break;
	}
	if(![_imageView superview]) [_imageView setImageRep:nil orientation:PGUpright size:NSZeroSize];
	[self _readFinished];
	[_thumbnailController clipViewBoundsDidChange:nil];
}

//	MARK: -

- (void)documentWillRemoveNodes:(NSNotification *)aNotif
{
	PGNode *const changedNode = [[aNotif userInfo] objectForKey:PGDocumentNodeKey];
	NSArray *const removedChildren = [[aNotif userInfo] objectForKey:PGDocumentRemovedChildrenKey];
	PGNode *node = [[[self activeNode] resourceAdapter] sortedViewableNodeNext:YES afterRemovalOfChildren:removedChildren fromNode:changedNode];
	if(!node) node = [[[self activeNode] resourceAdapter] sortedViewableNodeNext:NO afterRemovalOfChildren:removedChildren fromNode:changedNode];
	[self setActiveNode:node forward:YES];
}
- (void)documentSortedNodesDidChange:(NSNotification *)aNotif
{
	[self documentShowsInfoDidChange:nil];
	[self documentShowsThumbnailsDidChange:nil];
	if(![self activeNode]) [self setActiveNode:[[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:YES] forward:YES];
	else [self _updateNodeIndex];
}
- (void)documentNodeDisplayNameDidChange:(NSNotification *)aNotif
{
	NSParameterAssert(aNotif);
	PGNode *const node = [[aNotif userInfo] objectForKey:PGDocumentNodeKey];
	if([self activeNode] == node || [[self activeNode] parentNode] == node) [self _updateInfoPanelText]; // The parent may be displayed too, depending.
}
- (void)documentNodeIsViewableDidChange:(NSNotification *)aNotif
{
	PGNode *const node = aNotif ? [[aNotif userInfo] objectForKey:PGDocumentNodeKey] : [self activeNode];
	if(![self activeNode]) {
		if([node isViewable]) [self setActiveNode:node forward:YES];
	} else if([self activeNode] == node) {
		if(![node isViewable] && ![self tryToGoForward:YES allowAlerts:NO] && ![self tryToGoForward:NO allowAlerts:NO]) [self setActiveNode:[[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:YES] forward:YES];
	}
	if(aNotif) {
		[self documentShowsInfoDidChange:nil];
		[self documentShowsThumbnailsDidChange:nil];
		[self _updateNodeIndex];
	}
}
- (void)documentBaseOrientationDidChange:(NSNotification *)aNotif
{
	PGOrientation const o = [[[self activeNode] resourceAdapter] orientationWithBase:YES];
	[_imageView setImageRep:[_imageView rep] orientation:o size:[self _sizeForImageRep:[_imageView rep] orientation:o]];
}

//	MARK: -

- (void)documentShowsInfoDidChange:(NSNotification *)aNotif
{
	if([self shouldShowInfo]) {
		[[_infoPanel content] setCount:[[[[self activeDocument] node] resourceAdapter] viewableNodeCount]];
		[_infoPanel displayOverWindow:[self window]];
	} else [_infoPanel fadeOut];
}
- (void)documentShowsThumbnailsDidChange:(NSNotification *)aNotif
{
	if([PGThumbnailController shouldShowThumbnailsForDocument:[self activeDocument]]) {
		if(_thumbnailController) return;
		_thumbnailController = [[PGThumbnailController alloc] init];
	//	NSDisableScreenUpdates();	2021/07/21 deprecated
		[_thumbnailController setDisplayController:self];
		[self thumbnailControllerContentInsetDidChange:nil];
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
		[_thumbnailController PG_addObserver:self
									selector:@selector(thumbnailControllerContentInsetDidChange:)
										name:PGThumbnailControllerContentInsetDidChangeNotification];
	} else {
		[_thumbnailController PG_removeObserver:self
										   name:PGThumbnailControllerContentInsetDidChangeNotification];
		[_thumbnailController fadeOut];
#if !__has_feature(objc_arc)
		[_thumbnailController release];
#endif
		_thumbnailController = nil;
		[self thumbnailControllerContentInsetDidChange:nil];
	}
}
- (void)documentReadingDirectionDidChange:(NSNotification *)aNotif
{
	if(![self activeDocument]) return;
	BOOL const ltr = [[self activeDocument] readingDirection] == PGReadingDirectionLeftToRight;
	PGRectCorner const corner = ltr ? PGMinXMinYCorner : PGMaxXMinYCorner;
	PGInset inset = PGZeroInset;
	switch(corner) {
		case PGMinXMinYCorner: inset.minY = [self findPanelShown] ? NSHeight([_findPanel frame]) : 0.0f; break;
		case PGMaxXMinYCorner: inset.minX = [self findPanelShown] ? NSWidth([_findPanel frame]) : 0.0f; break;
	}
	if(_thumbnailController) inset = PGAddInsets(inset, [_thumbnailController contentInset]);
	[_infoPanel setFrameInset:inset];
	[[_infoPanel content] setOriginCorner:corner];
	[_infoPanel updateFrameDisplay:YES];
	[[[self activeDocument] pageMenu] update];
}
- (void)documentImageScaleDidChange:(NSNotification *)aNotif
{
	[self _updateImageViewSizeAllowAnimation:[[[aNotif userInfo] objectForKey:PGPrefObjectAnimateKey] boolValue]];
}
- (void)documentAnimatesImagesDidChange:(NSNotification *)aNotif
{
	[_imageView setAnimates:[[self activeDocument] animatesImages]];
}
- (void)documentTimerIntervalDidChange:(NSNotification *)aNotif
{
	[self setTimerRunning:[self timerRunning]];
}

//	MARK: -

- (void)thumbnailControllerContentInsetDidChange:(NSNotification *)aNotif
{
//	NSDisableScreenUpdates();	2021/07/21 deprecated
	PGInset inset = PGZeroInset;
	NSSize minSize = PGWindowMinSize;
	if(_thumbnailController) {
		PGInset const thumbnailInset = [_thumbnailController contentInset];
		inset = PGAddInsets(inset, thumbnailInset);
		minSize.width += thumbnailInset.minX + thumbnailInset.maxX;
	}
#if __has_feature(objc_arc)
	[_clipView setBoundsInset:inset];
	[_clipView displayIfNeeded];
#else
	[clipView setBoundsInset:inset];
	[clipView displayIfNeeded];
#endif
	[_findPanel setFrameInset:inset];
	[_graphicPanel setFrameInset:inset];
	[self _updateImageViewSizeAllowAnimation:NO];
	[self documentReadingDirectionDidChange:nil];
	[_findPanel updateFrameDisplay:YES];
	[_graphicPanel updateFrameDisplay:YES];
	NSWindow *const w = [self window];
	NSRect currentFrame = [w frame];
	if(NSWidth(currentFrame) < minSize.width) {
		currentFrame.size.width = minSize.width;
		[w setFrame:currentFrame display:YES];
	}
	[w setMinSize:minSize];
//	NSEnableScreenUpdates();	2021/07/21 deprecated
}

- (void)prefControllerBackgroundPatternColorDidChange:(NSNotification *)aNotif;
{
	[self _setClipViewBackground];
}

- (void)prefControllerBackgroundColorUsedInFullScreenDidChange:(NSNotification *)aNotif;
{
	if(self._isInAnyFullScreenMode)
		[self _setClipViewBackground];	//	updates only when in fullscreen mode
}

//	MARK: - PGDisplayController(Private)

//	ensures that whether in macOS-fullscreen or Sequential-fullscreen,
//	the app behaves the same
- (BOOL)_isInAnyFullScreenMode {
	return PGDocumentController.sharedDocumentController.fullscreen ||
			0 != (self.window.styleMask & NSWindowStyleMaskFullScreen);
}

- (BOOL)_usePreferredBackgroundColorWhenFullScreen {
	return [NSUserDefaults.standardUserDefaults
			boolForKey:PGBackgroundColorUsedInFullScreenKey];
}

- (NSColor *)_clipViewBackgroundColorWhenFullScreen:(BOOL)fullscreen {
	//	2023/08/14 added this method to enable the background color to depend on
	//	whether the view's window is in fullscreen mode and whether user wants it
	//	used in fullscreen mode.
	if(fullscreen && ![self _usePreferredBackgroundColorWhenFullScreen])
		return NSColor.blackColor;
	else
		return [PGPreferenceWindowController.sharedPrefController backgroundPatternColor];
}

- (void)_setClipViewBackground {
	NSColor *const clipViewBackgroundColor = [self
		_clipViewBackgroundColorWhenFullScreen:self._isInAnyFullScreenMode];
#if __has_feature(objc_arc)
	[_clipView setBackgroundColor:clipViewBackgroundColor];
#else
	[clipView setBackgroundColor:clipViewBackgroundColor];
#endif
}

- (void)_setImageView:(PGImageView *)aView
{
	if(aView == _imageView) return;
	[_imageView unbind:@"antialiasWhenUpscaling"];
	[_imageView unbind:@"usesRoundedCorners"];
#if __has_feature(objc_arc)
	_imageView = aView;
#else
	[_imageView release];
	_imageView = [aView retain];
#endif
	[_imageView bind:@"antialiasWhenUpscaling" toObject:[NSUserDefaults standardUserDefaults] withKeyPath:PGAntialiasWhenUpscalingKey options:nil];
	[self documentAnimatesImagesDidChange:nil];
}
- (BOOL)_setActiveNode:(PGNode *)aNode
{
	if(aNode == _activeNode) return NO;
	[_activeNode PG_removeObserver:self name:PGNodeLoadingDidProgressNotification];
	[_activeNode PG_removeObserver:self name:PGNodeReadyForViewingNotification];
#if __has_feature(objc_arc)
	_activeNode = aNode;
#else
	[_activeNode release];
	_activeNode = [aNode retain];
#endif
	[self _updateNodeIndex];
	[self _updateInfoPanelText];

	//	2023/08/21 bugfix: when this instance is the *shared* fullscreen display controller,
	//	the following notification is received by multiple thumbnail browsers, which can
	//	cause a crash if the notification is for a *particular* PGDocument instance but is
	//	processed by a thumbnail browser which is associated with a different PGDocument
	//	instance. Solution: provide context to the notification callback by supplying the
	//	active document value. See corresponding code in PGThumbnailController's method
	//	-displayControllerActiveNodeDidChange:
	NSDictionary* d = [NSDictionary dictionaryWithObjectsAndKeys:_activeDocument, @"PGDocument",
																	_activeNode, @"PGNode", nil];
	[self PG_postNotificationName:PGDisplayControllerActiveNodeDidChangeNotification
						 userInfo:d];
//	[self PG_postNotificationName:PGDisplayControllerActiveNodeDidChangeNotification];

	return YES;
}
- (void)_readActiveNode
{
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(showLoadingIndicator) object:nil];
	if(!_activeNode) return [self nodeReadyForViewing:nil];
	_reading = YES;
	[self PG_performSelector:@selector(showLoadingIndicator) withObject:nil fireDate:nil interval:0.5f options:kNilOptions];
	[_activeNode PG_addObserver:self selector:@selector(nodeLoadingDidProgress:) name:PGNodeLoadingDidProgressNotification];
	[_activeNode PG_addObserver:self selector:@selector(nodeReadyForViewing:) name:PGNodeReadyForViewingNotification];
	[_activeNode becomeViewed];
	[self setTimerRunning:[self timerRunning]];
}
- (void)_readFinished
{
	_reading = NO;
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(showLoadingIndicator) object:nil];
	[[_graphicPanel content] popGraphicsOfType:PGSingleImageGraphic]; // Hide most alerts.
#if !__has_feature(objc_arc)
	[_loadingGraphic release];
#endif
	_loadingGraphic = nil;
	[self PG_postNotificationName:PGDisplayControllerActiveNodeWasReadNotification];
}
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation
{
	return [self _sizeForImageRep:rep orientation:orientation scaleMode:[[self activeDocument] imageScaleMode] factor:[[self activeDocument] imageScaleFactor]];
}
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation scaleMode:(PGImageScaleMode)scaleMode factor:(float)factor
{
	if(!rep) return NSZeroSize;
	NSSize originalSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
	if(orientation & PGRotated90CCW) {
		CGFloat const w = originalSize.width;
		originalSize.width = originalSize.height;
		originalSize.height = w;
	}
	NSSize newSize = originalSize;
	if(PGConstantFactorScale == scaleMode) {
		newSize.width *= factor;
		newSize.height *= factor;
	} else {
		PGImageScaleConstraint const constraint = [[[NSUserDefaults standardUserDefaults] objectForKey:PGImageScaleConstraintKey] unsignedIntegerValue];
		BOOL const resIndependent = [[[self activeNode] resourceAdapter] isResolutionIndependent];
		NSSize const minSize = constraint != PGUpscaleOnly || resIndependent ? NSZeroSize : newSize;
		NSSize const maxSize = constraint != PGDownscaleOnly || resIndependent ? NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX) : newSize;
#if __has_feature(objc_arc)
		NSRect const bounds = [_clipView insetBounds];
#else
		NSRect const bounds = [clipView insetBounds];
#endif
		CGFloat scaleX = NSWidth(bounds) / round(newSize.width);
		CGFloat scaleY = NSHeight(bounds) / round(newSize.height);
		if(PGAutomaticScale == scaleMode) {
#if __has_feature(objc_arc)
			NSSize const scrollMax = [_clipView maximumDistanceForScrollType:PGScrollByPage];
#else
			NSSize const scrollMax = [clipView maximumDistanceForScrollType:PGScrollByPage];
#endif
			if(scaleX > scaleY) scaleX = scaleY = MAX(scaleY, MIN(scaleX, (floor(newSize.height * scaleX / scrollMax.height + 0.3f) * scrollMax.height) / newSize.height));
			else if(scaleX < scaleY) scaleX = scaleY = MAX(scaleX, MIN(scaleY, (floor(newSize.width * scaleY / scrollMax.width + 0.3f) * scrollMax.width) / newSize.width));
		} else if(PGViewFitScale == scaleMode) scaleX = scaleY = MIN(scaleX, scaleY);
		newSize = PGConstrainSize(minSize, PGScaleSizeByXY(newSize, scaleX, scaleY), maxSize);
	}
	return PGIntegralSize(newSize);
}
- (void)_updateImageViewSizeAllowAnimation:(BOOL)flag
{
	[_imageView setSize:[self _sizeForImageRep:[_imageView rep] orientation:[_imageView orientation]] allowAnimation:flag];
}
- (void)_updateNodeIndex
{
	PGNode *const an = [self activeNode];
	PGResourceAdapter *anra = [an resourceAdapter];
	PGInfoView *const infoView = (PGInfoView *) [_infoPanel content];

	_displayImageIndex = [anra viewableNodeIndex];

	[infoView setIndex:_displayImageIndex];

	//	update the title bar accessory instead of the title
	{
	//	[self synchronizeWindowTitleWithDocumentName];
		NSTextField *const accessoryTextField = _fullSizeContentController.accessoryTextField;

		NSUInteger const nodeCount = [[[[self activeDocument] node] resourceAdapter] viewableNodeCount];
		if(nodeCount <= 1)
			accessoryTextField.stringValue = [NSString string];
		else
			accessoryTextField.stringValue = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)_displayImageIndex + 1, (unsigned long)nodeCount];
	}

	//	2023/10/01 the Info window now shows the display progress
	//	within a single folder/container
	if(anra.isContainer) {
		//	this never executes because anra is never a container
		infoView.currentFolderCount = infoView.currentFolderIndex = 0;
	} else {
		PGContainerAdapter *const parent = anra.containerAdapter;
		if(!parent || !parent.isContainer)
			return;

#if 1
		@autoreleasepool {
			//	don't count non-viewable nodes (non-images) when a folder's progress is being determined
			//	TODO: ?should this be cached?
			NSInteger childIndex = NSNotFound;
			NSMutableArray<PGNode*> *const children = [NSMutableArray arrayWithArray:parent.sortedChildren];
			NSMutableIndexSet *const indexes = [NSMutableIndexSet indexSet];
			NSUInteger i = 0, containerCount = 0;
	#define	COLOR_FILLED_BAR_IS_ENTIRE_PROGRESS	1

	#if COLOR_FILLED_BAR_IS_ENTIRE_PROGRESS
	#else
			BOOL const parentIsRootNode = an.parentNode == an.rootNode;
	#endif
			for(PGNode *node in children) {
				if(node.resourceAdapter.isContainer)
					++containerCount;
				if(![node isViewable])
					[indexes addIndex:i];
				else if(an == node) {
					NSAssert(NSNotFound == childIndex, @"");

					//	the index after non-viewables are removed from children
					childIndex = i - [indexes count];
				}

				++i;
			}
			if(0 != [indexes count])
				[children removeObjectsAtIndexes:indexes];
			NSAssert(NSNotFound != childIndex || 0 == [children count], @"");

			NSUInteger const childCount = children.count;
	#if COLOR_FILLED_BAR_IS_ENTIRE_PROGRESS
			infoView.currentFolderCount = childCount;
			infoView.currentFolderIndex = childIndex;
	#else
			//	if imageCount <= 1 or the root node's set of children has no containers
			//	then do not draw the folder progress bar else do so
			if(childCount > 1 && (!parentIsRootNode || 0 != containerCount)) {
				infoView.currentFolderCount = childCount;
				infoView.currentFolderIndex = childIndex;
			} else
				infoView.currentFolderCount = infoView.currentFolderIndex = 0;
	#endif
		}
#else
		NSArray<PGNode*> *const sortedChildren = parent.sortedChildren;
		NSUInteger const childCount = sortedChildren.count;	//	includes folders and non-images
		if(childCount > 1) {
			infoView.currentFolderCount = childCount;
			NSUInteger const childIndex = [sortedChildren indexOfObject:an];
			NSAssert(NSNotFound != childIndex, @"");
			infoView.currentFolderIndex = childIndex;
		} else
			infoView.currentFolderCount = infoView.currentFolderIndex = 0;
#endif
	}
}
- (void)_updateInfoPanelText
{
	NSString *text = nil;
	PGNode *const node = [self activeNode];
	if(node) {
		text = [[node identifier] displayName];
		PGNode *const parent = [node parentNode];
		if([parent parentNode]) text = [NSString stringWithFormat:@"%@ %C %@", [[parent identifier] displayName], (unichar)0x25B8, text];
	} else text = NSLocalizedString(@"No image", @"Label for when no image is being displayed in the window.");
	[[_infoPanel content] setStringValue:text];
}
- (void)_setCopyAsDesktopPicturePanelDidEnd:(NSSavePanel *)savePanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if(NSModalResponseOK != returnCode) return;
//	NSURL *const URL = [[savePanel filename] PG_fileURL];
	NSURL *const URL = savePanel.URL;
	[[[[self activeNode] resourceAdapter] data] writeToURL:URL atomically:NO];
//	if(![[NSScreen PG_mainScreen] PG_setDesktopImageURL:URL]) NSBeep();
	if(!SetDesktopImage([NSScreen PG_mainScreen], URL)) NSBeep();
}
- (void)_offerToOpenBookmarkAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode bookmark:(PGBookmark *)bookmark
{
#if __has_feature(objc_arc)
#else
	[bookmark autorelease];
#endif
	if(NSAlertFirstButtonReturn == returnCode) [[self activeDocument] openBookmark:bookmark];
}

//	MARK: -NSWindowController

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	[self documentReadingDirectionDidChange:nil];
	if([self shouldShowInfo]) [_infoPanel displayOverWindow:[self window]];
	[_thumbnailController display];
}

//	MARK: -

- (void)windowDidLoad
{
	[super windowDidLoad];
#if !__has_feature(objc_arc)
	[passwordView retain];
#endif

//	[[self window] useOptimizedDrawing:YES];	2021/07/21 deprecated
	[[self window] setMinSize:PGWindowMinSize];

	NSImage *const cursorImage = [NSImage imageNamed:@"Cursor-Hand-Pointing"];
#if __has_feature(objc_arc)
	[_clipView setAcceptsFirstResponder:YES];
	[_clipView setCursor:cursorImage ? [[NSCursor alloc] initWithImage:cursorImage hotSpot:NSMakePoint(5.0f, 0.0f)] : [NSCursor pointingHandCursor]];
	[_clipView setPostsFrameChangedNotifications:YES];
	[_clipView PG_addObserver:self selector:@selector(clipViewFrameDidChange:) name:NSViewFrameDidChangeNotification];
#else
	[clipView setAcceptsFirstResponder:YES];
	[clipView setCursor:cursorImage ? [[[NSCursor alloc] initWithImage:cursorImage hotSpot:NSMakePoint(5.0f, 0.0f)] autorelease] : [NSCursor pointingHandCursor]];
	[clipView setPostsFrameChangedNotifications:YES];
	[clipView PG_addObserver:self selector:@selector(clipViewFrameDidChange:) name:NSViewFrameDidChangeNotification];
#endif

#if __has_feature(objc_arc)
	_findPanel = [[PGBezelPanel alloc] initWithContentView:_findView];
	[_findPanel setInitialFirstResponder:_searchField];
#else
	_findPanel = [[PGBezelPanel alloc] initWithContentView:findView];
	[_findPanel setInitialFirstResponder:searchField];
#endif
	[_findPanel setDelegate:self];
	[_findPanel setAcceptsEvents:YES];
	[_findPanel setCanBecomeKey:YES];

	[self prefControllerBackgroundPatternColorDidChange:nil];

	//	create the full-size-content controller only when not in
	//	fullscreen mode (because the styleMask in that mode makes
	//	the window disallow having titlebar accessory controllers)
	NSWindowStyleMask const styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
								NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	if(styleMask == (self.window.styleMask & styleMask))
		_fullSizeContentController =
			[[PGFullSizeContentController alloc] initWithWindow:self.window];
}
- (void)synchronizeWindowTitleWithDocumentName
{
	NSString *blank = [NSString string];
	PGDisplayableIdentifier *const identifier = [[[self activeDocument] node] identifier];
	NSURL *const URL = [identifier URL];
	if([identifier isFileIdentifier]) {
	//	NSString *const path = [identifier isFileIdentifier] ? [URL path] : nil;
	//	[[self window] setRepresentedFilename:path ? path : blank];
		[[self window] setRepresentedURL:URL];
	} else {
		[[self window] setRepresentedURL:URL];
		NSButton *const docButton = [[self window] standardWindowButton:NSWindowDocumentIconButton];
#if __has_feature(objc_arc)
		NSImage *const image = [identifier.icon copy];
#else
		NSImage *const image = [[[identifier icon] copy] autorelease];
#endif
		[image setSize:[docButton bounds].size];
		[image recache];
		[docButton setImage:image];
	}

	NSUInteger const nodeCount = [[[[self activeDocument] node] resourceAdapter] viewableNodeCount];
	NSString *const titleDetails = nodeCount > 1 ?
		[NSString stringWithFormat:@" (%lu/%lu)", (unsigned long)_displayImageIndex + 1, (unsigned long)nodeCount] :
		blank;

	NSString *const title = [identifier displayName];
//	[[self window] setTitle:title ? [title stringByAppendingString:titleDetails] : blank];
	[[self window] setTitle:title ? title : blank];

#if __has_feature(objc_arc)
	NSMutableAttributedString *const menuLabel = [[identifier attributedStringWithAncestory:NO] mutableCopy];
#else
	NSMutableAttributedString *const menuLabel = [[[identifier attributedStringWithAncestory:NO] mutableCopy] autorelease];
#endif
	[[menuLabel mutableString] appendString:titleDetails];
	[[[PGDocumentController sharedDocumentController] windowsMenuItemForDocument:[self activeDocument]] setAttributedTitle:menuLabel];
}
- (void)close
{
	[[self activeDocument] close];
}

//	MARK: - NSResponder

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
	return ![returnType length] && [self writeSelectionToPasteboard:nil types:[NSArray arrayWithObject:sendType]] ? self : [super validRequestorForSendType:sendType returnType:returnType];
}

//	MARK: - NSObject

- (id)init
{
	if((self = [super initWithWindowNibName:@"PGDocument"])) {
		(void)[self window]; // Just load the window so we don't have to worry about it.

#if __has_feature(objc_arc)
		_graphicPanel = [PGAlertView PG_bezelPanel];
		_infoPanel = [PGInfoView PG_bezelPanel];
#else
		_graphicPanel = [[PGAlertView PG_bezelPanel] retain];
		_infoPanel = [[PGInfoView PG_bezelPanel] retain];
#endif
		[self _updateInfoPanelText];

		[[PGPreferenceWindowController sharedPrefController] PG_addObserver:self selector:@selector(prefControllerBackgroundPatternColorDidChange:) name:PGPreferenceWindowControllerBackgroundPatternColorDidChangeNotification];
		[[PGPreferenceWindowController sharedPrefController] PG_addObserver:self selector:@selector(prefControllerBackgroundColorUsedInFullScreenDidChange:) name:PGPreferenceWindowControllerBackgroundColorUsedInFullScreenDidChangeNotification];
		[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:PGImageScaleConstraintKey options:kNilOptions context:NULL];
	}
	return self;
}
- (void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:PGImageScaleConstraintKey];
	[self PG_cancelPreviousPerformRequests];
	[self PG_removeObserver];
	[self _setImageView:nil];
#if !__has_feature(objc_arc)
	[passwordView release];
	[_activeNode release];
	[_imageView release];	//	bugfix
	[_graphicPanel release];
	[_loadingGraphic release];
	[_infoPanel release];
	[_findPanel release];
	[_findFieldEditor release];
	[_thumbnailController release];
	[_nextTimerFireDate release];
#endif
	[_timer invalidate];
#if !__has_feature(objc_arc)
	[_timer release];
	[super dealloc];
#endif
}

//	MARK: - NSObject(NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(PGEqualObjects(keyPath, PGImageScaleConstraintKey)) [self _updateImageViewSizeAllowAnimation:YES];
	else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

//	MARK: - NSObject(NSMenuValidation)

#define PGFuzzyEqualityToCellState(a, b) ({ double __a = (double)(a); double __b = (double)(b); (fabs(__a - __b) < 0.001f ? NSControlStateValueOn : (fabs(round(__a) - round(__b)) < 0.1f ? NSControlStateValueMixed : NSControlStateValueOff)); })
- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = [anItem action];
	NSInteger const tag = [anItem tag];

	// File:
	if(@selector(reveal:) == action) {
		if([[self activeDocument] isOnline]) [anItem setTitle:NSLocalizedString(@"Reveal in Browser", @"Reveal in Finder, Path Finder (www.cocoatech.com) or web browser. Three states of the same item.")];
		else if([[PGDocumentController sharedDocumentController] pathFinderRunning]) [anItem setTitle:NSLocalizedString(@"Reveal in Path Finder", @"Reveal in Finder, Path Finder (www.cocoatech.com) or web browser. Three states of the same item.")];
		else [anItem setTitle:NSLocalizedString(@"Reveal in Finder", @"Reveal in Finder, Path Finder (www.cocoatech.com) or web browser. Three states of the same item.")];
	}

	// Edit:
	if(@selector(selectAll:) == action)
		return [[self activeDocument] showsThumbnails];
	if(@selector(performFindPanelAction:) == action) switch([anItem tag]) {
		case NSFindPanelActionShowFindPanel:
		case NSFindPanelActionNext:
		case NSFindPanelActionPrevious: break;
		default: return NO;
	}

	// View:
	if(@selector(toggleFullscreen:) == action)
		[anItem setTitle:NSLocalizedString((PGDocumentController.sharedDocumentController.isFullscreen ?
							@"Exit Full Screen (Sequential)" : @"Enter Full Screen (Sequential)"),
							@"Enter/exit full screen. Two states of the same item.")];

	if(@selector(toggleEntireWindowOrScreen:) == action) {	//	2023/08/14 added; 2023/11/16 renamed
		//	this command is labelled (and behaves) differently depending on the fullscreen state:
		//	* when in Sequential's fullscreen, its label is "Use Entire Screen" and its state depends
		//		on PGDocumentController.sharedDocumentController.usesEntireScreenWhenInFullScreen
		//	* when not in fullscreen, its label is "Use Entire Window"
		//		and its state depends on the window's state
		BOOL const isInSequentialFullscreen = PGDocumentController.sharedDocumentController.fullscreen;
		anItem.title = isInSequentialFullscreen ? @"Use Entire Screen" : @"Use Entire Window";
		if(isInSequentialFullscreen)
			anItem.state = PGDocumentController.sharedDocumentController.usesEntireScreenWhenInFullScreen;
		else
			anItem.state = 0 != (self.window.styleMask & NSWindowStyleMaskFullSizeContentView);

		//	this command is disabled when the window is in macOS' fullscreen mode (ie, not Sequential's)
		return 0 == (self.window.styleMask & NSWindowStyleMaskFullScreen);
	}

	if(@selector(toggleInfo:) == action) [anItem setTitle:NSLocalizedString(([[self activeDocument] showsInfo] ? @"Hide Info" : @"Show Info"), @"Lets the user toggle the on-screen display. Two states of the same item.")];
	if(@selector(toggleThumbnails:) == action) [anItem setTitle:NSLocalizedString(([[self activeDocument] showsThumbnails] ? @"Hide Thumbnails" : @"Show Thumbnails"), @"Lets the user toggle whether thumbnails are shown. Two states of the same item.")];
	if(@selector(changeReadingDirection:) == action) [anItem setState:[[self activeDocument] readingDirection] == tag];
	if(@selector(revertOrientation:) == action) [anItem setState:[[self activeDocument] baseOrientation] == PGUpright];
	if(@selector(toggleAnimation:) == action) {
		BOOL const canAnimate = [_imageView canAnimateRep];
		[anItem setTitle:canAnimate && [[self activeDocument] animatesImages] ? NSLocalizedString(@"Turn Animation Off", @"Title of menu item for toggling animation. Two states.") : NSLocalizedString(@"Turn Animation On", @"Title of menu item for toggling animation. Two states.")];
		if(!canAnimate) return NO;
	}

	// Scale:
	if(@selector(changeImageScaleMode:) == action) {
		if(PGViewFitScale == tag) {
			if([[PGDocumentController sharedDocumentController] isFullscreen]) [anItem setTitle:NSLocalizedString(@"Fit to Screen", @"Scale image down so the entire thing fits menu item. Two labels, depending on mode.")];
			else [anItem setTitle:NSLocalizedString(@"Fit to Window", @"Scale image down so the entire thing fits menu item. Two labels, depending on mode.")];
		}
		if(PGConstantFactorScale == tag) [anItem setState:[[self activeDocument] imageScaleMode] == tag ? PGFuzzyEqualityToCellState(0.0f, log2([[self activeDocument] imageScaleFactor])) : NSControlStateValueOff];
		else [anItem setState:[[self activeDocument] imageScaleMode] == tag];
	}
	if(@selector(changeImageScaleFactor:) == action) [[[PGDocumentController sharedDocumentController] scaleSlider] setDoubleValue:log2([[self activeDocument] imageScaleFactor])];

	// Sort:
	if(@selector(changeSortOrder:) == action) [anItem setState:(PGSortOrderMask & [[self activeDocument] sortOrder]) == tag];
	if(@selector(changeSortDirection:) == action) {
		[anItem setState:tag == (PGSortDescendingMask & [[self activeDocument] sortOrder])];
		if(([[self activeDocument] sortOrder] & PGSortOrderMask) == PGSortShuffle) return NO;
	}
	if(@selector(changeSortRepeat:) == action) [anItem setState:(PGSortRepeatMask & [[self activeDocument] sortOrder]) == tag];

	// Page:
	if(@selector(nextPage:) == action || @selector(lastPage:) == action) [anItem setKeyEquivalent:[[self activeDocument] readingDirection] == PGReadingDirectionLeftToRight ? @"]" : @"["];
	if(@selector(previousPage:) == action || @selector(firstPage:) == action) [anItem setKeyEquivalent:[[self activeDocument] readingDirection] == PGReadingDirectionLeftToRight ? @"[" : @"]"];
	if(@selector(nextPage:) == action || @selector(previousPage:) == action) [anItem setKeyEquivalentModifierMask:kNilOptions];
	if(@selector(jumpToPage:) == action) {
		PGNode *const node = [[anItem representedObject] nonretainedObjectValue];
		NSControlStateValue state = NSControlStateValueOff;
		if(node && node == [self activeNode]) state = NSControlStateValueOn;
		else if([[self activeNode] isDescendantOfNode:node]) state = NSControlStateValueMixed;
		[anItem setState:state];
		return [node isViewable] || [anItem submenu];
	}

	if(![[self activeNode] isViewable]) {
		if(@selector(reveal:) == action) return NO;
		if(@selector(setAsDesktopPicture:) == action) return NO;
		if(@selector(setCopyAsDesktopPicture:) == action) return NO;
		if(@selector(pauseDocument:) == action) return NO;
		if(@selector(pauseAndCloseDocument:) == action) return NO;
		if(@selector(copy:) == action) return NO;
	}
	if(![[[[self activeDocument] node] resourceAdapter] hasNodesWithData]) {
		if(@selector(saveImagesTo:) == action) return NO;
	}
	if(![[[self activeNode] resourceAdapter] canSaveData]) {
		if(@selector(setCopyAsDesktopPicture:) == action) return NO;
	}
	PGResourceIdentifier *const activeNodeIdent = [[self activeNode] identifier];
	if(![activeNodeIdent isFileIdentifier] || ![activeNodeIdent URL]) {
		if(@selector(setAsDesktopPicture:) == action) return NO;
	}
	PGResourceIdentifier *const selectedNodeIdent = [[self selectedNode] identifier];
	if(![selectedNodeIdent isFileIdentifier] || ![selectedNodeIdent URL]) {
		if(@selector(moveToTrash:) == action) return NO;
	}
	if(![[PGDocumentController sharedDocumentController] canToggleFullscreen]) {
		if(@selector(toggleFullscreen:) == action) return NO;
	}
	if(![self canShowInfo]) {
		if(@selector(toggleInfo:) == action) return NO;
	}
	if(![PGThumbnailController canShowThumbnailsForDocument:[self activeDocument]]) {
		if(@selector(toggleThumbnails:) == action) return NO;
	}
	if(![_imageView canAnimateRep]) {
		if(@selector(toggleAnimation:) == action) return NO;
	}
	PGDocument *const doc = [self activeDocument];
	if([doc imageScaleMode] == PGConstantFactorScale) {
		if(@selector(zoomIn:) == action && fabs([_imageView averageScaleFactor] - PGScaleMax) < 0.01f) return NO;
		if(@selector(zoomOut:) == action && fabs([_imageView averageScaleFactor] - PGScaleMin) < 0.01f) return NO;
	}
	PGNode *const firstNode = [[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:YES];
	if(!firstNode) { // We might have to get -firstNode anyway.
		if(@selector(firstPage:) == action) return NO;
		if(@selector(previousPage:) == action) return NO;
		if(@selector(nextPage:) == action) return NO;
		if(@selector(lastPage:) == action) return NO;
		if(@selector(skipBeforeFolder:) == action) return NO;
		if(@selector(skipPastFolder:) == action) return NO;
		if(@selector(firstOfNextFolder:) == action) return NO;
		if(@selector(firstOfPreviousFolder:) == action) return NO;
		if(@selector(firstOfFolder:) == action) return NO;
		if(@selector(lastOfFolder:) == action) return NO;
	}
	if([self activeNode] == firstNode) {
		if(@selector(firstPage:) == action) return NO;
	//	if(@selector(firstOfFolder:) == action) return NO;	see below specific test
	}

	//	2022/11/04 use the correct test (this is a bugfix)
	if(self.activeNode.resourceAdapter.nodeIsFirstOfFolder &&
	   @selector(firstOfFolder:) == action)
		return NO;

	//	2022/11/04 use the correct test (this is a bugfix)
	if(self.activeNode.resourceAdapter.nodeIsLastOfFolder &&
	   @selector(lastOfFolder:) == action)
		return NO;

//	PGNode *const lastNode = [[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:NO];
//	if([self activeNode] == lastNode) {
	if([self activeNode] == [[[[self activeDocument] node] resourceAdapter] sortedViewableNodeFirst:NO]) {
		if(@selector(lastPage:) == action) return NO;
	//	if(@selector(lastOfFolder:) == action) return NO;	see above specific test
	}
	if(![[[[self activeNode] resourceAdapter] containerAdapter] parentAdapter]) {
		if(@selector(skipBeforeFolder:) == action) return NO;
		if(@selector(skipPastFolder:) == action) return NO;
	}
	return [super validateMenuItem:anItem];
}

//	MARK: - NSObject(NSServicesRequests)

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
	BOOL wrote = NO;
	[pboard declareTypes:[NSArray array] owner:nil];
#if __has_feature(objc_arc)
	if([_clipView documentView] == _imageView && [_imageView writeToPasteboard:pboard types:types]) wrote = YES;
#else
	if([clipView documentView] == _imageView && [_imageView writeToPasteboard:pboard types:types]) wrote = YES;
#endif
	if([[self activeNode] writeToPasteboard:pboard types:types]) wrote = YES;
	return wrote;
}

//	MARK: - <NSWindowDelegate>

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu
{
	return ![[self activeDocument] isOnline];
}
- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pboard
{
	if([self window] != window) return YES;
	PGDisplayableIdentifier *const ident = [[[self activeDocument] node] identifier];
	if(![ident isFileIdentifier]) {
		[pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeURL] owner:nil];
		[[ident URL] writeToPasteboard:pboard];
	}
#if __has_feature(objc_arc)
	NSImage *const image = [ident.icon copy];
#else
	NSImage *const image = [[[ident icon] copy] autorelease];
#endif
	NSPoint pt = PGOffsetPointByXY(dragImageLocation, 24 - [image size].width / 2,
								   24 - [image size].height / 2);
	//	OS X will start the drag image 16 pixels down and to the left of the button
	//	which looks bad at both 16x16 and at 32x32, so always do our own drags.
//	[self.window dragImage:image at:pt offset:NSZeroSize event:event pasteboard:pboard source:nil slideBack:YES];
	//	2021/07/21 NB: self is supposed to conform to the NSDraggingSource protocol...
	[self.window dragImage:image at:pt offset:NSZeroSize event:event pasteboard:pboard source:self slideBack:YES];
	return NO;
}
- (id)windowWillReturnFieldEditor:(NSWindow *)window toObject:(id)anObject
{
	if(window != _findPanel) return nil;
	if(!_findFieldEditor) {
		_findFieldEditor = [[PGFindlessTextView alloc] init];
		[_findFieldEditor setFieldEditor:YES];
	}
	return _findFieldEditor;
}

//	MARK : -
/* - (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
NSLog(@"-[PGDisplayController windowWillResize:toSize:(%5.2f, %5.2f)]",
frameSize.width, frameSize.height);
	return frameSize;
} */

//	MARK: -

- (NSApplicationPresentationOptions)window:(NSWindow *)window
	  willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
	// customize our appearance when entering full screen:
	// we don't want the dock to appear but we want the menubar to hide/show automatically
	return (NSApplicationPresentationFullScreen |
			NSApplicationPresentationHideDock |
			NSApplicationPresentationAutoHideMenuBar);
}

- (nullable NSArray<NSWindow *> *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window {
	return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenOnScreen:(NSScreen *)screen
  withDuration:(NSTimeInterval)duration {
//NSLog(@"duration %5.2f", duration);

	_windowFrameBeforeEnteringFullScreen = window.frame;
	[self invalidateRestorableState];

	NSInteger previousWindowLevel = [window level];
	[window setLevel:(NSMainMenuWindowLevel + 1)];

	//	Setting the styleMask will disable the animation (Apple's sample code
	//	does this; why it works in the sample code but not here is unknown).
//	window.styleMask = window.styleMask | NSWindowStyleMaskFullScreen;

	// If our window animation takes the same amount of time as the system's animation,
	// a small black flash will occur atthe end of your animation.  However, if we
	// leave some extra time between when our animation completes and when the system's
	// animation completes we can avoid this.
	duration -= 0.2;

	NSRect proposedFrame = [screen frame];
	if (@available(macOS 12.0, *)) {
		NSEdgeInsets insets = [screen safeAreaInsets];
		proposedFrame.size.height -= insets.top;
	}

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		[context setDuration:duration];

//NSLog(@"(%5.2f, %5.2f) [%5.2f x %5.2f]", proposedFrame.origin.x, proposedFrame.origin.y,
//proposedFrame.size.width, proposedFrame.size.height);
		[window.animator setFrame:proposedFrame display:YES];

		//	altering the styleMask like this causes the Exit Full Screen menu item
		//	to become disabled which makes it very difficult to exit full screen mode:
	//	window.animator.styleMask = window.animator.styleMask & ~NSWindowStyleMaskTitled;
	//	window.animator.titlebarAppearsTransparent = YES; <== doesn't do anything

		[self.thumbnailController parentWindowWillEnterFullScreenToScreenFrame:proposedFrame];

		if(![self _usePreferredBackgroundColorWhenFullScreen])
#if __has_feature(objc_arc)
			_clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:YES];
#else
			clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:YES];
#endif
	} completionHandler:^{
		[self.window setLevel:previousWindowLevel];

//NSLog(@"-[PGDisplayController window:startCustomAnimationToEnterFullScreenOnScreen:withDuration:] DONE");
	}];
}

- (nullable NSArray<NSWindow *> *)customWindowsToExitFullScreenForWindow:(NSWindow *)window {
	return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration {
//NSLog(@"duration %5.2f", duration);

	NSInteger previousWindowLevel = [window level];
	[window setLevel:(NSMainMenuWindowLevel + 1)];

	window.styleMask = window.styleMask & ~NSWindowStyleMaskFullScreen;

	// If our window animation takes the same amount of time as the system's animation,
	// a small black flash will occur atthe end of your animation.  However, if we
	// leave some extra time between when our animation completes and when the system's
	// animation completes we can avoid this.
	duration -= 0.1;

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		[context setDuration:duration];

		[window.animator setFrame:_windowFrameBeforeEnteringFullScreen display:YES];

	//	window.animator.styleMask = window.animator.styleMask | NSWindowStyleMaskTitled;
	//	window.animator.titlebarAppearsTransparent = NO; <== doesn't do anything

		//	not needed and produces an incorrectly located/sized thumbnail browser window
	//	[self.thumbnailController
	//	 parentWindowWillExitFullScreenToScreenFrame:_windowFrameBeforeEnteringFullScreen];

		if(![self _usePreferredBackgroundColorWhenFullScreen])
#if __has_feature(objc_arc)
			_clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:NO];
#else
			clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:NO];
#endif
	} completionHandler:^{
		[self.window setLevel:previousWindowLevel];

//NSLog(@"-[PGDisplayController window:startCustomAnimationToExitFullScreenWithDuration:] DONE");
		NSAssert(NSEqualRects(self.window.frame, _windowFrameBeforeEnteringFullScreen), @"");
		_windowFrameBeforeEnteringFullScreen = NSZeroRect;
	}];
}

//	MARK: -
- (void)windowWillEnterFullScreen:(NSNotification *)notification {
	//	about to enter macOS' fullscreen mode: if the window is in full-size
	//	content mode (titlebar hidden) then switch it back to normal mode
	if(self.window.styleMask & NSWindowStyleMaskFullSizeContentView)
		[_fullSizeContentController toggleFullSizeContent];
}

- (void)_updateViewMenuItems {
	NSMenu *const mainMenu = NSApplication.sharedApplication.mainMenu;
	NSInteger const viewMenuIndex = [mainMenu indexOfItemWithTitle:@"View"];
	NSAssert(NSNotFound != viewMenuIndex, @"");
	NSMenuItem *const viewMenuItem = [mainMenu itemAtIndex:viewMenuIndex];
	NSAssert(nil != viewMenuItem, @"");
	[viewMenuItem.submenu update];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
//NSLog(@"-[PGDisplayController windowDidEnterFullScreen:]");
	[self _setClipViewBackground];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
//NSLog(@"-[PGDisplayController windowDidExitFullScreen:]");
	[self _setClipViewBackground];

	//	When macOS-fullscreen mode is exited, the Use Entire Window command
	//	is not executed when option-F is typed because the menu items in the
	//	View menu are in an incorrect state, so find the View menu and update
	//	its items.
	[self _updateViewMenuItems];
}

//	MARK: -

- (void)windowDidBecomeKey:(NSNotification *)notification
{
#if __has_feature(objc_arc)
	if([notification object] == _findPanel) [_findPanel makeFirstResponder:_searchField];
#else
	if([notification object] == _findPanel) [_findPanel makeFirstResponder:searchField];
#endif
}
- (void)windowDidResignKey:(NSNotification *)notification
{
	if([notification object] == _findPanel) [_findPanel makeFirstResponder:nil];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	NSParameterAssert(notification);
	if([notification object] != [self window]) return;
	[[PGDocumentController sharedDocumentController] setCurrentDocument:[self activeDocument]];

	if(_thumbnailController)
		[_thumbnailController selectionNeedsDisplay];	//	2023/11/12
}
- (void)windowDidResignMain:(NSNotification *)notification
{
	NSParameterAssert(notification);
	if([notification object] != [self window]) return;
	[[PGDocumentController sharedDocumentController] setCurrentDocument:nil];

	if(_thumbnailController)
		[_thumbnailController selectionNeedsDisplay];	//	2023/11/12
}

- (void)windowWillClose:(NSNotification *)notification
{
	NSParameterAssert(notification);
	if([notification object] != [self window])
		return;
	if([_findPanel parentWindow])
		[_findPanel close];
	[self close];
}

- (void)windowWillBeginSheet:(NSNotification *)notification
{
	[_findPanel setIgnoresMouseEvents:YES];
}
- (void)windowDidEndSheet:(NSNotification *)notification
{
	[_findPanel setIgnoresMouseEvents:NO];
}

//	MARK: - <PGClipViewDelegate>

- (BOOL)clipView:(PGClipView *)sender handleMouseEvent:(NSEvent *)anEvent first:(BOOL)flag
{
	if(flag) return NO;
	BOOL const primary = [anEvent type] == NSEventTypeLeftMouseDown;
	BOOL const rtl = [[self activeDocument] readingDirection] == PGReadingDirectionRightToLeft;
	BOOL forward;
	switch([[[NSUserDefaults standardUserDefaults] objectForKey:PGMouseClickActionKey] integerValue]) {
		case PGLeftRightAction: forward = primary == rtl; break;
		case PGRightLeftAction: forward = primary != rtl; break;
		default: forward = primary; break;
	}
	if([anEvent modifierFlags] & NSEventModifierFlagShift) forward = !forward;
	if(forward) [self nextPage:self];
	else [self previousPage:self];
	return YES;
}
- (BOOL)clipView:(PGClipView *)sender handleKeyDown:(NSEvent *)anEvent
{
	NSUInteger const modifiers = (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption) & [anEvent modifierFlags];
	unsigned short const keyCode = [anEvent keyCode];
	if(!modifiers) switch(keyCode) {
		case PGKeyEscape: return [[PGDocumentController sharedDocumentController] performEscapeKeyAction];
	}
	if(!modifiers || !(~(NSEventModifierFlagCommand | NSEventModifierFlagShift) & modifiers)) switch(keyCode) {
		case PGKeyPadPlus:
		case PGKeyPadMinus:
		case PGKeyEquals:
		case PGKeyMinus: [self zoomKeyDown:anEvent]; return YES;
	}
	CGFloat const timerFactor = NSEventModifierFlagOption == modifiers ? 10.0f : 1.0f;
	PGDocument *const d = [self activeDocument];
	if(!modifiers || NSEventModifierFlagOption == modifiers) switch(keyCode) {
		case PGKey0: [self setTimerRunning:NO]; return YES;
		case PGKey1: [d setTimerInterval:1.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey2: [d setTimerInterval:2.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey3: [d setTimerInterval:3.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey4: [d setTimerInterval:4.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey5: [d setTimerInterval:5.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey6: [d setTimerInterval:6.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey7: [d setTimerInterval:7.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey8: [d setTimerInterval:8.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
		case PGKey9: [d setTimerInterval:9.0f * timerFactor]; [self setTimerRunning:YES]; return YES;
	}
	return [self performKeyEquivalent:anEvent];
}
- (BOOL)clipView:(PGClipView *)sender shouldExitEdges:(PGRectEdgeMask)mask
{
	NSAssert(mask, @"At least one edge must be set.");
	NSAssert(!PGHasContradictoryRectEdges(mask), @"Contradictory edges aren't allowed.");
	BOOL const ltr = [[self activeDocument] readingDirection] == PGReadingDirectionLeftToRight;
	PGNode *const activeNode = [self activeNode];
	if(mask & (ltr ? PGMinXEdgeMask : PGMaxXEdgeMask)) [self previousPage:self];
	else if(mask & (ltr ? PGMaxXEdgeMask : PGMinXEdgeMask)) [self nextPage:self];
	return [self activeNode] != activeNode;
}
- (PGRectEdgeMask)clipView:(PGClipView *)sender directionFor:(PGPageLocation)nodeLocation
{
	return PGReadingDirectionAndLocationToRectEdgeMask(nodeLocation, [[self activeDocument] readingDirection]);
}
- (void)clipView:(PGClipView *)sender magnifyBy:(CGFloat)amount
{
	[_imageView setUsesCaching:NO];
	[[self activeDocument] setImageScaleFactor:MAX(PGScaleMin, MIN([_imageView averageScaleFactor] * (amount / 500.0f + 1.0f), PGScaleMax))];
}
- (void)clipView:(PGClipView *)sender rotateByDegrees:(CGFloat)amount
{
#if __has_feature(objc_arc)
	[_clipView scrollCenterTo:[_clipView convertPoint:[_imageView rotateByDegrees:amount adjustingPoint:[_imageView convertPoint:[_clipView center] fromView:_clipView]] fromView:_imageView] animation:PGNoAnimation];
#else
	[clipView scrollCenterTo:[clipView convertPoint:[_imageView rotateByDegrees:amount adjustingPoint:[_imageView convertPoint:[clipView center] fromView:clipView]] fromView:_imageView] animation:PGNoAnimation];
#endif
}
- (void)clipViewGestureDidEnd:(PGClipView *)sender
{
	[_imageView setUsesCaching:YES];
	CGFloat const deg = [_imageView rotationInDegrees];
	[_imageView setRotationInDegrees:0.0f];
	PGOrientation o;
	switch((NSInteger)round((deg + 360.0f) / 90.0f) % 4) {
		case 0: o = PGUpright; break;
		case 1: o = PGRotated90CCW; break;
		case 2: o = PGUpsideDown; break;
		case 3: o = PGRotated90CW; break;
		default: PGAssertNotReached(@"Rotation wasn't simplified into an orientation.");
	}
	[[self activeDocument] setBaseOrientation:PGAddOrientation([[self activeDocument] baseOrientation], o)];
}

@end
