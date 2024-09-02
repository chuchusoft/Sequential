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
#import <QuartzCore/QuartzCore.h>	//	2024/08/14 added for -invertColors:

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

typedef NS_OPTIONS(NSUInteger, PGZoomDirection) {
	PGZoomNone = 0,
	PGZoomIn   = 1 << 0,
	PGZoomOut  = 1 << 1
};

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
	c.attributedStringValue = str;
}


//	MARK: -

@interface IntegerNumberFormatter : NSNumberFormatter
@property (assign, nonatomic) NSInteger maxValue;
@end

@implementation IntegerNumberFormatter

- (BOOL)isPartialStringValid:(NSString *)partialString
			newEditingString:(NSString **)newString
			errorDescription:(NSString **)error {
	// Make sure we clear newString and error to ensure old values aren't being used
	if(newString)
		*newString = nil;
	if(error)
		*error = nil;

	static NSCharacterSet *nonDecimalCharacters = nil;
	if(nonDecimalCharacters == nil)
		nonDecimalCharacters = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

	if(partialString.length == 0)
		return YES; // The empty string is okay (the user clears the field to start over)
	else if([partialString rangeOfCharacterFromSet:nonDecimalCharacters].location != NSNotFound)
		return NO; // Non-decimal characters aren't allowed

	NSInteger const value = partialString.integerValue;
	return 0 < value && value <= self.maxValue;
}

@end

//	MARK: -

#if __has_feature(objc_arc)

@interface PGDisplayController () <NSTextFieldDelegate>

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

//	no need for separate NSView subclass - instead, re-use PGFindView
@property (nonatomic, weak) IBOutlet PGFindView *goToPageView; // 2024/08/16
@property (nonatomic, weak) IBOutlet NSTextField *pageNumberField; // 2024/08/16
@property (nonatomic, weak) IBOutlet NSTextField *maxPageNumberField; // 2024/08/16

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

@property (nonatomic, strong) PGBezelPanel *goToPagePanel; // 2024/08/16

@property (nonatomic, strong) NSDate *nextTimerFireDate;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) PGFullSizeContentController *fullSizeContentController;

@property (nonatomic, assign) BeforeState bs;
@property (nonatomic, assign) NSRect windowFrameForNonFullScreenMode;

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

@interface PGDisplayController(Private) <NSTextFieldDelegate>

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
	[NSApp registerServicesMenuSendTypes:[self pasteboardTypes] returnTypes:@[]];
}
- (NSUserDefaultsController *)userDefaults
{
	return [NSUserDefaultsController sharedUserDefaultsController];
}

//	MARK: - PGDisplayController IBAction

- (IBAction)reveal:(id)sender
{
	if(self.activeDocument.online) {
		if([[NSWorkspace sharedWorkspace] openURL:[self.activeDocument.rootIdentifier URLByFollowingAliases:NO]]) return;
	} else {
		NSString *const path = [self.activeNode.identifier URLByFollowingAliases:NO].path;
		if([PGDocumentController sharedDocumentController].pathFinderRunning) {
#if __has_feature(objc_arc)
			if([[[NSAppleScript alloc] initWithSource:[NSString stringWithFormat:@"tell application \"Path Finder\"\nactivate\nreveal \"%@\"\nend tell", path]] executeAndReturnError:NULL])
				return;
#else
			if([[[[NSAppleScript alloc] initWithSource:[NSString stringWithFormat:@"tell application \"Path Finder\"\nactivate\nreveal \"%@\"\nend tell", path]] autorelease] executeAndReturnError:NULL]) return;
#endif
		} else {
		//	if([[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:nil]) return;
			NSString*	rootPath = @(self.activeDocument.rootIdentifier.URL.fileSystemRepresentation);
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
	[[[PGImageSaveAlert alloc] initWithRoot:self.activeDocument.node initialSelection:self.selectedNodes] beginSheetForWindow:self.windowForSheet];
#else
	[[[[PGImageSaveAlert alloc] initWithRoot:[[self activeDocument] node] initialSelection:[self selectedNodes]] autorelease] beginSheetForWindow:[self windowForSheet]];
#endif
}
- (IBAction)setAsDesktopPicture:(id)sender
{
	PGResourceIdentifier *const ident = self.activeNode.identifier;
//	if(![ident isFileIdentifier] || ![[NSScreen PG_mainScreen] PG_setDesktopImageURL:[ident URLByFollowingAliases:YES]]) NSBeep();
	if(!ident.isFileIdentifier ||
		!SetDesktopImage([NSScreen PG_mainScreen], [ident URLByFollowingAliases:YES]))
		NSBeep();
}
- (IBAction)setCopyAsDesktopPicture:(id)sender
{
	NSSavePanel *const savePanel = [NSSavePanel savePanel];
	[savePanel setTitle:NSLocalizedString(@"Save Copy as Desktop Picture", @"Title of save dialog when setting a copy as the desktop picture.")];
	PGDisplayableIdentifier *const ident = self.activeNode.identifier;
//	[savePanel setRequiredFileType:[[ident naturalDisplayName] pathExtension]];
	savePanel.allowedFileTypes = @[ident.naturalDisplayName.pathExtension];

	[savePanel setCanSelectHiddenExtension:YES];
	NSWindow *const window = self.windowForSheet;
	NSString *const file = ident.naturalDisplayName.stringByDeletingPathExtension;
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
	for(PGNode *const node in self.selectedNodes) {
#if 1
		[NSWorkspace.sharedWorkspace recycleURLs:@[node.identifier.URL]
							   completionHandler:^(NSDictionary<NSURL*,NSURL*>* newURLs, NSError* error) {
			if(nil != error)
				return;

			movedAnything = YES;
			[node removeFromDocument];	//	2024/02/29 remove node from model and UI
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
			self.findPanelShown = !(self.findPanelShown && _findPanel.keyWindow);
			break;
		case NSFindPanelActionNext:
		case NSFindPanelActionPrevious:
		{
#if __has_feature(objc_arc)
			NSArray *const terms = [_searchField.stringValue PG_searchTerms];
#else
			NSArray *const terms = [[searchField stringValue] PG_searchTerms];
#endif
			if(terms && terms.count && ![self tryToSetActiveNode:[self.activeNode.resourceAdapter sortedViewableNodeNext:[sender tag] == NSFindPanelActionNext matchSearchTerms:terms] forward:YES]) NSBeep();
			break;
		}
		default:
			NSBeep();
	}
#if __has_feature(objc_arc)
	if(_findPanel.isKeyWindow) [_findPanel makeFirstResponder:_searchField];
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
	BOOL const inFullscreen = dc.fullscreen;
	if(!inFullscreen) {
		BOOL const inFullSizeContentMode =
			0 != (self.window.styleMask & NSWindowStyleMaskFullSizeContentView);
		_inFullSizeContentModeForNonFullScreenMode = inFullSizeContentMode;
		if(inFullSizeContentMode)
			[_fullSizeContentController toggleFullSizeContentWithAnimation:NO];
	}

	dc.fullscreen = !inFullscreen;	//	creates/destroys a fullscreen window; not animated

	//	because of the way classic fullscreen is implemented, this if never executes;
	//	see -setInFullSizeContentModeForNonFullScreenMode: for the code which handles this case
//	if(inFullscreen && _inFullSizeContentModeForNonFullScreenMode)
//		[_fullSizeContentController toggleFullSizeContentWithAnimation:NO];

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
		[_fullSizeContentController toggleFullSizeContentWithAnimation:YES];
}

- (IBAction)toggleInfo:(id)sender
{
	self.activeDocument.showsInfo = !self.activeDocument.showsInfo;
}

- (IBAction)toggleThumbnails:(id)sender
{
	self.activeDocument.showsThumbnails = !self.activeDocument.showsThumbnails;
}
- (IBAction)changeReadingDirection:(id)sender
{
	self.activeDocument.readingDirection = [sender tag];
}
- (IBAction)changeSortOrder:(id)sender
{
	self.activeDocument.sortOrder = ([sender tag] & PGSortOrderMask) | (self.activeDocument.sortOrder & PGSortOptionsMask);
}
- (IBAction)changeSortDirection:(id)sender
{
	self.activeDocument.sortOrder = (self.activeDocument.sortOrder & ~PGSortDescendingMask) | [sender tag];
}
- (IBAction)changeSortRepeat:(id)sender
{
	self.activeDocument.sortOrder = (self.activeDocument.sortOrder & ~PGSortRepeatMask) | [sender tag];
}
- (IBAction)revertOrientation:(id)sender
{
	self.activeDocument.baseOrientation = PGUpright;
}
- (IBAction)changeOrientation:(id)sender
{
	self.activeDocument.baseOrientation = PGAddOrientation(self.activeDocument.baseOrientation, [sender tag]);
}
- (IBAction)resetRotation:(id)sender
{
#if __has_feature(objc_arc)
	[_clipView scrollCenterTo:[_clipView convertPoint:[_imageView rotateToDegrees:0 adjustingPoint:[_imageView convertPoint:_clipView.center fromView:_clipView]] fromView:_imageView] animation:PGNoAnimation];
#else
	[clipView scrollCenterTo:[clipView convertPoint:[_imageView rotateToDegrees:0 adjustingPoint:[_imageView convertPoint:[clipView center] fromView:clipView]] fromView:_imageView] animation:PGNoAnimation];
#endif
}
- (IBAction)toggleAnimation:(id)sender
{
	NSParameterAssert([_imageView canAnimateRep]);
	BOOL const nowPlaying = !self.activeDocument.animatesImages;
	[_graphicPanel.contentView pushGraphic:[PGBezierPathIconGraphic graphicWithIconType:nowPlaying ? AEPlayIcon : AEPauseIcon] window:self.window];
	self.activeDocument.animatesImages = nowPlaying;
}
- (IBAction)toggleColorInversion:(id)sender	//	2024/08/14 added action for better PDF reading in Dark Mode
{
	PGImageView *iv = self.imageView;
	if(!iv)
		return;

	const BOOL invertColors = !iv.wantsLayer;
	iv.wantsLayer = invertColors;
	iv.layer.filters = invertColors ? @[
						//	first, invert the colors (white --> black, etc.)
						[CIFilter filterWithName:@"CIColorInvert"],
						//	next, darken the whites to enhance readability
						//	because really bright whites are hard to look
						//	at for a long time in a darkened environment
						[CIFilter filterWithName:@"CIExposureAdjust"
							 withInputParameters:@{@"inputEV": @-1.1}]] : nil;
#if !defined(NDEBUG) && 0
	NSLog(@"self.imageView.layer = %@, self.imageView.layer.filters = %@",
			iv.layer, iv.layer.filters);
#endif
}

//	MARK: -

- (IBAction)changeImageScaleMode:(id)sender
{
	//	see -documentImageScaleDidChange:
	self.activeDocument.imageScaleMode = [sender tag];
}
- (IBAction)zoomIn:(id)sender
{
	if(![self zoomKeyDown:self.window.currentEvent]) [self zoomBy:2.0f animate:YES];
}
- (IBAction)zoomOut:(id)sender
{
	if(![self zoomKeyDown:self.window.currentEvent]) [self zoomBy:0.5f animate:YES];
}
- (IBAction)changeImageScaleFactor:(id)sender
{
	[self.activeDocument setImageScaleFactor:pow(2.0f, (CGFloat)[sender doubleValue]) animate:NO];
	[[PGDocumentController sharedDocumentController].scaleMenu update];
}
- (IBAction)minImageScaleFactor:(id)sender
{
	[self.activeDocument setImageScaleFactor:PGScaleMin];
	[[PGDocumentController sharedDocumentController].scaleMenu update];
}
- (IBAction)maxImageScaleFactor:(id)sender
{
	[self.activeDocument setImageScaleFactor:PGScaleMax];
	[[PGDocumentController sharedDocumentController].scaleMenu update];
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
	[self setActiveNode:[self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:YES] forward:YES];
}
- (IBAction)lastPage:(id)sender
{
	[self setActiveNode:[self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:NO] forward:NO];
}

//	MARK: -

- (IBAction)firstOfPreviousFolder:(id)sender
{
	if([self tryToSetActiveNode:[self.activeNode.resourceAdapter sortedFirstViewableNodeInFolderNext:NO inclusive:NO] forward:YES]) return;
	[self prepareToLoop]; // -firstOfPreviousFolder: is an exception to our usual looping mechanic, so we can't use -loopForward:.
	PGNode *const last = [self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:NO];
	[self tryToLoopForward:NO toNode:last.resourceAdapter.isSortedFirstViewableNodeOfFolder ? last : [last.resourceAdapter sortedFirstViewableNodeInFolderNext:NO inclusive:YES] pageForward:YES allowAlerts:YES];
}
- (IBAction)firstOfNextFolder:(id)sender
{
	if([self tryToSetActiveNode:[self.activeNode.resourceAdapter sortedFirstViewableNodeInFolderNext:YES inclusive:NO] forward:YES]) return;
	[self loopForward:YES];
}
- (IBAction)skipBeforeFolder:(id)sender
{
	if([self tryToSetActiveNode:[self.activeNode.resourceAdapter.containerAdapter sortedViewableNodeNext:NO includeChildren:NO] forward:NO]) return;
	[self loopForward:NO];
}
- (IBAction)skipPastFolder:(id)sender
{
	if([self tryToSetActiveNode:[self.activeNode.resourceAdapter.containerAdapter sortedViewableNodeNext:YES includeChildren:NO] forward:YES]) return;
	[self loopForward:YES];
}
- (IBAction)firstOfFolder:(id)sender
{
	[self setActiveNode:[self.activeNode.resourceAdapter sortedViewableNodeInFolderFirst:YES] forward:YES];
}
- (IBAction)lastOfFolder:(id)sender
{
	[self setActiveNode:[self.activeNode.resourceAdapter sortedViewableNodeInFolderFirst:NO] forward:NO];
}

//	MARK: - Go To Page Number

- (void)pageNumberFieldDidChange:(NSNotification *)notification {
	NSTextField *tf = (NSTextField *)notification.object;
//NSLog(@"-pageNumberFieldDidChange: \"%@\"", tf.stringValue);
	if(0 == tf.stringValue.length)
		return;

	NSInteger const value = tf.stringValue.integerValue;

	PGNode *const activeNode = self.activeNode;
	NSParameterAssert(activeNode);
	PGNode *const parentNode = activeNode.parentNode;
	NSParameterAssert(parentNode);

	PGResourceAdapter *ra = parentNode.resourceAdapter;
	PGContainerAdapter *ca = ra.isContainer ? (PGContainerAdapter *)ra : nil;
	NSParameterAssert(ca);

	NSParameterAssert(0 < value && (NSUInteger) value <= ca.sortedChildren.count);
	PGNode *const node = [ca.sortedChildren objectAtIndex:value-1];
	NSParameterAssert(ca);
	[self setActiveNode:node forward:YES];
}

//	@protocol NSControlTextEditingDelegate
- (BOOL)control:(NSControl *)control
	   textView:(NSTextView *)textView
	doCommandBySelector:(SEL)commandSelector {
//NSLog(@"Selector method is (%@)", NSStringFromSelector(commandSelector));

	//	<https://stackoverflow.com/questions/995758/execute-an-action-when-the-enter-key-is-pressed-in-a-nstextfield>
	if(commandSelector == @selector(insertNewline:)) {
		//Do something against ENTER key
		[self toggleGoToPagePanelVisibility:nil];
		return YES;
	} else if(commandSelector == @selector(deleteForward:)) {
		//Do something against DELETE key
	} else if(commandSelector == @selector(deleteBackward:)) {
		//Do something against BACKSPACE key
	} else if(commandSelector == @selector(insertTab:)) {
		//Do something against TAB key
	} else if(commandSelector == @selector(cancelOperation:)) {
		//Do something against Escape key
		[self toggleGoToPagePanelVisibility:nil];
		return YES;
	}

	return NO;
}

- (IBAction)toggleGoToPagePanelVisibility:(id)sender
{
	self.goToPagePanelShown = !(self.goToPagePanelShown && _goToPagePanel.keyWindow);

	if(_goToPagePanel.isKeyWindow) {
		[_goToPagePanel makeFirstResponder:_pageNumberField];

		PGNode *const activeNode = self.activeNode;
		NSParameterAssert(nil != activeNode);
		PGNode *const parentNode = activeNode.parentNode;
		NSParameterAssert(nil != parentNode);

		PGResourceAdapter *ra = parentNode.resourceAdapter;
		PGContainerAdapter *ca = ra.isContainer ? (PGContainerAdapter *)ra : nil;
		NSParameterAssert(nil != ca);

		//	page number field
		NSParameterAssert(nil != _pageNumberField);
		_pageNumberField.integerValue = ca ?
			1 + [ca.sortedChildren indexOfObject:activeNode] : 0;
		_maxPageNumberField.stringValue = [NSString stringWithFormat:@"/ %lu", ca.sortedChildren.count];

		IntegerNumberFormatter *nf = _pageNumberField.cell.formatter;
		nf.maxValue = ca.sortedChildren.count;
	}
}

//	MARK: -

- (IBAction)jumpToPage:(id)sender
{
	PGNode *node = [((NSMenuItem *)sender).representedObject nonretainedObjectValue];
	if(!node.isViewable) node = [node.resourceAdapter sortedViewableNodeFirst:YES];
	if(self.activeNode == node || !node) return;
	[self setActiveNode:node forward:YES];
}

//	MARK: -

- (IBAction)pauseDocument:(id)sender
{
	[[PGBookmarkController sharedBookmarkController] addBookmark:self.activeNode.bookmark];
}
- (IBAction)pauseAndCloseDocument:(id)sender
{
	[self pauseDocument:sender];
	[self.activeDocument close];
}

//	MARK: -

- (IBAction)reload:(id)sender
{
#if __has_feature(objc_arc)
	[_reloadButton setEnabled:NO];
#else
	[reloadButton setEnabled:NO];
#endif
	[self.activeNode reload];
	[self _readActiveNode];
}
- (IBAction)decrypt:(id)sender
{
	PGNode *const activeNode = self.activeNode;
	[activeNode PG_addObserver:self selector:@selector(nodeLoadingDidProgress:) name:PGNodeLoadingDidProgressNotification];
	[activeNode PG_addObserver:self selector:@selector(nodeReadyForViewing:) name:PGNodeReadyForViewingNotification];
	// TODO: Figure this out.
//	[[[activeNode resourceAdapter] info] setObject:[_passwordField stringValue] forKey:PGPasswordKey];
	[activeNode becomeViewed];
}

//	MARK: - public API (properties)

#if !__has_feature(objc_arc)
@synthesize activeDocument = _activeDocument;
@synthesize activeNode = _activeNode;
#endif
- (NSWindow *)windowForSheet
{
	return self.window;
}
- (NSSet *)selectedNodes
{
	NSSet *const thumbnailSelection = _thumbnailController.selectedNodes;
	if(thumbnailSelection.count) return thumbnailSelection;
	return self.activeNode ? [NSSet setWithObject:self.activeNode] : [NSSet set];
}
- (void)setSelectedNodes:(NSSet *)selectedNodes {	//	2023/10/02 was readonly
	_thumbnailController.selectedNodes = selectedNodes;
}

- (PGNode *)selectedNode
{
	NSSet *const selectedNodes = self.selectedNodes;
	return selectedNodes.count == 1 ? [selectedNodes anyObject] : nil;
}
#if !__has_feature(objc_arc)
@synthesize clipView;
@synthesize initialLocation = _initialLocation;
@synthesize reading = _reading;
#endif
- (BOOL)isDisplayingImage
{
#if __has_feature(objc_arc)
	return _clipView.documentView == _imageView;
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
	return self.activeDocument.showsInfo && self.canShowInfo;
}
- (BOOL)loadingIndicatorShown
{
	return _loadingGraphic != nil;
}
- (BOOL)findPanelShown
{
	return _findPanel.visible && !_findPanel.isFadingOut;
}
- (void)setFindPanelShown:(BOOL)flag
{
	if(flag) {
	//	NSDisableScreenUpdates();	2021/07/21 deprecated
		[self.window orderFront:self];
		if(!self.findPanelShown) [_findPanel displayOverWindow:self.window];
		[_findPanel makeKeyWindow];
		[self documentReadingDirectionDidChange:nil];
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
	} else {
		[_findPanel fadeOut];
		[self documentReadingDirectionDidChange:nil];
		[self.window makeKeyWindow];
	}
}
- (BOOL)goToPagePanelShown
{
	return _goToPagePanel.visible && !_goToPagePanel.isFadingOut;
}
- (void)setGoToPagePanelShown:(BOOL)flag
{
	if(flag) {
	//	NSDisableScreenUpdates();	2021/07/21 deprecated
		[self.window orderFront:self];
		if(!self.goToPagePanelShown) [_goToPagePanel displayOverWindow:self.window];
		[_goToPagePanel makeKeyWindow];
		[self documentReadingDirectionDidChange:nil];
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
	} else {
		[_goToPagePanel fadeOut];
		[self documentReadingDirectionDidChange:nil];
		[self.window makeKeyWindow];
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
		_nextTimerFireDate = [[NSDate alloc] initWithTimeIntervalSinceNow:self.activeDocument.timerInterval];
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

- (void)setInFullSizeContentModeForNonFullScreenMode:(BOOL)fullSizeContentMode {
	_inFullSizeContentModeForNonFullScreenMode = fullSizeContentMode;

	//	this setting is transferred twice:
	//	(1) from the old non-fullscreen controller to the fullscreen controller with
	//		PGDocumentController.sharedDocumentController.fullscreen being true, and
	//	(2) from the fullscreen controller to the new non-fullscreen controller with
	//		PGDocumentController.sharedDocumentController.fullscreen being false
	//	the fullSizeContentController is only altered on the second transfer, ie, (2)
	if(fullSizeContentMode && !PGDocumentController.sharedDocumentController.fullscreen)
		[_fullSizeContentController toggleFullSizeContentWithAnimation:NO];
}

//	MARK: - public API (methods)

- (BOOL)setActiveDocument:(PGDocument *)document closeIfAppropriate:(BOOL)flag
{
	if(document == _activeDocument) return NO;
	if(_activeDocument) {
		if(_reading) [_imageView setImageRep:nil orientation:PGUpright size:NSZeroSize];
#if __has_feature(objc_arc)
		[_activeDocument storeNode:self.activeNode imageView:_imageView offset:_clipView.pinLocationOffset query:_searchField.stringValue];
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
		[self.window close];
		return YES;
	}
	_activeDocument = document;
	if(self.window.mainWindow) [PGDocumentController sharedDocumentController].currentDocument = _activeDocument;
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
		if(view.rep) {
			[self _setActiveNode:node];
#if __has_feature(objc_arc)
			_clipView.documentView = view;
#else
			[clipView setDocumentView:view];
#endif
			[view setImageRep:view.rep
				  orientation:view.orientation
						 size:[self _sizeForImageRep:view.rep orientation:view.orientation]];
#if __has_feature(objc_arc)
			[_clipView scrollPinLocationToOffset:offset animation:PGNoAnimation];
#else
			[clipView scrollPinLocationToOffset:offset animation:PGNoAnimation];
#endif
			[self _readFinished];
		} else {
#if __has_feature(objc_arc)
			_clipView.documentView = view;
#else
			[clipView setDocumentView:view];
#endif
			[self setActiveNode:node forward:YES];
		}
		[self documentNodeIsViewableDidChange:nil]; // In case the node has become unviewable in the meantime.
#if __has_feature(objc_arc)
		_searchField.stringValue = query;
#else
		[searchField setStringValue:query];
#endif

		[self documentReadingDirectionDidChange:nil];
		[self documentShowsInfoDidChange:nil];
		[self documentShowsThumbnailsDidChange:nil];	//	creates the thumbnailController
		_thumbnailController.document = _activeDocument;
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
	}
	return NO;
}
- (void)activateDocument:(PGDocument *)document
{
	[self setActiveDocument:document closeIfAppropriate:NO];
	[self.window makeKeyAndOrderFront:self];
}

//	MARK: -

- (void)setActiveNode:(PGNode *)aNode forward:(BOOL)flag
{
	if(![self _setActiveNode:aNode]) return;
	if(self.window.currentEvent.modifierFlags & NSEventModifierFlagControl) _initialLocation = PGPreserveLocation;
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
	if([self tryToSetActiveNode:[self.activeNode.resourceAdapter sortedViewableNodeNext:forward] forward:forward]) return YES;
	[self prepareToLoop];
	return [self tryToLoopForward:forward toNode:[self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:forward] pageForward:forward allowAlerts:flag];
}
- (void)loopForward:(BOOL)flag
{
	[self prepareToLoop];
	[self tryToLoopForward:flag toNode:[self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:flag] pageForward:flag allowAlerts:YES];
}
- (void)prepareToLoop
{
	PGSortOrder const o = self.activeDocument.sortOrder;
	if(!(PGSortRepeatMask & o) || (PGSortOrderMask & o) != PGSortShuffle) return;
	PGDocument *const doc = self.activeDocument;
	[doc.node noteSortOrderDidChange]; // Reshuffle.
	[doc noteSortedChildrenDidChange];
}
- (BOOL)tryToLoopForward:(BOOL)loopForward toNode:(PGNode *)node pageForward:(BOOL)pageForward allowAlerts:(BOOL)flag
{
	PGDocument *const doc = self.activeDocument;
	BOOL const left = (doc.readingDirection == PGReadingDirectionLeftToRight) == !loopForward;
	PGSortOrder const o = self.activeDocument.sortOrder;
	if(PGSortRepeatMask & o && [self tryToSetActiveNode:node forward:pageForward]) {
		if(flag) [_graphicPanel.contentView pushGraphic:left ? [PGAlertGraphic loopedLeftGraphic] : [PGAlertGraphic loopedRightGraphic] window:self.window];
		return YES;
	}
	if(flag) [_graphicPanel.contentView pushGraphic:left ? [PGAlertGraphic cannotGoLeftGraphic] : [PGAlertGraphic cannotGoRightGraphic] window:self.window];
	return NO;
}
- (void)activateNode:(PGNode *)node
{
	[self setActiveDocument:node.document closeIfAppropriate:NO];
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
	_loadingGraphic.progress = self.activeNode.resourceAdapter.activity.progress;
	[_graphicPanel.contentView pushGraphic:_loadingGraphic window:self.window];
}
- (void)offerToOpenBookmark:(PGBookmark *)bookmark
{
#if __has_feature(objc_arc)
	NSAlert *alert = [NSAlert new];
#else
	NSAlert *const alert = [NSAlert new];
#endif
	alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"This document has a bookmark for the page %@.", @"Offer to resume from bookmark alert message text. %@ is replaced with the page name."), bookmark.fileIdentifier.displayName];
	[alert setInformativeText:NSLocalizedString(@"If you don't resume from this page, the bookmark will be kept and you will start from the first page as usual.", @"Offer to resume from bookmark alert informative text.")];
	[alert addButtonWithTitle:NSLocalizedString(@"Resume", @"Do resume from bookmark button.")].keyEquivalent = @"\r";
	[alert addButtonWithTitle:NSLocalizedString(@"Don't Resume", @"Don't resume from bookmark button.")].keyEquivalent = @"\e";
	NSWindow *const window = self.windowForSheet;
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
	self.timerRunning = [self tryToGoForward:YES allowAlerts:YES];
}

//	MARK: -

- (void)zoomBy:(CGFloat)factor animate:(BOOL)flag
{
	[self.activeDocument setImageScaleFactor:MAX(PGScaleMin, MIN([_imageView averageScaleFactor] * factor, PGScaleMax)) animate:flag];
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
		NSEventType const type = latestEvent.type;
		if(NSEventTypeKeyDown == type || NSEventTypeKeyUp == type) {
			PGZoomDirection newDir = PGZoomNone;
			switch(latestEvent.keyCode) {
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
	} while(!stop && (latestEvent = [self.window nextEventMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskPeriodic untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES]));
	[NSEvent stopPeriodicEvents];
	[self.window discardEventsMatchingMask:NSEventMaskAny beforeEvent:latestEvent];
	[_imageView setUsesCaching:YES];
	return didAnything;
}

//	MARK: - notification handlers

- (void)clipViewFrameDidChange:(NSNotification *)aNotif
{
	[self _updateImageViewSizeAllowAnimation:NO];
}

//	MARK: -

- (void)nodeLoadingDidProgress:(NSNotification *)aNotif
{
	NSParameterAssert([aNotif object] == [self activeNode]);
	_loadingGraphic.progress = self.activeNode.resourceAdapter.activity.progress;
}
- (void)nodeReadyForViewing:(NSNotification *)aNotif
{
	NSParameterAssert([aNotif object] == [self activeNode]);
	NSError *const error = self.activeNode.resourceAdapter.error;
	if(!error) {
#if __has_feature(objc_arc)
		NSPoint const relativeCenter = _clipView.relativeCenter;
#else
		NSPoint const relativeCenter = [clipView relativeCenter];
#endif
		NSImageRep *const rep = aNotif.userInfo[PGImageRepKey];
		PGOrientation const orientation = [self.activeNode.resourceAdapter orientationWithBase:YES];
		[_imageView setImageRep:rep
					orientation:orientation
						   size:[self _sizeForImageRep:rep orientation:orientation]];
#if __has_feature(objc_arc)
		_clipView.documentView = _imageView;
		if(PGPreserveLocation == _initialLocation)
			[_clipView scrollRelativeCenterTo:relativeCenter animation:PGNoAnimation];
		else
			[_clipView scrollToLocation:_initialLocation animation:PGNoAnimation];
		[self.window makeFirstResponder:_clipView];
#else
		[clipView setDocumentView:_imageView];
		if(PGPreserveLocation == _initialLocation)
			[clipView scrollRelativeCenterTo:relativeCenter animation:PGNoAnimation];
		else
			[clipView scrollToLocation:_initialLocation animation:PGNoAnimation];
		[[self window] makeFirstResponder:clipView];
#endif
	} else if(PGEqualObjects(error.domain, PGNodeErrorDomain)) switch(error.code) {
		case PGGenericError:
#if __has_feature(objc_arc)
			SetControlAttributedStringValue(_errorLabel,
				[_activeNode.resourceAdapter.dataProvider attributedString]);
		//	[_errorLabel PG_setAttributedStringValue:[[[_activeNode resourceAdapter] dataProvider] attributedString]];
			_errorMessage.stringValue = error.localizedDescription;
			[_errorView setFrameSize:NSMakeSize(NSWidth(_errorView.frame), NSHeight(_errorView.frame) - NSHeight(_errorMessage.frame) + [_errorMessage.cell cellSizeForBounds:NSMakeRect(0.0f, 0.0f, NSWidth(_errorMessage.frame), CGFLOAT_MAX)].height)];
			[_reloadButton setEnabled:YES];
			_clipView.documentView = _errorView;
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
			_passwordField.stringValue = @"";
			_clipView.documentView = _passwordView;
#else
			SetControlAttributedStringValue(passwordLabel,
				[_activeNode.resourceAdapter.dataProvider attributedString]);
		//	[passwordLabel PG_setAttributedStringValue:[[[_activeNode resourceAdapter] dataProvider] attributedString]];
			[passwordField setStringValue:@""];
			[clipView setDocumentView:passwordView];
#endif
			break;
	}
	if(!_imageView.superview) [_imageView setImageRep:nil orientation:PGUpright size:NSZeroSize];
	[self _readFinished];
	[_thumbnailController clipViewBoundsDidChange:nil];
}

//	MARK: -

- (void)documentWillRemoveNodes:(NSNotification *)aNotif
{
	PGNode *const changedNode = aNotif.userInfo[PGDocumentNodeKey];
	NSArray *const removedChildren = aNotif.userInfo[PGDocumentRemovedChildrenKey];
	PGNode *node = [self.activeNode.resourceAdapter sortedViewableNodeNext:YES afterRemovalOfChildren:removedChildren fromNode:changedNode];
	if(!node) node = [self.activeNode.resourceAdapter sortedViewableNodeNext:NO afterRemovalOfChildren:removedChildren fromNode:changedNode];
	[self setActiveNode:node forward:YES];
}
- (void)documentSortedNodesDidChange:(NSNotification *)aNotif
{
	[self documentShowsInfoDidChange:nil];
	[self documentShowsThumbnailsDidChange:nil];
	if(!self.activeNode) [self setActiveNode:[self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:YES] forward:YES];
	else [self _updateNodeIndex];
}
- (void)documentNodeDisplayNameDidChange:(NSNotification *)aNotif
{
	NSParameterAssert(aNotif);
	PGNode *const node = aNotif.userInfo[PGDocumentNodeKey];
	if(self.activeNode == node || self.activeNode.parentNode == node) [self _updateInfoPanelText]; // The parent may be displayed too, depending.
}
- (void)documentNodeIsViewableDidChange:(NSNotification *)aNotif
{
	PGNode *const node = aNotif ? aNotif.userInfo[PGDocumentNodeKey] : self.activeNode;
	if(!self.activeNode) {
		if(node.isViewable) [self setActiveNode:node forward:YES];
	} else if(self.activeNode == node) {
		if(!node.isViewable && ![self tryToGoForward:YES allowAlerts:NO] && ![self tryToGoForward:NO allowAlerts:NO]) [self setActiveNode:[self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:YES] forward:YES];
	}
	if(aNotif) {
		[self documentShowsInfoDidChange:nil];
		[self documentShowsThumbnailsDidChange:nil];
		[self _updateNodeIndex];
	}
}
- (void)documentBaseOrientationDidChange:(NSNotification *)aNotif
{
	PGOrientation const o = [self.activeNode.resourceAdapter orientationWithBase:YES];
	[_imageView setImageRep:_imageView.rep orientation:o size:[self _sizeForImageRep:_imageView.rep orientation:o]];
}

//	MARK: -

- (void)documentShowsInfoDidChange:(NSNotification *)aNotif
{
	if(self.shouldShowInfo) {
		((PGInfoView *)_infoPanel.contentView).count = self.activeDocument.node.resourceAdapter.viewableNodeCount;
		[_infoPanel displayOverWindow:self.window];
	} else [_infoPanel fadeOut];
}
- (void)documentShowsThumbnailsDidChange:(NSNotification *)aNotif
{
	if([PGThumbnailController shouldShowThumbnailsForDocument:self.activeDocument]) {
		if(_thumbnailController) return;
		_thumbnailController = [[PGThumbnailController alloc] init];
	//	NSDisableScreenUpdates();	2021/07/21 deprecated
		_thumbnailController.displayController = self;
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
	if(!self.activeDocument) return;
	BOOL const ltr = self.activeDocument.readingDirection == PGReadingDirectionLeftToRight;
	PGRectCorner const corner = ltr ? PGMinXMinYCorner : PGMaxXMinYCorner;
	PGInset inset = PGZeroInset;
	switch(corner) {
		case PGMinXMinYCorner: inset.minY = self.findPanelShown ? NSHeight(_findPanel.frame) : 0.0f; break;
		case PGMaxXMinYCorner: inset.minX = self.findPanelShown ? NSWidth(_findPanel.frame) : 0.0f; break;
		case PGMinXMaxYCorner:
		case PGMaxXMaxYCorner: break;
	}
	if(_thumbnailController) inset = PGAddInsets(inset, _thumbnailController.contentInset);
	_infoPanel.frameInset = inset;
	((PGInfoView *)_infoPanel.contentView).originCorner = corner;
	[_infoPanel updateFrameDisplay:YES];
	[self.activeDocument.pageMenu update];
}
- (void)documentImageScaleDidChange:(NSNotification *)aNotif
{
	[self _updateImageViewSizeAllowAnimation:[aNotif.userInfo[PGPrefObjectAnimateKey] boolValue]];
}
- (void)documentAnimatesImagesDidChange:(NSNotification *)aNotif
{
	_imageView.animates = self.activeDocument.animatesImages;
}
- (void)documentTimerIntervalDidChange:(NSNotification *)aNotif
{
	self.timerRunning = self.timerRunning;
}

//	MARK: -

- (void)thumbnailControllerContentInsetDidChange:(NSNotification *)aNotif
{
//	NSDisableScreenUpdates();	2021/07/21 deprecated
	PGInset inset = PGZeroInset;
	NSSize minSize = PGWindowMinSize;
	if(_thumbnailController) {
		PGInset const thumbnailInset = _thumbnailController.contentInset;
		inset = PGAddInsets(inset, thumbnailInset);
		minSize.width += thumbnailInset.minX + thumbnailInset.maxX;
	}
#if __has_feature(objc_arc)
	_clipView.boundsInset = inset;
	[_clipView displayIfNeeded];
#else
	[clipView setBoundsInset:inset];
	[clipView displayIfNeeded];
#endif
	_findPanel.frameInset = inset;
	_graphicPanel.frameInset = inset;
	[self _updateImageViewSizeAllowAnimation:NO];
	[self documentReadingDirectionDidChange:nil];
	[_findPanel updateFrameDisplay:YES];
	[_graphicPanel updateFrameDisplay:YES];
	NSWindow *const w = self.window;
	NSRect currentFrame = w.frame;
	if(NSWidth(currentFrame) < minSize.width) {
		currentFrame.size.width = minSize.width;
		[w setFrame:currentFrame display:YES];
	}
	w.minSize = minSize;
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
	_clipView.backgroundColor = clipViewBackgroundColor;
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
	//	active document value. See the corresponding code in
	//	-[PGThumbnailController displayControllerActiveNodeDidChange:]
	[self PG_postNotificationName:PGDisplayControllerActiveNodeDidChangeNotification
						 userInfo:@{ @"PGDocument":_activeDocument, @"PGNode":_activeNode }];
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
	self.timerRunning = self.timerRunning;
}
- (void)_readFinished
{
	_reading = NO;
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(showLoadingIndicator) object:nil];
	[_graphicPanel.contentView popGraphicsOfType:PGSingleImageGraphic]; // Hide most alerts.
#if !__has_feature(objc_arc)
	[_loadingGraphic release];
#endif
	_loadingGraphic = nil;
	[self PG_postNotificationName:PGDisplayControllerActiveNodeWasReadNotification];
}
- (NSSize)_sizeForImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation
{
	return [self _sizeForImageRep:rep
					  orientation:orientation
						scaleMode:self.activeDocument.imageScaleMode
						   factor:self.activeDocument.imageScaleFactor];
}
- (NSSize)_sizeForImageRep:(NSImageRep *)rep
			   orientation:(PGOrientation)orientation
				 scaleMode:(PGImageScaleMode)scaleMode
					factor:(float)factor
{
	if(!rep) return NSZeroSize;
	NSSize originalSize = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
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
		BOOL const resIndependent = self.activeNode.resourceAdapter.resolutionIndependent;
		NSSize const minSize = constraint != PGUpscaleOnly || resIndependent ? NSZeroSize : newSize;
		NSSize const maxSize = constraint != PGDownscaleOnly || resIndependent ? NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX) : newSize;
#if __has_feature(objc_arc)
		NSRect const bounds = _clipView.insetBounds;
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
	[_imageView setSize:[self _sizeForImageRep:_imageView.rep orientation:_imageView.orientation] allowAnimation:flag];
}
- (void)_updateNodeIndex
{
	PGNode *const an = self.activeNode;
	PGResourceAdapter *anra = an.resourceAdapter;
	PGInfoView *const infoView = (PGInfoView *)_infoPanel.contentView;

	_displayImageIndex = anra.viewableNodeIndex;

	infoView.index = _displayImageIndex;

	//	Update the entry in the Window menu, and yes, it's
	//	done in -synchronizeWindowTitleWithDocumentName.
	[self synchronizeWindowTitleWithDocumentName];

	//	update the title bar accessory instead of the title
	{
		NSTextField *const accessoryTextField = _fullSizeContentController.accessoryTextField;

		NSUInteger const nodeCount = self.activeDocument.node.resourceAdapter.viewableNodeCount;
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
				if(!node.isViewable)
					[indexes addIndex:i];
				else if(an == node) {
					NSAssert(NSNotFound == childIndex, @"");

					//	the index after non-viewables are removed from children
					childIndex = i - indexes.count;
				}

				++i;
			}
			if(0 != indexes.count)
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
	PGNode *const node = self.activeNode;
	if(node) {
		text = node.identifier.displayName;
		PGNode *const parent = node.parentNode;
		if(parent.parentNode) text = [NSString stringWithFormat:@"%@ %C %@", parent.identifier.displayName, (unichar)0x25B8, text];
	} else text = NSLocalizedString(@"No image", @"Label for when no image is being displayed in the window.");
	((PGInfoView *)_infoPanel.contentView).stringValue = text;
}
- (void)_setCopyAsDesktopPicturePanelDidEnd:(NSSavePanel *)savePanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if(NSModalResponseOK != returnCode) return;
//	NSURL *const URL = [[savePanel filename] PG_fileURL];
	NSURL *const URL = savePanel.URL;
	[self.activeNode.resourceAdapter.data writeToURL:URL atomically:NO];
//	if(![[NSScreen PG_mainScreen] PG_setDesktopImageURL:URL]) NSBeep();
	if(!SetDesktopImage([NSScreen PG_mainScreen], URL)) NSBeep();
}
- (void)_offerToOpenBookmarkAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode bookmark:(PGBookmark *)bookmark
{
#if __has_feature(objc_arc)
#else
	[bookmark autorelease];
#endif
	if(NSAlertFirstButtonReturn == returnCode) [self.activeDocument openBookmark:bookmark];
}

//	MARK: -NSWindowController

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	[self documentReadingDirectionDidChange:nil];
	if(self.shouldShowInfo) [_infoPanel displayOverWindow:self.window];
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
	[self.window setMinSize:PGWindowMinSize];

#if __has_feature(objc_arc)
	[_clipView setAcceptsFirstResponder:YES];
	_clipView.cursor = [NSCursor openHandCursor];
	[_clipView setPostsFrameChangedNotifications:YES];
	[_clipView PG_addObserver:self selector:@selector(clipViewFrameDidChange:) name:NSViewFrameDidChangeNotification];
#else
	[clipView setAcceptsFirstResponder:YES];
	NSImage *const cursorImage = [NSImage imageNamed:@"Cursor-Hand-Pointing"];
	[clipView setCursor:cursorImage ? [[[NSCursor alloc] initWithImage:cursorImage hotSpot:NSMakePoint(5.0f, 0.0f)] autorelease] : [NSCursor pointingHandCursor]];
	[clipView setPostsFrameChangedNotifications:YES];
	[clipView PG_addObserver:self selector:@selector(clipViewFrameDidChange:) name:NSViewFrameDidChangeNotification];
#endif

#if __has_feature(objc_arc)
	_findPanel = [[PGBezelPanel alloc] initWithContentView:_findView];
	_findPanel.initialFirstResponder = _searchField;
#else
	_findPanel = [[PGBezelPanel alloc] initWithContentView:findView];
	[_findPanel setInitialFirstResponder:searchField];
#endif
	_findPanel.delegate = self;
	[_findPanel setAcceptsEvents:YES];
	[_findPanel setCanBecomeKey:YES];

#if __has_feature(objc_arc)
	_goToPagePanel = [[PGBezelPanel alloc] initWithContentView:_goToPageView];
	_goToPagePanel.initialFirstResponder = _pageNumberField;
#else
	_goToPagePanel = [[PGBezelPanel alloc] initWithContentView:goToPageView];
	[_goToPagePanel setInitialFirstResponder:pageNumberField];
#endif
//	_goToPagePanel.delegate = self;
	[_goToPagePanel setAcceptsEvents:YES];
	[_goToPagePanel setCanBecomeKey:YES];

	_pageNumberField.delegate = self;

	[NSNotificationCenter.defaultCenter
		 addObserver:self
			selector:@selector(pageNumberFieldDidChange:)
				name:NSControlTextDidChangeNotification
			  object:_pageNumberField];

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
	PGDisplayableIdentifier *const identifier = self.activeDocument.node.identifier;
	NSURL *const URL = identifier.URL;
	if(identifier.isFileIdentifier) {
	//	NSString *const path = [identifier isFileIdentifier] ? [URL path] : nil;
	//	[[self window] setRepresentedFilename:path ? path : blank];
		self.window.representedURL = URL;
	} else {
		self.window.representedURL = URL;
		NSButton *const docButton = [self.window standardWindowButton:NSWindowDocumentIconButton];
#if __has_feature(objc_arc)
		NSImage *const image = [identifier.icon copy];
#else
		NSImage *const image = [[[identifier icon] copy] autorelease];
#endif
		image.size = docButton.bounds.size;
		[image recache];
		docButton.image = image;
	}

	NSUInteger const nodeCount = self.activeDocument.node.resourceAdapter.viewableNodeCount;
	NSString *const titleDetails = nodeCount > 1 ?
		[NSString stringWithFormat:@" (%lu/%lu)", (unsigned long)_displayImageIndex + 1, (unsigned long)nodeCount] :
		blank;

	NSString *const title = identifier.displayName;
//	[[self window] setTitle:title ? [title stringByAppendingString:titleDetails] : blank];
	self.window.title = title ? title : blank;

#if __has_feature(objc_arc)
	NSMutableAttributedString *const menuLabel = [[identifier attributedStringWithAncestory:NO] mutableCopy];
#else
	NSMutableAttributedString *const menuLabel = [[[identifier attributedStringWithAncestory:NO] mutableCopy] autorelease];
#endif
	[menuLabel.mutableString appendString:titleDetails];
	[[PGDocumentController sharedDocumentController] windowsMenuItemForDocument:self.activeDocument].attributedTitle = menuLabel;
}
- (void)close
{
	[self.activeDocument close];
}

//	MARK: - NSResponder

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
	return !returnType.length && [self writeSelectionToPasteboard:nil types:@[sendType]] ? self : [super validRequestorForSendType:sendType returnType:returnType];
}

//	MARK: - NSObject

- (instancetype)init
{
	if((self = [super initWithWindowNibName:@"PGDocument"])) {
		(void)self.window; // Just load the window so we don't have to worry about it.

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

	[NSNotificationCenter.defaultCenter
		removeObserver:self
				  name:NSControlTextDidChangeNotification
				object:_pageNumberField];

#if !__has_feature(objc_arc)
	[passwordView release];
	[_activeNode release];
	[_imageView release];	//	bugfix
	[_graphicPanel release];
	[_loadingGraphic release];
	[_infoPanel release];
	[_goToPagePanel release];
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
	SEL const action = anItem.action;
	NSInteger const tag = anItem.tag;

	// File:
	if(@selector(reveal:) == action) {
		if(self.activeDocument.online) [anItem setTitle:NSLocalizedString(@"Reveal in Browser", @"Reveal in Finder, Path Finder (www.cocoatech.com) or web browser. Three states of the same item.")];
		else if([PGDocumentController sharedDocumentController].pathFinderRunning) [anItem setTitle:NSLocalizedString(@"Reveal in Path Finder", @"Reveal in Finder, Path Finder (www.cocoatech.com) or web browser. Three states of the same item.")];
		else [anItem setTitle:NSLocalizedString(@"Reveal in Finder", @"Reveal in Finder, Path Finder (www.cocoatech.com) or web browser. Three states of the same item.")];
	}

	// Edit:
	if(@selector(selectAll:) == action)
		return self.activeDocument.showsThumbnails;
	if(@selector(performFindPanelAction:) == action) switch(anItem.tag) {
		case NSFindPanelActionShowFindPanel:
		case NSFindPanelActionNext:
		case NSFindPanelActionPrevious: break;
		default: return NO;
	}

	// View:
	if(@selector(toggleFullscreen:) == action) {
		anItem.title = NSLocalizedString(
						PGDocumentController.sharedDocumentController.isFullscreen ?
						@"Exit Full Screen (classic)" : @"Enter Full Screen (classic)",
						@"Enter/exit full screen. Two states of the same item.");

		//	if the window is already in macOS-fullscreen mode
		//	then disallow entering classic fullscreen mode
		return !(NSWindowStyleMaskFullScreen & self.window.styleMask) &&
			[PGDocumentController sharedDocumentController].canToggleFullscreen;
	}

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
	if(@selector(changeReadingDirection:) == action) anItem.state = self.activeDocument.readingDirection == tag;
	if(@selector(revertOrientation:) == action) anItem.state = self.activeDocument.baseOrientation == PGUpright;
	if(@selector(toggleAnimation:) == action) {
		BOOL const canAnimate = _imageView.canAnimateRep;
		anItem.title = canAnimate && self.activeDocument.animatesImages ? NSLocalizedString(@"Turn Animation Off", @"Title of menu item for toggling animation. Two states.") : NSLocalizedString(@"Turn Animation On", @"Title of menu item for toggling animation. Two states.");
		if(!canAnimate) return NO;
	}
	if(@selector(toggleColorInversion:) == action) anItem.state = self.imageView.wantsLayer;

	// Scale:
	if(@selector(changeImageScaleMode:) == action) {
		if(PGViewFitScale == tag) {
			if([PGDocumentController sharedDocumentController].fullscreen) [anItem setTitle:NSLocalizedString(@"Fit to Screen", @"Scale image down so the entire thing fits menu item. Two labels, depending on mode.")];
			else [anItem setTitle:NSLocalizedString(@"Fit to Window", @"Scale image down so the entire thing fits menu item. Two labels, depending on mode.")];
		}
		if(PGConstantFactorScale == tag) anItem.state = self.activeDocument.imageScaleMode == tag ? PGFuzzyEqualityToCellState(0.0f, log2([[self activeDocument] imageScaleFactor])) : NSControlStateValueOff;
		else anItem.state = self.activeDocument.imageScaleMode == tag;
	}
	if(@selector(changeImageScaleFactor:) == action) [[PGDocumentController sharedDocumentController].scaleSlider setDoubleValue:log2([[self activeDocument] imageScaleFactor])];

	// Sort:
	if(@selector(changeSortOrder:) == action) anItem.state = (PGSortOrderMask & self.activeDocument.sortOrder) == tag;
	if(@selector(changeSortDirection:) == action) {
		anItem.state = tag == (PGSortDescendingMask & self.activeDocument.sortOrder);
		if((self.activeDocument.sortOrder & PGSortOrderMask) == PGSortShuffle) return NO;
	}
	if(@selector(changeSortRepeat:) == action) anItem.state = (PGSortRepeatMask & self.activeDocument.sortOrder) == tag;

	// Page:
	if(@selector(nextPage:) == action || @selector(lastPage:) == action) anItem.keyEquivalent = self.activeDocument.readingDirection == PGReadingDirectionLeftToRight ? @"]" : @"[";
	if(@selector(previousPage:) == action || @selector(firstPage:) == action) anItem.keyEquivalent = self.activeDocument.readingDirection == PGReadingDirectionLeftToRight ? @"[" : @"]";
	if(@selector(nextPage:) == action || @selector(previousPage:) == action) anItem.keyEquivalentModifierMask = kNilOptions;
	if(@selector(toggleGoToPagePanelVisibility:) == action) {
		PGResourceAdapter *rootNodeRA = self.activeDocument.node.resourceAdapter;
		PGContainerAdapter *ca = rootNodeRA.isContainer ? (PGContainerAdapter *)rootNodeRA : nil;
//NSLog(@"rootNode.resourceAdapter.unsortedChildren.count = %lu", ca.unsortedChildren.count);
		return ca && ca.unsortedChildren.count > 1;
	}
	if(@selector(jumpToPage:) == action) {
		PGNode *const node = [anItem.representedObject nonretainedObjectValue];
		NSControlStateValue state = NSControlStateValueOff;
		if(node && node == self.activeNode) state = NSControlStateValueOn;
		else if([self.activeNode isDescendantOfNode:node]) state = NSControlStateValueMixed;
		anItem.state = state;
		return node.isViewable || anItem.submenu;
	}

	if(!self.activeNode.isViewable) {
		if(@selector(reveal:) == action) return NO;
		if(@selector(setAsDesktopPicture:) == action) return NO;
		if(@selector(setCopyAsDesktopPicture:) == action) return NO;
		if(@selector(pauseDocument:) == action) return NO;
		if(@selector(pauseAndCloseDocument:) == action) return NO;
		if(@selector(copy:) == action) return NO;
	}
	if(!self.activeDocument.node.resourceAdapter.hasNodesWithData) {
		if(@selector(saveImagesTo:) == action) return NO;
	}
	if(!self.activeNode.resourceAdapter.canSaveData) {
		if(@selector(setCopyAsDesktopPicture:) == action) return NO;
	}
	PGResourceIdentifier *const activeNodeIdent = self.activeNode.identifier;
	if(!activeNodeIdent.isFileIdentifier || !activeNodeIdent.URL) {
		if(@selector(setAsDesktopPicture:) == action) return NO;
	}
	PGResourceIdentifier *const selectedNodeIdent = self.selectedNode.identifier;
	if(!selectedNodeIdent.isFileIdentifier || !selectedNodeIdent.URL) {
		if(@selector(moveToTrash:) == action) return NO;
	}
	if(!self.canShowInfo) {
		if(@selector(toggleInfo:) == action) return NO;
	}
	if(![PGThumbnailController canShowThumbnailsForDocument:self.activeDocument]) {
		if(@selector(toggleThumbnails:) == action) return NO;
	}
	if(!_imageView.canAnimateRep) {
		if(@selector(toggleAnimation:) == action) return NO;
	}
	PGDocument *const doc = self.activeDocument;
	if(doc.imageScaleMode == PGConstantFactorScale) {
		if(@selector(zoomIn:) == action && fabs([_imageView averageScaleFactor] - PGScaleMax) < 0.01f) return NO;
		if(@selector(zoomOut:) == action && fabs([_imageView averageScaleFactor] - PGScaleMin) < 0.01f) return NO;
	}
	PGNode *const firstNode = [self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:YES];
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
	if(self.activeNode == firstNode) {
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
	if(self.activeNode == [self.activeDocument.node.resourceAdapter sortedViewableNodeFirst:NO]) {
		if(@selector(lastPage:) == action) return NO;
	//	if(@selector(lastOfFolder:) == action) return NO;	see above specific test
	}
	if(!self.activeNode.resourceAdapter.containerAdapter.parentAdapter) {
		if(@selector(skipBeforeFolder:) == action) return NO;
		if(@selector(skipPastFolder:) == action) return NO;
	}
	return [super validateMenuItem:anItem];
}

//	MARK: - NSObject(NSServicesRequests)

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
	BOOL wrote = NO;
	[pboard declareTypes:@[] owner:nil];
#if __has_feature(objc_arc)
	if(_clipView.documentView == _imageView && [_imageView writeToPasteboard:pboard types:types]) wrote = YES;
#else
	if([clipView documentView] == _imageView && [_imageView writeToPasteboard:pboard types:types]) wrote = YES;
#endif
	if([self.activeNode writeToPasteboard:pboard types:types]) wrote = YES;
	return wrote;
}

//	MARK: - <NSWindowDelegate>

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu
{
	return !self.activeDocument.online;
}
- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pboard
{
	if(self.window != window) return YES;
	PGDisplayableIdentifier *const ident = self.activeDocument.node.identifier;
	if(!ident.isFileIdentifier) {
		[pboard declareTypes:@[NSPasteboardTypeURL] owner:nil];
		[ident.URL writeToPasteboard:pboard];
	}
#if __has_feature(objc_arc)
	NSImage *const image = [ident.icon copy];
#else
	NSImage *const image = [[[ident icon] copy] autorelease];
#endif
	NSPoint pt = PGOffsetPointByXY(dragImageLocation, 24 - image.size.width / 2,
								   24 - image.size.height / 2);
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

//	MARK: -

- (void)windowDidBecomeKey:(NSNotification *)notification
{
#if __has_feature(objc_arc)
	if(notification.object == _findPanel) [_findPanel makeFirstResponder:_searchField];
	else if(notification.object == _goToPagePanel)
		[_goToPagePanel makeFirstResponder:_pageNumberField];
#else
	if([notification object] == _findPanel) [_findPanel makeFirstResponder:searchField];
	else if([notification object] == _goToPagePanel)
		[_goToPagePanel makeFirstResponder:pageNumberField];
#endif
}
- (void)windowDidResignKey:(NSNotification *)notification
{
	if(notification.object == _findPanel) [_findPanel makeFirstResponder:nil];
	else if(notification.object == _goToPagePanel)
		[_goToPagePanel makeFirstResponder:nil];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	NSParameterAssert(notification);
	if(notification.object != self.window) return;
	[PGDocumentController sharedDocumentController].currentDocument = self.activeDocument;

	if(_thumbnailController)
		[_thumbnailController selectionNeedsDisplay];	//	2023/11/12
}
- (void)windowDidResignMain:(NSNotification *)notification
{
	NSParameterAssert(notification);
	if(notification.object != self.window) return;
	[[PGDocumentController sharedDocumentController] setCurrentDocument:nil];

	if(_thumbnailController)
		[_thumbnailController selectionNeedsDisplay];	//	2023/11/12
}

- (void)windowWillClose:(NSNotification *)notification
{
	NSParameterAssert(notification);
	if(notification.object != self.window)
		return;
	if(_findPanel.parentWindow)
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
/*
- (void)windowWillStartLiveResize:(NSNotification *)notification {
NSLog(@"-windowWillStartLiveResize: duration %5.2f", NSAnimationContext.currentContext.duration);
}
- (void)windowDidEndLiveResize:(NSNotification *)notification {
NSLog(@"-windowDidEndLiveResize:");
} */

//	MARK: -

/* - (NSApplicationPresentationOptions)window:(NSWindow *)window
	  willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
	// customize our appearance when entering full screen:
	// we don't want the dock to appear but we want the menubar to hide/show automatically
	return (NSApplicationPresentationFullScreen |
			NSApplicationPresentationHideDock |
			NSApplicationPresentationAutoHideMenuBar);
} */

- (nullable NSArray<NSWindow *> *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window {
	return @[window];
}

static
CGFloat
GetNotchHeight(NSScreen* screen) {
	if(@available(macOS 12.0, *))
		return screen.safeAreaInsets.top;
	else
		return 0;
}

//	Transitioning to fullscreen via the "Tile Window to Left/Right of Screen" always
//	causes the -window:startCustomAnimationToEnterFullScreenWithDuration: method to
//	NOT be called so any member variable changes and method calls it makes are NOT
//	performed. Such code has been moved to the -windowWillEnterFullScreen: method.

#if 1
//	Using this delegate method causes the statement:
//		window.styleMask = window.styleMask | NSWindowStyleMaskFullScreen;
//	to work.
- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
//	NSScreen *screen = [[NSScreen screens] objectAtIndex:0];
	NSScreen *screen = window.screen;
#else
//	Using this delegate method causes the statement:
//		window.styleMask = window.styleMask | NSWindowStyleMaskFullScreen;
//	to not work: the animation does not occur. Instead, the window immediately
//	goes fullscreen. This appears to be a bug in macOS Monterey 12.7.1.
- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenOnScreen:(NSScreen *)screen withDuration:(NSTimeInterval)duration
{
//	NSScreen *screen0 = [[NSScreen screens] objectAtIndex:0];
//NSLog(@"screen %@  screen0 %@", screen, screen0);
#endif
//NSLog(@"duration %5.2f", duration);

//	_windowFrameForNonFullScreenMode = window.frame;
//	_inFullSizeContentModeForNonFullScreenMode =
//		0 != (window.styleMask & NSWindowStyleMaskFullSizeContentView);
	[self invalidateRestorableState];

//	NSInteger previousWindowLevel = [window level];
//	[window setLevel:NSStatusWindowLevel];	<== this causes flashing

	//	if the window is in fullsize content mode then the animation to
	//	go fullscreen will not occur so first get out of fullsize content
	//	mode and then add NSWindowStyleMaskFullScreen to the styleMask
//	if(_inFullSizeContentModeForNonFullScreenMode)
//		[_fullSizeContentController toggleFullSizeContentWithAnimation:YES];

	//	if -toggleFullSizeContent was called, window.styleMask was changed
	//	so it must be reloaded here:
	window.styleMask = window.styleMask | NSWindowStyleMaskFullScreen;

	// If our window animation takes the same amount of time as the system's animation,
	// a small black flash will occur atthe end of your animation.  However, if we
	// leave some extra time between when our animation completes and when the system's
	// animation completes we can avoid this.
	duration -= 0.2;

	NSRect proposedFrame = screen.frame;
#if 1
	proposedFrame.size.height -= GetNotchHeight(screen);
#else
	if(@available(macOS 12.0, *)) {
		proposedFrame.size.height -= screen.safeAreaInsets.top;

/* NSRect vf = screen.visibleFrame;
NSLog(@"visibleFrame (%5.2f, %5.2f) [%5.2f x %5.2f]",
vf.origin.x, vf.origin.y, vf.size.width, vf.size.height);
NSLog(@"proposedFrame (%5.2f, %5.2f) [%5.2f x %5.2f]",
proposedFrame.origin.x, proposedFrame.origin.y,
proposedFrame.size.width, proposedFrame.size.height); */
	}
#endif


	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		context.duration = duration;

		[window.animator setFrame:proposedFrame display:NO];

		[self.thumbnailController parentWindowWillTransitionToScreenFrame:proposedFrame];

		if(![self _usePreferredBackgroundColorWhenFullScreen])
#if __has_feature(objc_arc)
			_clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:YES];
#else
			clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:YES];
#endif
	} completionHandler:^{
	//	[self.window setLevel:previousWindowLevel];

		NSAssert(0 != _bs, @"");
		(void) [PGDocumentController.sharedDocumentController
					togglePanelsForExitingFullScreen:NO
									 withBeforeState:_bs];
		_bs = 0;
	}];
#if 0
}
#else
}
#endif

- (nullable NSArray<NSWindow *> *)customWindowsToExitFullScreenForWindow:(NSWindow *)window {
	return @[window];
}

- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration {
	NSAssert(NSStatusWindowLevel == window.level, @"");
//	NSInteger previousWindowLevel = [window level];
//NSLog(@"%lu", previousWindowLevel);
//	[window setLevel:NSStatusWindowLevel];

	window.styleMask = window.styleMask & ~NSWindowStyleMaskFullScreen;

	// If our window animation takes the same amount of time as the system's animation,
	// a small black flash will occur atthe end of your animation.  However, if we
	// leave some extra time between when our animation completes and when the system's
	// animation completes we can avoid this.
	duration -= 0.1;

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		context.duration = duration;

		//	If the window was in fullsize content mode when fullscreen mode was
		//	entered then restore it. Do this *before* calling -setFrame:display:
		if(_inFullSizeContentModeForNonFullScreenMode)
			[_fullSizeContentController toggleFullSizeContentWithAnimation:YES];

		[window.animator setFrame:_windowFrameForNonFullScreenMode display:YES];

		if(_thumbnailController) {
//	should match #define in PGThumbnailController.m
#define FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE	false
#if FULL_HEIGHT_BROWSER_IN_FULLSIZE_CONTENT_MODE
			[_thumbnailController parentWindowWillTransitionToScreenFrame:
				[window contentRectForFrameRect:_windowFrameForNonFullScreenMode]];
#else
			CGFloat const titleBarHeight = [window
				standardWindowButton:NSWindowCloseButton].superview.frame.size.height;
			[_thumbnailController parentWindowWillTransitionToScreenFrame:
				NSMakeRect(NSMinX(_windowFrameForNonFullScreenMode),
							NSMinY(_windowFrameForNonFullScreenMode),
							NSWidth(_windowFrameForNonFullScreenMode),
							NSHeight(_windowFrameForNonFullScreenMode) - titleBarHeight)];
#endif
		}

		if(![self _usePreferredBackgroundColorWhenFullScreen])
#if __has_feature(objc_arc)
			_clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:NO];
#else
			clipView.animator.backgroundColor =
				[self _clipViewBackgroundColorWhenFullScreen:NO];
#endif
	} completionHandler:^{
	//	[window setLevel:previousWindowLevel];
		window.level = NSNormalWindowLevel;
		NSAssert(NSNormalWindowLevel == window.level, @"");

		NSAssert(NSEqualRects(window.frame, _windowFrameForNonFullScreenMode), @"");
		_windowFrameForNonFullScreenMode = NSZeroRect;
	}];
}

//	MARK: -

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
	NSWindow *window = self.window;

	//	changing the window's level in the method
	//		-window:startCustomAnimationToEnterFullScreenOnScreen:withDuration:
	//	causes a visible screen flashing; doing it in this method does not
	window.level = NSStatusWindowLevel;

	_bs = [PGDocumentController.sharedDocumentController
			togglePanelsForExitingFullScreen:NO
							 withBeforeState:0];

	//	2024/03/01 when transitioning to fullscreen via the "Tile Window to
	//	Left/Right of Screen" command, the method
	//	-window:startCustomAnimationToEnterFullScreenWithDuration:
	//	is not invoked, so code was moved here to ensure correct state.

	_windowFrameForNonFullScreenMode = window.frame;
	_inFullSizeContentModeForNonFullScreenMode =
		0 != (window.styleMask & NSWindowStyleMaskFullSizeContentView);

	//	if the window is in fullsize content mode then the animation to
	//	go fullscreen will not occur so first get out of fullsize content
	//	mode and then add NSWindowStyleMaskFullScreen to the styleMask
	if(_inFullSizeContentModeForNonFullScreenMode)
		[_fullSizeContentController toggleFullSizeContentWithAnimation:YES];
}

- (void)updateViewMenuItems_ {
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
	[self updateViewMenuItems_];
}

//	MARK: - <PGClipViewDelegate>

- (BOOL)clipView:(PGClipView *)sender handleMouseEvent:(NSEvent *)anEvent first:(BOOL)flag
{
	if(flag) return NO;
	BOOL const primary = anEvent.type == NSEventTypeLeftMouseDown;
	BOOL const rtl = self.activeDocument.readingDirection == PGReadingDirectionRightToLeft;
	BOOL forward;
	switch([[[NSUserDefaults standardUserDefaults] objectForKey:PGMouseClickActionKey] integerValue]) {
		case PGLeftRightAction: forward = primary == rtl; break;
		case PGRightLeftAction: forward = primary != rtl; break;
		default: forward = primary; break;
	}
	if(anEvent.modifierFlags & NSEventModifierFlagShift) forward = !forward;
	if(forward) [self nextPage:self];
	else [self previousPage:self];
	return YES;
}
- (BOOL)clipView:(PGClipView *)sender handleKeyDown:(NSEvent *)anEvent
{
	NSUInteger const modifiers = (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption) & anEvent.modifierFlags;
	unsigned short const keyCode = anEvent.keyCode;
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
	PGDocument *const d = self.activeDocument;
	if(!modifiers || NSEventModifierFlagOption == modifiers) switch(keyCode) {
		case PGKey0: [self setTimerRunning:NO]; return YES;
		case PGKey1: d.timerInterval = 1.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey2: d.timerInterval = 2.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey3: d.timerInterval = 3.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey4: d.timerInterval = 4.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey5: d.timerInterval = 5.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey6: d.timerInterval = 6.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey7: d.timerInterval = 7.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey8: d.timerInterval = 8.0f * timerFactor; [self setTimerRunning:YES]; return YES;
		case PGKey9: d.timerInterval = 9.0f * timerFactor; [self setTimerRunning:YES]; return YES;
	}
	return [self performKeyEquivalent:anEvent];
}
- (BOOL)clipView:(PGClipView *)sender shouldExitEdges:(PGRectEdgeMask)mask
{
	NSAssert(mask, @"At least one edge must be set.");
	NSAssert(!PGHasContradictoryRectEdges(mask), @"Contradictory edges aren't allowed.");
	BOOL const ltr = self.activeDocument.readingDirection == PGReadingDirectionLeftToRight;
	PGNode *const activeNode = self.activeNode;
	if(mask & (ltr ? PGMinXEdgeMask : PGMaxXEdgeMask)) [self previousPage:self];
	else if(mask & (ltr ? PGMaxXEdgeMask : PGMinXEdgeMask)) [self nextPage:self];
	return self.activeNode != activeNode;
}
- (PGRectEdgeMask)clipView:(PGClipView *)sender directionFor:(PGPageLocation)nodeLocation
{
	return PGReadingDirectionAndLocationToRectEdgeMask(nodeLocation, self.activeDocument.readingDirection);
}
- (void)clipView:(PGClipView *)sender magnifyBy:(CGFloat)amount
{
	[_imageView setUsesCaching:NO];
	[self.activeDocument setImageScaleFactor:MAX(PGScaleMin, MIN([_imageView averageScaleFactor] * (amount / 500.0f + 1.0f), PGScaleMax))];
}
- (void)clipView:(PGClipView *)sender rotateByDegrees:(CGFloat)amount
{
#if __has_feature(objc_arc)
	[_clipView scrollCenterTo:[_clipView convertPoint:[_imageView rotateByDegrees:amount adjustingPoint:[_imageView convertPoint:_clipView.center fromView:_clipView]] fromView:_imageView] animation:PGNoAnimation];
#else
	[clipView scrollCenterTo:[clipView convertPoint:[_imageView rotateByDegrees:amount adjustingPoint:[_imageView convertPoint:[clipView center] fromView:clipView]] fromView:_imageView] animation:PGNoAnimation];
#endif
}
- (void)clipViewGestureDidEnd:(PGClipView *)sender
{
	[_imageView setUsesCaching:YES];
	CGFloat const deg = _imageView.rotationInDegrees;
	_imageView.rotationInDegrees = 0.0f;
	PGOrientation o;
	switch((NSInteger)round((deg + 360.0f) / 90.0f) % 4) {
		case 0: o = PGUpright; break;
		case 1: o = PGRotated90CCW; break;
		case 2: o = PGUpsideDown; break;
		case 3: o = PGRotated90CW; break;
		default: PGAssertNotReached(@"Rotation wasn't simplified into an orientation.");
	}
	self.activeDocument.baseOrientation = PGAddOrientation(self.activeDocument.baseOrientation, o);
}

@end
