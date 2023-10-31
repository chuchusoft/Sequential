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
#import "PGDocumentController.h"
#import <Carbon/Carbon.h>
#import <sys/resource.h>
#import <objc/Protocol.h>
#import <tgmath.h>

// Models
#import "PGDocument.h"
#import "PGResourceAdapter.h"
#import "PGContainerAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGBookmark.h"

// Views
#import "PGOrientationMenuItemCell.h"

// Controllers
#import "PGAboutBoxController.h"
#import "PGPreferenceWindowController.h"
#import "PGDisplayController.h"
#import "PGWindowController.h"
#import "PGFullscreenController.h"
#import "PGInspectorPanelController.h"
#import "PGTimerPanelController.h"
#import "PGActivityPanelController.h"
#import "PGURLAlert.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGDelayedPerforming.h"
#import "PGFoundationAdditions.h"
#import "PGKeyboardLayout.h"
//#import "PGLegacy.h"
#import "PGLocalizing.h"
#import "PGZooming.h"

//	general prefs pane
NSString *const PGAntialiasWhenUpscalingKey = @"PGAntialiasWhenUpscaling";
NSString *const PGBackgroundColorSourceKey = @"PGBackgroundColorSource";	//	2023/08/17
NSString *const PGBackgroundColorKey = @"PGBackgroundColor";
NSString *const PGBackgroundPatternKey = @"PGBackgroundPattern";
NSString *const PGBackgroundColorUsedInFullScreenKey = @"PGBackgroundColorUsedInFullScreen";	//	2023/08/14
NSString *const PGEscapeKeyMappingKey = @"PGEscapeKeyMapping";
NSString *const PGDimOtherScreensKey = @"PGDimOtherScreens";
NSString *const PGImageScaleConstraintKey = @"PGImageScaleConstraint";

//	thumbnail prefs pane
NSString *const PGShowThumbnailImageNameKey = @"PGShowThumbnailImageName";	//	2023/10/01 added
NSString *const PGShowThumbnailImageSizeKey = @"PGShowThumbnailImageSize";	//	2023/10/01 added
NSString *const PGShowThumbnailContainerNameKey = @"PGShowThumbnailContainerName";	//	2023/10/01 added
NSString *const PGShowThumbnailContainerChildCountKey = @"PGShowThumbnailContainerChildCount";	//	2023/10/01 added
NSString *const PGShowThumbnailContainerChildSizeTotalKey = @"PGShowThumbnailContainerChildSizeTotal";	//	2023/10/01 added
NSString *const PGThumbnailSizeFormatKey = @"PGThumbnailSizeFormat";	//	2023/10/01 added

NSString *const deprecated_PGShowFileNameOnImageThumbnailKey = @"PGShowFileNameOnImageThumbnail";	//	2023/10/01 deprecated/removed
static NSString* const deprecated_PGShowCountsAndSizesOnContainerThumbnailKey = @"PGShowCountsAndSizesOnContainerThumbnail";	//	2023/09/11 deprecated/removed
//NSString *const PGThumbnailContainerLabelTypeKey = @"PGThumbnailContainerLabelType";	//	2023/09/11

//	navigation prefs pane
NSString *const PGMouseClickActionKey = @"PGMouseClickAction";
NSString *const PGBackwardsInitialLocationKey = @"PGBackwardsInitialLocation";

//	TODO: work out if these can be removed
static NSString *const PGRecentItemsKey = @"PGRecentItems2";
static NSString *const PGRecentItemsDeprecated2Key = @"PGRecentItems"; // Deprecated after 1.3.2
static NSString *const PGRecentItemsDeprecatedKey = @"PGRecentDocuments"; // Deprecated after 1.2.2.
static NSString *const PGFullscreenKey = @"PGFullscreen";

static NSString *const PGPathFinderBundleID = @"<Path Finder Bundle ID>";	//	TODO
//static NSString *const PGPathFinderApplicationName = @"Path Finder";

static PGDocumentController *PGSharedDocumentController = nil;

@interface PGDocumentController(Private)

- (void)_awakeAfterLocalizing;
- (void)_setFullscreen:(BOOL)flag;
- (PGDocument *)_openNew:(BOOL)flag document:(PGDocument *)document display:(BOOL)display;
- (void)_setRecentDocumentIdentifiers:(NSArray<PGDisplayableIdentifier*> *)anArray;
- (void)_changeRecentDocumentIdentifiersWithDocument:(PGDocument *)document prepend:(BOOL)prepend;

@end

#pragma mark -
@implementation PGDocumentController

#pragma mark +PGDocumentController

+ (PGDocumentController *)sharedDocumentController
{
	return PGSharedDocumentController ? PGSharedDocumentController : [[[self alloc] init] autorelease];
}

#pragma mark +NSObject

+ (void)initialize
{
	if([PGDocumentController class] != self)
		return;
//	NSNumber *const yes = [NSNumber numberWithBool:YES], *no = [NSNumber numberWithBool:NO];
	NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
	NSError *error = nil;
	NSData *archivedBlackColor = [NSKeyedArchiver
									archivedDataWithRootObject:NSColor.blackColor
									requiringSecureCoding:YES error:&error];
	[d registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		@YES /* yes */, PGAntialiasWhenUpscalingKey,
		archivedBlackColor, PGBackgroundColorKey,
		[NSNumber numberWithUnsignedInteger:PGNoPattern], PGBackgroundPatternKey,	//	misnomer; should be PGBackgroundPatternTypeKey
		[NSNumber numberWithInteger:PGNextPreviousAction], PGMouseClickActionKey,
		[NSNumber numberWithUnsignedInteger:1], PGMaxDepthKey,
		@NO, PGFullscreenKey,
		[NSNumber numberWithInteger:PGFullscreenMapping], PGEscapeKeyMappingKey,
		@NO, PGDimOtherScreensKey,
		[NSNumber numberWithInteger:PGEndLocation], PGBackwardsInitialLocationKey,
		[NSNumber numberWithUnsignedInteger:PGScaleFreely], PGImageScaleConstraintKey,

		@NO, PGShowThumbnailImageNameKey,
		@NO, PGShowThumbnailImageSizeKey,

		@YES, PGShowThumbnailContainerNameKey,
		@NO, PGShowThumbnailContainerChildCountKey,
		@NO, PGShowThumbnailContainerChildSizeTotalKey,

		[NSNumber numberWithUnsignedInteger:0], PGThumbnailSizeFormatKey,
		nil]];

	//	2023/10/01 transition value of the old PGShowFileNameOnImageThumbnail
	//	default to the new PGShowThumbnailImageName default
	id o = [d objectForKey:deprecated_PGShowFileNameOnImageThumbnailKey];
	if(o) {
		[d setBool:[o boolValue] forKey:PGShowThumbnailImageNameKey];
	}

	//	2023/09/11 transition value of the old PGShowCountsAndSizesOnContainerThumbnail
	//	default to the new PGThumbnailContainerLabelType default
	o = [d objectForKey:deprecated_PGShowCountsAndSizesOnContainerThumbnailKey];
	if(o) {
		BOOL b = [o boolValue];
		[d setBool:b forKey:PGShowThumbnailContainerChildCountKey];
		[d setBool:b forKey:PGShowThumbnailContainerChildSizeTotalKey];
		[d removeObjectForKey:deprecated_PGShowCountsAndSizesOnContainerThumbnailKey];
	}
}

#pragma mark -PGDocumentController

- (IBAction)orderFrontStandardAboutPanel:(id)sender
{
	[[PGAboutBoxController sharedAboutBoxController] showWindow:self];
}
- (IBAction)showPreferences:(id)sender
{
	[[PGPreferenceWindowController sharedPrefController] showWindow:self];
}
- (IBAction)switchToFileManager:(id)sender
{
	if(![[[[NSAppleScript alloc] initWithSource:self.pathFinderRunning ? @"tell application \"Path Finder\" to activate" : @"tell application \"Finder\" to activate"] autorelease] executeAndReturnError:NULL]) NSBeep();
}

#pragma mark -

- (IBAction)open:(id)sender
{
	[NSApp activateIgnoringOtherApps:YES];
	NSOpenPanel *const openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowsMultipleSelection:YES];
	NSURL *const URL = [[[self currentDocument] rootIdentifier] URL];
#if 1
	if(URL.isFileURL)
		openPanel.directoryURL		=	URL.URLByDeletingLastPathComponent;
	openPanel.allowedFileTypes	=	[PGResourceAdapter supportedFileTypes];
	NSModalResponse	response	=	[openPanel runModal];
#else
	NSString *const path = [URL isFileURL] ? [URL path] : nil;
	NSInteger	response	=	[openPanel runModalForDirectory:[path stringByDeletingLastPathComponent] file:[path lastPathComponent] types:[PGResourceAdapter supportedFileTypes]];
#endif
	if(response == NSModalResponseOK) {
		PGDocument *const oldDoc = [self currentDocument];
	//	[self application:NSApp openFiles:[openPanel filenames]];
		[self application:NSApp openURLs:openPanel.URLs];

		if((openPanel.currentEvent.modifierFlags & NSEventModifierFlagOption) && self.currentDocument != oldDoc)
			[oldDoc close];
	}
}
- (IBAction)openURL:(id)sender
{
	[NSApp activateIgnoringOtherApps:YES];
	NSURL *const URL = [(PGURLAlert *)[[[PGURLAlert alloc] init] autorelease] runModal];
	if(URL) [self openDocumentWithContentsOfURL:URL display:YES];
}
- (IBAction)openRecentDocument:(id)sender
{
	[self openDocumentWithContentsOfIdentifier:[(NSMenuItem *)sender representedObject] display:YES];
}
- (IBAction)clearRecentDocuments:(id)sender
{
	[self setRecentDocumentIdentifiers:[NSArray<PGDisplayableIdentifier*> array]];
}
- (IBAction)closeAll:(id)sender
{
	[[_fullscreenController window] close];
	for(PGDocument *const doc in [self documents]) [[[doc displayController] window] performClose:self];
}

#pragma mark -

- (IBAction)toggleInspector:(id)sender
{
	[_inspectorPanel toggleShown];
}
- (IBAction)toggleTimer:(id)sender
{
	[_timerPanel toggleShown];
}
- (IBAction)toggleActivity:(id)sender
{
	[_activityPanel toggleShown];
}
- (IBAction)selectPreviousDocument:(id)sender
{
	PGDocument *const doc = [self next:NO documentBeyond:[self currentDocument]];
	[[doc displayController] activateDocument:doc];
}
- (IBAction)selectNextDocument:(id)sender
{
	PGDocument *const doc = [self next:YES documentBeyond:[self currentDocument]];
	[[doc displayController] activateDocument:doc];
}
- (IBAction)activateDocument:(id)sender
{
	PGDocument *const doc = [(NSMenuItem *)sender representedObject];
	[[doc displayController] activateDocument:doc];
}

#pragma mark -

- (IBAction)showKeyboardShortcuts:(id)sender
{
	[[NSHelpManager sharedHelpManager] openHelpAnchor:@"shortcuts" inBook:[[NSBundle mainBundle] objectForInfoDictionaryKey:PGCFBundleHelpBookNameKey]];
}

#pragma mark -

- (BOOL)performEscapeKeyAction
{
	switch([[[NSUserDefaults standardUserDefaults] objectForKey:PGEscapeKeyMappingKey] integerValue]) {
		case PGFullscreenMapping: return [self performToggleFullscreen];
		case PGQuitMapping: [NSApp terminate:self]; return YES;
	}
	return NO;
}
- (BOOL)performZoomIn
{
	return [zoomIn PG_performAction];
}
- (BOOL)performZoomOut
{
	return [zoomOut PG_performAction];
}
- (BOOL)performToggleFullscreen
{
	return [toggleFullscreen PG_performAction];
}

#pragma mark -

- (NSArray<PGDisplayableIdentifier*> *)recentDocumentIdentifiers
{
	//	bugfix: never return a nil value
	if(!_recentDocumentIdentifiers)
		_recentDocumentIdentifiers	=	[NSArray<PGDisplayableIdentifier*> new];

	return [[_recentDocumentIdentifiers retain] autorelease];
}
- (void)setRecentDocumentIdentifiers:(NSArray<PGDisplayableIdentifier*> *)anArray
{
	[self _setRecentDocumentIdentifiers:anArray];
	[self recentDocumentIdentifierDidChange:nil];
}
- (NSUInteger)maximumRecentDocumentCount
{
	return [[[[NSDocumentController alloc] init] autorelease] maximumRecentDocumentCount]; // This is ugly but we don't want to use NSDocumentController.
}
- (PGDisplayController *)displayControllerForNewDocument
{
	if(self.fullscreen) {
		if(!_fullscreenController)
			_fullscreenController = [[PGFullscreenController alloc] init];
		return _fullscreenController;
	}
	return [[[PGWindowController alloc] init] autorelease];
}

@synthesize fullscreen = _fullscreen;
- (void)setFullscreen:(BOOL)flag
{
	if(flag == _fullscreen) return;
	_fullscreen = flag;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:flag] forKey:PGFullscreenKey];
	[self _setFullscreen:flag];
}

- (BOOL)canToggleFullscreen
{
	if(_fullscreen) return YES;
	for(PGDocument *const doc in [self documents]) if([[[doc displayController] window] attachedSheet]) return NO;
	return YES;
}

extern	const NSString* const	PGUseEntireScreenWhenInFullScreenKey;
		const NSString* const	PGUseEntireScreenWhenInFullScreenKey	=	@"PGUseEntireScreenWhenInFullScreen";

- (BOOL) usesEntireScreenWhenInFullScreen
{
	return [NSUserDefaults.standardUserDefaults
			boolForKey:(NSString*)PGUseEntireScreenWhenInFullScreenKey];
}

- (void)setUsesEntireScreenWhenInFullScreen:(BOOL)flag	//	2023/08/14 added
{
	NSParameterAssert(_fullscreen);
	NSParameterAssert(_fullscreenController);

	[NSUserDefaults.standardUserDefaults setBool:flag
										  forKey:(NSString*)PGUseEntireScreenWhenInFullScreenKey];

	[_fullscreenController resizeToUseEntireScreen];
}

- (BOOL)canToggleUsesEntireScreenWhenInFullScreen	//	2023/08/14
{
	return _fullscreen;
}

@synthesize documents = _documents;
- (NSMenu *)scaleMenu
{
	return [scaleSliderItem menu];
}
- (NSSlider *)scaleSlider
{
	return scaleSlider;
}
@synthesize defaultPageMenu;
@synthesize currentDocument = _currentDocument;
- (void)setCurrentDocument:(PGDocument *)document
{
	_currentDocument = document;
	NSMenu *const menu = [_currentDocument pageMenu];
	[pageMenuItem setSubmenu:menu ? menu : [self defaultPageMenu]];
}
- (BOOL)pathFinderRunning
{
#if 1
	for(NSRunningApplication *const oneApp in [[NSWorkspace sharedWorkspace] runningApplications])
		if([oneApp.bundleIdentifier isEqual:PGPathFinderBundleID])
			return YES;
#else
	for(NSDictionary *const dict in [[NSWorkspace sharedWorkspace] launchedApplications])
		if(PGEqualObjects([dict objectForKey:@"NSApplicationName"], PGPathFinderApplicationName))
			return YES;
#endif
	return NO;
}

#pragma mark -

- (void)addDocument:(PGDocument *)document
{
	NSParameterAssert([_documents indexOfObjectIdenticalTo:document] == NSNotFound);
	if(![_documents count]) [windowsMenu addItem:windowsMenuSeparator];
	[_documents addObject:document];
	NSMenuItem *const item = [[[NSMenuItem alloc] init] autorelease];
	[item setRepresentedObject:document];
	[item setAction:@selector(activateDocument:)];
	[item setTarget:self];
	[windowsMenu addItem:item];
	[self _setFullscreen:YES];
}
- (void)removeDocument:(PGDocument *)document
{
	NSParameterAssert(!document || [_documents indexOfObjectIdenticalTo:document] != NSNotFound);
	if(document == [self currentDocument]) [self setCurrentDocument:nil];
	if(!document) return;
	[_documents removeObject:document];
	NSUInteger const i = [windowsMenu indexOfItemWithRepresentedObject:document];
	if(NSNotFound != i) [windowsMenu removeItemAtIndex:i];
	if(![_documents count]) [windowsMenuSeparator PG_removeFromMenu];
	[self _setFullscreen:[_documents count] > 0];
}
- (PGDocument *)documentForIdentifier:(PGResourceIdentifier *)ident
{
	for(PGDocument *const doc in _documents) if(PGEqualObjects([doc rootIdentifier], ident)) return doc;
	return nil;
}
- (PGDocument *)next:(BOOL)flag documentBeyond:(PGDocument *)document
{
	NSArray *const docs = [[PGDocumentController sharedDocumentController] documents];
	NSUInteger const count = [docs count];
	if(count <= 1) return nil;
	NSUInteger i = [docs indexOfObjectIdenticalTo:[self currentDocument]];
	if(NSNotFound == i) return nil;
	if(flag) {
		if([docs count] == ++i) i = 0;
	} else if(0 == i--) i = [docs count] - 1;
	return [docs objectAtIndex:i];
}
- (NSMenuItem *)windowsMenuItemForDocument:(PGDocument *)document
{
	NSInteger const i = [windowsMenu indexOfItemWithRepresentedObject:document];
	return -1 == i ? nil : [windowsMenu itemAtIndex:i];
}

#pragma mark -

- (id)openDocumentWithContentsOfIdentifier:(PGResourceIdentifier *)ident display:(BOOL)flag
{
	if(!ident) return nil;
	PGDocument *const doc = [self documentForIdentifier:ident];
	return [self _openNew:!doc document:doc ? doc : [[(PGDocument *)[PGDocument alloc] initWithIdentifier:[ident displayableIdentifier]] autorelease] display:flag];
}
- (id)openDocumentWithContentsOfURL:(NSURL *)URL display:(BOOL)flag
{
	return [self openDocumentWithContentsOfIdentifier:[URL PG_resourceIdentifier] display:flag];
}
- (id)openDocumentWithBookmark:(PGBookmark *)aBookmark display:(BOOL)flag
{
	PGDocument *const doc = [self documentForIdentifier:[aBookmark documentIdentifier]];
	[doc openBookmark:aBookmark];
	return [self _openNew:!doc document:doc ? doc : [[[PGDocument alloc] initWithBookmark:aBookmark] autorelease] display:flag];
}
- (void)noteNewRecentDocument:(PGDocument *)document
{
	[self _changeRecentDocumentIdentifiersWithDocument:document prepend:YES];
}
- (void)noteDeletedRecentDocument:(PGDocument *)document
{
	[self _changeRecentDocumentIdentifiersWithDocument:document prepend:NO];
}

#pragma mark -

- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	if([event eventClass] == kInternetEventClass && [event eventID] == kAEGetURL) [self openDocumentWithContentsOfURL:[NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]] display:YES];
}

#pragma mark -

- (void)recentDocumentIdentifierDidChange:(NSNotification *)aNotif
{
//	[[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:_recentDocumentIdentifiers] forKey:PGRecentItemsKey];
	NSError* error = nil;
	NSData* archivedData = [NSKeyedArchiver archivedDataWithRootObject:_recentDocumentIdentifiers requiringSecureCoding:YES error:&error];
	if(error)
		return;

	[[NSUserDefaults standardUserDefaults] setObject:archivedData forKey:PGRecentItemsKey];
}

#pragma mark -PGDocumentController(Private)

- (void)_awakeAfterLocalizing
{
	for(NSMenuItem *const item in [orientationMenu itemArray]) [PGOrientationMenuIconCell addOrientationMenuIconCellToMenuItem:item];
}
- (void)_setFullscreen:(BOOL)flag
{
	if(flag == _inFullscreen) return;
//	NSDisableScreenUpdates();	2021/07/21 deprecated

	//	2023/10/14 there is a known issue when entering or leaving fullscreen mode:
	//	if document A has multiple items selected and document B has multiple items
	//	selected then entering/exiting fullscreen will preserve the selection of
	//	whichever document is the active/frontmost document when the transition
	//	occurs, but the selection of the other document(s) will be lost and only the
	//	active node of the other documents ends up selected.

/*	//	The solution is probably to use a dictionary of sets where the key is the
	//	PGDocument instance and the value is the NSSet of that document's selection.

	//	Unfortunately, this idea does not work: it causes the wrong nodes to be
	//	selected in the wrong doc. Here's the code which doesn't work.

	NSArray<__kindof NSDocument *> *const docs = [self documents];
	CFMutableDictionaryRef selections = CFDictionaryCreateMutable(
						kCFAllocatorDefault, docs.count, NULL, NULL);
	for(PGDocument *const doc in docs) {
		NSSet *const selectedNodes = doc.displayController.selectedNodes;
		if(selectedNodes)
			CFDictionaryAddValue(selections, doc, [[selectedNodes retain] autorelease]);
	}

	if(!flag) {
		_inFullscreen = flag;

		NSAssert(_fullscreenController, @"_fullscreenController");
		[_fullscreenController prepareToExitFullscreen];

		NSMutableArray *const mutDocs = [[docs mutableCopy] autorelease];
		PGDocument *const currentDoc = [_fullscreenController activeDocument];
		if(currentDoc) {
			[mutDocs removeObjectIdenticalTo:currentDoc];
			[mutDocs addObject:currentDoc];
		}
		for(PGDocument *const doc in mutDocs) {
			PGDisplayController *const dc = [self displayControllerForNewDocument];
			[doc setDisplayController:dc];
			[dc showWindow:self];

			//	2023/10/02 sets the selection in the new controller,
			//	ie, restores selection
			NSSet *selectedNodes = CFDictionaryGetValue(selections, doc);
			if(selectedNodes && currentDoc == doc)
				dc.selectedNodes = selectedNodes;
		}

		[[_fullscreenController window] close];
		[_fullscreenController release];
		_fullscreenController = nil;
	} else if([docs count] && self.fullscreen) {
		_inFullscreen = flag;
		PGDocument *const currentDoc = [self currentDocument];
		_fullscreenController = [[PGFullscreenController alloc] init];
		for(PGDocument *const doc in docs) {
			PGDisplayController *const oldController = [doc displayController];
			if(!oldController) continue;

			[doc setDisplayController:_fullscreenController];
			[[oldController window] close];
		}
		[_fullscreenController setActiveDocument:currentDoc closeIfAppropriate:NO];
		[_fullscreenController showWindow:self];

		//	2023/10/02 sets the selection in the new controller, ie,
		//	restores selection
		for(PGDocument *const doc in docs) {
			NSSet *selectedNodes = CFDictionaryGetValue(selections, doc);
			if(!selectedNodes)
				continue;

			if(doc == currentDoc) {
				NSAssert(doc.displayController == _fullscreenController, @"dc");
				_fullscreenController.selectedNodes = selectedNodes;
			} else
				doc.displayController.selectedNodes = selectedNodes;
		}
	}
	CFRelease(selections);
 */

	NSArray<__kindof NSDocument *> *const docs = [self documents];
	NSSet *selectedNodes = nil;	//	2023/10/02

	if(!flag) {
		_inFullscreen = flag;

		NSAssert(_fullscreenController, @"_fullscreenController");
		[_fullscreenController prepareToExitFullscreen];
		selectedNodes = _fullscreenController.selectedNodes;

		NSMutableArray *const mutDocs = [[docs mutableCopy] autorelease];
		PGDocument *const currentDoc = [_fullscreenController activeDocument];
		if(currentDoc) {
			[mutDocs removeObjectIdenticalTo:currentDoc];
			[mutDocs addObject:currentDoc];
		}
		for(PGDocument *const doc in mutDocs) {
			PGDisplayController *const dc = [self displayControllerForNewDocument];
			[doc setDisplayController:dc];
			[dc showWindow:self];

			//	2023/10/02 sets the selection in the new controller,
			//	ie, restores selection
			if(selectedNodes && currentDoc == doc)
				dc.selectedNodes = selectedNodes;
		}
		[[_fullscreenController window] close];
		[_fullscreenController release];
		_fullscreenController = nil;
	} else if([docs count] && self.fullscreen) {
		_inFullscreen = flag;
		PGDocument *const currentDoc = [self currentDocument];
		_fullscreenController = [[PGFullscreenController alloc] init];
		for(PGDocument *const doc in docs) {
			PGDisplayController *const oldController = [doc displayController];
			if(!oldController) continue;

			//	2023/10/02 get the selected nodes from the (old) thumbnail
			//	browser before it is lost
			if(nil == selectedNodes && currentDoc == doc)
				selectedNodes = [[oldController.selectedNodes retain] autorelease];

			[doc setDisplayController:_fullscreenController];
			[[oldController window] close];
		}
		[_fullscreenController setActiveDocument:currentDoc closeIfAppropriate:NO];
		[_fullscreenController showWindow:self];

		//	2023/10/02 sets the selection in the new controller, ie,
		//	restores selection
		if(selectedNodes)
			_fullscreenController.selectedNodes = selectedNodes;
	}
//	NSEnableScreenUpdates();	2021/07/21 deprecated
}

- (PGDocument *)_openNew:(BOOL)flag document:(PGDocument *)document display:(BOOL)display
{
	if(!document) return nil;
	if(flag) [self addDocument:document];
	if(display) [document createUI];
	return document;
}

- (void)_setRecentDocumentIdentifiers:(NSArray<PGDisplayableIdentifier*> *)anArray {
//NSLog(@"-[PGDocumentController _setRecentDocumentIdentifiers:] self = %p", self);
	NSParameterAssert(anArray);
	if(PGEqualObjects(anArray, _recentDocumentIdentifiers)) return;
	[_recentDocumentIdentifiers PG_removeObjectObserver:self name:PGDisplayableIdentifierIconDidChangeNotification];
	[_recentDocumentIdentifiers PG_removeObjectObserver:self name:PGDisplayableIdentifierDisplayNameDidChangeNotification];
	[_recentDocumentIdentifiers release];
	_recentDocumentIdentifiers = [[anArray subarrayWithRange:NSMakeRange(0, MIN([anArray count], [self maximumRecentDocumentCount]))] copy];
	[_recentDocumentIdentifiers PG_addObjectObserver:self selector:@selector(recentDocumentIdentifierDidChange:) name:PGDisplayableIdentifierIconDidChangeNotification];
	[_recentDocumentIdentifiers PG_addObjectObserver:self selector:@selector(recentDocumentIdentifierDidChange:) name:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}
- (void)_changeRecentDocumentIdentifiersWithDocument:(PGDocument *)document prepend:(BOOL)prepend {
	PGDisplayableIdentifier *const identifier = [document rootIdentifier];
	if(!identifier)
		return;
	NSArray<PGDisplayableIdentifier*> *const recentDocumentIdentifiers = [self recentDocumentIdentifiers];
	//	if the recent document list will not change then exit
	if(prepend && [recentDocumentIdentifiers count] > 0 &&
		identifier == [recentDocumentIdentifiers objectAtIndex:0]) {
		return;
	}
	NSMutableArray<PGDisplayableIdentifier*> *const identifiers = [[recentDocumentIdentifiers mutableCopy] autorelease];
	[identifiers removeObject:identifier];
	if(prepend)
		[identifiers insertObject:identifier atIndex:0];
	[self setRecentDocumentIdentifiers:identifiers];
}

#pragma mark -NSResponder

- (BOOL)performKeyEquivalent:(NSEvent *)anEvent
{
	if(!([anEvent modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption)))
		switch([anEvent keyCode]) {
		case PGKeyEscape: [self performEscapeKeyAction]; break;
		case PGKeyQ: [NSApp terminate:self]; return YES;
		}

	return NO;
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		NSUserDefaults *const defaults = [NSUserDefaults standardUserDefaults];
		id recentItemsData = [defaults objectForKey:PGRecentItemsKey];
		if(!recentItemsData) {
			recentItemsData = [defaults objectForKey:PGRecentItemsDeprecated2Key];
			[defaults removeObjectForKey:PGRecentItemsDeprecated2Key]; // Don't leave unused data around.
		}
		if(!recentItemsData) {
			recentItemsData = [defaults objectForKey:PGRecentItemsDeprecatedKey];
			[defaults removeObjectForKey:PGRecentItemsDeprecatedKey]; // Don't leave unused data around.
		}
#if 1
		NSArray*	rdia = nil;
		if(recentItemsData) {
			NSError* error = nil;
			NSSet* classes = [NSSet setWithArray:@[NSArray.class, NSData.class, PGResourceIdentifier.class]];
			rdia	=	[NSKeyedUnarchiver unarchivedObjectOfClasses:classes
															fromData:recentItemsData
															   error:&error];
		} else
			rdia	=	[NSArray array];
		if(rdia)
			//	calling -setRecentDocumentIdentifiers: will pointlessly write the list
			//	back out so avoid doing that by using a private setter
			[self _setRecentDocumentIdentifiers:rdia];
#else
		[self setRecentDocumentIdentifiers:recentItemsData ?
		 [NSKeyedUnarchiver unarchiveObjectWithData:recentItemsData] : [NSArray array]];
#endif
		_fullscreen = [[defaults objectForKey:PGFullscreenKey] boolValue];

		_documents = [[NSMutableArray<__kindof PGDocument*> alloc] init];
	//	_classesByExtension = [[NSMutableDictionary alloc] init];	2023/10/29 not used; removed

		_inspectorPanel = [[PGInspectorPanelController alloc] init];
		_timerPanel = [[PGTimerPanelController alloc] init];
		_activityPanel = [[PGActivityPanelController alloc] init];

		if(!PGSharedDocumentController) {
			PGSharedDocumentController = [self retain];
			[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleAppleEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
			[self setNextResponder:[NSApp nextResponder]];
			[NSApp setNextResponder:self];
		}
	}
	return self;
}
- (void)dealloc
{
	if(PGSharedDocumentController == self) [[NSAppleEventManager sharedAppleEventManager] removeEventHandlerForEventClass:kInternetEventClass andEventID:kAEGetURL];
	[self PG_removeObserver];
	[defaultPageMenu release];
	[windowsMenuSeparator release];
	[_recentDocumentIdentifiers release];
	[_documents release];
	[_fullscreenController release];
	[_inspectorPanel release];
	[_timerPanel release];
	[_activityPanel release];
//	[_classesByExtension release];	2023/10/29 not used; removed
	[super dealloc];
}

#pragma mark -NSObject(NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = [anItem action];

	// Sequential:
	if(@selector(switchToFileManager:) == action) [anItem setTitle:NSLocalizedString((self.pathFinderRunning ? @"Switch to Path Finder" : @"Switch to Finder"), @"Switch to Finder or Path Finder (www.cocoatech.com). Two states of the same item.")];

	// Window:
	if(@selector(activateDocument:) == action) [anItem setState:[anItem representedObject] == [self currentDocument]];

	if([[self documents] count] <= 1) {
		if(@selector(selectPreviousDocument:) == action) return NO;
		if(@selector(selectNextDocument:) == action) return NO;
	}
	if(![[self recentDocumentIdentifiers] count]) {
		if(@selector(clearRecentDocuments:) == action) return NO;
	}
	return [super validateMenuItem:anItem];
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	[defaultPageMenu retain];
	[windowsMenuSeparator retain];
	[windowsMenuSeparator PG_removeFromMenu];
	[zoomIn setKeyEquivalent:@"+"];
	[zoomIn setKeyEquivalentModifierMask:0];
	[zoomOut setKeyEquivalent:@"-"];
	[zoomOut setKeyEquivalentModifierMask:0];

	[scaleSliderItem setView:[scaleSlider superview]];
	[scaleSlider setMinValue:log2(PGScaleMin)];
	[scaleSlider setMaxValue:log2(PGScaleMax)];

	[selectPreviousDocument setKeyEquivalent:[NSString stringWithFormat:@"%C", (unichar)0x21E1]];
	[selectPreviousDocument setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
	[selectNextDocument setKeyEquivalent:[NSString stringWithFormat:@"%C", (unichar)0x21E3]];
	[selectNextDocument setKeyEquivalentModifierMask:NSEventModifierFlagCommand];

	[self _setFullscreen:_fullscreen];
	[self setCurrentDocument:nil];

	[self performSelector:@selector(_awakeAfterLocalizing) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
}

#pragma mark -<NSApplicationDelegate>

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
	return !![self openDocumentWithContentsOfURL:[filename PG_fileURL] display:YES];
}
- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
	for(NSString *const filename in filenames) [self openDocumentWithContentsOfURL:[filename PG_fileURL] display:YES];
	[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}
- (void)application:(NSApplication *)sender openURLs:(NSArray<NSURL*>*)URLs
{
//[self application:NSApp openURLs:openPanel.URLs];
	for(NSURL* const url in URLs)
		[self openDocumentWithContentsOfURL:url display:YES];
	[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

#pragma mark -<NSMenuDelegate>

- (void)menuNeedsUpdate:(NSMenu *)recentDocumentsMenu
{
	[recentDocumentsMenu PG_removeAllItems];
	BOOL addedAnyItems = NO;	//	could be replaced by testing "if(0 != [recentDocumentsMenu numberOfItems])" instead of "if(addedAnyItems)"
	NSArray<PGDisplayableIdentifier*> *const identifiers = [self recentDocumentIdentifiers];
	for(PGDisplayableIdentifier *const identifier in identifiers) {
		if(![identifier URL])
			continue; // Make sure the URLs are valid.
		BOOL uniqueName = YES;
		NSString *const name = [identifier displayName];
		for(PGDisplayableIdentifier *const comparisonIdentifier in identifiers) {
			if(comparisonIdentifier == identifier || !PGEqualObjects([comparisonIdentifier displayName], name)) continue;
			uniqueName = NO;
			break;
		}
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:@"" action:@selector(openRecentDocument:) keyEquivalent:@""] autorelease];
		[item setAttributedTitle:[identifier attributedStringWithAncestory:!uniqueName]];
		[item setRepresentedObject:identifier];
		[recentDocumentsMenu addItem:item];
		addedAnyItems = YES;
	}
	if(addedAnyItems) [recentDocumentsMenu addItem:[NSMenuItem separatorItem]];
	[recentDocumentsMenu addItem:[[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Clear Menu", @"Clear the Open Recent menu. Should be the same as the standard text.") action:@selector(clearRecentDocuments:) keyEquivalent:@""] autorelease]];
}

@end

@interface PGApplication : NSApplication {
@private
	//	<https://lapcatsoftware.com/articles/Preferences2.html>
//	IBOutlet NSMenuItem *_preferencesMenuItem;
//	NSString *_originalPreferencesTitle;
}
@end
@interface PGWindow : NSWindow
@end
@interface PGView : NSView
@end
@interface PGMenu : NSMenu
@end
@interface PGMenuItem : NSMenuItem
@end
//@interface PGButton : NSButton
//@end

static BOOL (*PGNSWindowValidateMenuItem)(id, SEL, NSMenuItem *);
static BOOL (*PGNSMenuPerformKeyEquivalent)(id, SEL, NSEvent *);
static void (*PGNSMenuItemSetEnabled)(id, SEL, BOOL);
//static BOOL (*PGNSButtonPerformKeyEquivalent)(id, SEL, NSEvent *);

@implementation PGApplication

+ (void)initialize
{
	if([PGApplication class] != self) return;

	PGNSWindowValidateMenuItem = [NSWindow PG_useInstance:YES implementationFromClass:[PGWindow class] forSelector:@selector(validateMenuItem:)];
	PGNSMenuPerformKeyEquivalent = [NSMenu PG_useInstance:YES implementationFromClass:[PGMenu class] forSelector:@selector(performKeyEquivalent:)];
	PGNSMenuItemSetEnabled = [NSMenuItem PG_useInstance:YES implementationFromClass:[PGMenuItem class] forSelector:@selector(setEnabled:)];
//	PGNSButtonPerformKeyEquivalent = [NSButton PG_useInstance:YES
//									  implementationFromClass:[PGButton class]
//												  forSelector:@selector(performKeyEquivalent:)];

	struct rlimit const lim = {RLIM_INFINITY, RLIM_INFINITY};
	(void)setrlimit(RLIMIT_NOFILE, &lim); // We use a lot of file descriptors.

	[NSBundle PG_prepareToAutoLocalize];
}
- (void)sendEvent:(NSEvent *)anEvent
{
	if([anEvent window] || [anEvent type] != NSEventTypeKeyDown || !([[self mainMenu] performKeyEquivalent:anEvent] || [[PGDocumentController sharedDocumentController] performKeyEquivalent:anEvent])) [super sendEvent:anEvent];
}
- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	//	<https://lapcatsoftware.com/articles/Preferences2.html>
//	if(!_preferencesMenuItem || _originalPreferencesTitle)
//		return;
//	_originalPreferencesTitle = [[_preferencesMenuItem title] retain];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	//	<https://lapcatsoftware.com/articles/Preferences2.html>
//	if(!_originalPreferencesTitle || !_preferencesMenuItem)
//		return;
//	[_preferencesMenuItem setTitle:_originalPreferencesTitle];
//	[_originalPreferencesTitle release];
//	_originalPreferencesTitle = nil;
}

@end

@implementation PGWindow

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	if(@selector(PG_grow:) == [anItem action]) return [self styleMask] & NSWindowStyleMaskResizable && [[self standardWindowButton:NSWindowZoomButton] isEnabled];
	return PGNSWindowValidateMenuItem(self, _cmd, anItem);
}

@end

@implementation PGMenu

- (BOOL)performKeyEquivalent:(NSEvent *)anEvent
{
	if([anEvent type] != NSEventTypeKeyDown) return NO;
	NSInteger i;
	NSInteger const count = [self numberOfItems];
	for(i = 0; i < count; i++) {
		NSMenuItem *const item = [self itemAtIndex:i];
		NSString *const equiv = [item keyEquivalent];
		if([equiv length] != 1) continue;
		unsigned short const keyCode = PGKeyCodeFromUnichar([equiv characterAtIndex:0]);
		if(PGKeyUnknown == keyCode || [anEvent keyCode] != keyCode) continue; // Some non-English keyboard layouts switch to English when the Command key is held, but that doesn't help our shortcuts that don't use Command, so we have to check by key code.
		NSUInteger const modifiersMask = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption;
		if(([anEvent modifierFlags] & modifiersMask) != ([item keyEquivalentModifierMask] & modifiersMask)) continue;
		return [item PG_performAction];
	}
	for(i = 0; i < count; i++) if([[[self itemAtIndex:i] submenu] performKeyEquivalent:anEvent]) return YES;
	return [NSApp mainMenu] == self ? PGNSMenuPerformKeyEquivalent(self, _cmd, anEvent) : NO;
}

@end

@implementation PGMenuItem

- (void)setEnabled:(BOOL)flag
{
	PGNSMenuItemSetEnabled(self, _cmd, flag);
	[[self view] PG_setEnabled:flag recursive:YES];
}

@end

/* @implementation PGButton

#pragma mark -NSView

- (BOOL)performKeyEquivalent:(NSEvent *)anEvent
{
	if(PGNSButtonPerformKeyEquivalent(self, _cmd, anEvent)) return YES;
	if(![[NSArray arrayWithObjects:@"\r", @"\n", nil] containsObject:[self keyEquivalent]]) return NO;
	if(![[anEvent charactersIgnoringModifiers] isEqual:[self keyEquivalent]]) return NO;
	NSUInteger const sharedModifiers = [anEvent modifierFlags] & [self keyEquivalentModifierMask];
	if([self keyEquivalentModifierMask] == sharedModifiers) {
		[[self cell] performClick:self];
		return YES;
	}
	return NO;
}

@end */
