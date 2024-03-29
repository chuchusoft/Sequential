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
#import "PGFullscreenController.h"
#import <Carbon/Carbon.h>

// Views
#import "PGFullscreenWindow.h"

// Controllers
#import "PGDocumentController.h"
#import "PGPreferenceWindowController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGDelayedPerforming.h"
#import "PGFoundationAdditions.h"

// Models
#import "PGDocument.h"

#if __has_feature(objc_arc)

@interface PGFullscreenController ()

@property (nonatomic, assign) BOOL isExitingFullscreen;
@property (nonatomic, strong) NSMutableArray *shieldWindows;

- (void)_setMenuBarHidden:(BOOL)hidden delayed:(BOOL)delayed; // Delaying prevents the menu bar from messing up when the application unhides on Leopard.
- (void)_hideMenuBar;
- (void)_showMenuBar;

@end

#else

@interface PGFullscreenController(Private)

- (void)_setMenuBarHidden:(BOOL)hidden delayed:(BOOL)delayed; // Delaying prevents the menu bar from messing up when the application unhides on Leopard.
- (void)_hideMenuBar;
- (void)_showMenuBar;

@end

#endif

//	MARK: -
@implementation PGFullscreenController

//	MARK: +PGFullscreenController

+ (PGFullscreenController*)sharedFullscreenController
{
	static PGFullscreenController *sharedFullscreenController = nil;
	if(!sharedFullscreenController) sharedFullscreenController = [[self alloc] init];
	return sharedFullscreenController;
}

//	MARK: - PGFullscreenController

- (void)prepareToExitFullscreen
{
	_isExitingFullscreen = YES;
	[self _setMenuBarHidden:NO delayed:NO]; // For some reason, this moves windows downward slightly (at least on 10.5.3), so make sure it happens before our new windows get put onscreen.
}

- (void)displayScreenDidChange:(NSNotification *)aNotif
{
	NSScreen *const screen = [[PGPreferenceWindowController sharedPrefController] displayScreen];
	[(PGFullscreenWindow *)self.window moveToScreen:screen];
	if(!self.window.keyWindow) return;
	[self _setMenuBarHidden:[NSScreen PG_mainScreen] == screen delayed:YES];
}

- (void)resizeToUseEntireScreen	//	2023/08/14 added
{
	[(PGFullscreenWindow *)self.window resizeToUseEntireScreen];
}

//	MARK: - PGFullscreenController(Private)

- (void)_setMenuBarHidden:(BOOL)hidden delayed:(BOOL)delayed
{
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(_hideMenuBar) object:nil];
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(_showMenuBar) object:nil];
	if(delayed) [self PG_performSelector:hidden ? @selector(_hideMenuBar) : @selector(_showMenuBar) withObject:nil fireDate:nil interval:0.0f options:kNilOptions];
	else if(hidden) [self _hideMenuBar];
	else [self _showMenuBar];
}
- (void)_hideMenuBar
{
	//	There is no NSApplication option to hide the menu bar using animation
	//	while the Carbon version offers kUIOptionAnimateMenuBar. As a result,
	//	the original Carbon version is still used.
#ifndef __CARBON__
	NSApp.presentationOptions = NSApplicationPresentationAutoHideDock |
								NSApplicationPresentationAutoHideMenuBar;
#else
	SetSystemUIMode(kUIModeAllSuppressed, kUIOptionAnimateMenuBar);
#endif
}
- (void)_showMenuBar
{
#ifndef __CARBON__
	NSApp.presentationOptions = NSApplicationPresentationDefault;
#else
	SetSystemUIMode(kUIModeNormal, kUIOptionAnimateMenuBar);
#endif
}

//	MARK: - PGDisplayController

- (BOOL)setActiveDocument:(PGDocument *)document closeIfAppropriate:(BOOL)flag
{
	if(document || _isExitingFullscreen) return [super setActiveDocument:document closeIfAppropriate:NO];
	if(!self.activeDocument) return NO;
#if __has_feature(objc_arc)
	NSMutableArray *const docs = [[PGDocumentController sharedDocumentController].documents mutableCopy];
#else
	NSMutableArray *const docs = [[[[PGDocumentController sharedDocumentController] documents] mutableCopy] autorelease];
#endif
	PGDocument *const nextDoc = [[PGDocumentController sharedDocumentController] next:YES documentBeyond:self.activeDocument];
	[docs removeObjectIdenticalTo:self.activeDocument];
	[super setActiveDocument:nextDoc closeIfAppropriate:NO]; // PGDocumentController knows when to close us, so don't close ourselves.
	return NO;
}
- (NSWindow *)windowForSheet
{
	return nil;
}

//	MARK: - PGDisplayController(PGThumbnailControllerCallbacks)

- (void)thumbnailPanelDidBecomeKey:(NSNotification *)aNotif
{
	[self windowDidBecomeKey:aNotif];
}
- (void)thumbnailPanelDidResignKey:(NSNotification *)aNotif
{
	[self windowDidResignKey:aNotif];
}

//	MARK: - NSWindowController

- (BOOL)shouldCascadeWindows
{
	return NO;
}
- (void)windowDidLoad
{
#if __has_feature(objc_arc)
	NSWindow *const window = [[PGFullscreenWindow alloc] initWithScreen:[PGPreferenceWindowController.sharedPrefController displayScreen]];
	NSView *const content = self.window.contentView;
#else
	NSWindow *const window = [[[PGFullscreenWindow alloc] initWithScreen:[[PGPreferenceWindowController sharedPrefController] displayScreen]] autorelease];
	NSView *const content = [[[[self window] contentView] retain] autorelease];
#endif
	[self.window setContentView:nil];
	window.contentView = content;
	window.delegate = self.window.delegate;
	window.hidesOnDeactivate = self.window.hidesOnDeactivate;
//	[window registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSPasteboardTypeURL, nil]];
	[window registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSPasteboardTypeURL]];
	self.window = window;

	[super windowDidLoad];
}
- (void)close
{
	if(!_isExitingFullscreen) for(PGDocument *const doc in [PGDocumentController sharedDocumentController].documents) [doc close];
}

//	MARK: - NSObject

- (instancetype)init
{
	if((self = [super init])) {
		[[PGPreferenceWindowController sharedPrefController] PG_addObserver:self selector:@selector(displayScreenDidChange:) name:PGPreferenceWindowControllerDisplayScreenDidChangeNotification];
	}
	return self;
}
- (void)dealloc
{
	[self PG_cancelPreviousPerformRequests];
	[self PG_removeObserver];
	[_shieldWindows makeObjectsPerformSelector:@selector(close)];
#if !__has_feature(objc_arc)
	[_shieldWindows release];
	[super dealloc];
#endif
}

//	MARK: - <NSWindowDelegate>

- (void)windowDidBecomeMain:(NSNotification *)aNotif
{
	[super windowDidBecomeMain:aNotif];
	[NSCursor setHiddenUntilMouseMoves:YES];
}
- (void)windowDidResignMain:(NSNotification *)aNotif
{
	if(!_isExitingFullscreen) [super windowDidResignMain:aNotif];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotif
{
	BOOL const dim = [[NSUserDefaults standardUserDefaults] boolForKey:PGDimOtherScreensKey]; // We shouldn't need to observe this value because our fullscreen window isn't going to be key while the user is adjusting the setting in the prefs window.
	NSScreen *const displayScreen = [[PGPreferenceWindowController sharedPrefController] displayScreen];

	if(dim || [NSScreen PG_mainScreen] == displayScreen) [self _setMenuBarHidden:YES delayed:YES];

	if(!dim) return;
	[_shieldWindows makeObjectsPerformSelector:@selector(close)];
#if !__has_feature(objc_arc)
	[_shieldWindows release];
#endif
	_shieldWindows = [NSMutableArray new];
	for(NSScreen *const screen in [NSScreen screens]) {
		if(displayScreen == screen) continue;
#if __has_feature(objc_arc)
		NSWindow *const w = [[NSWindow alloc] initWithContentRect:screen.frame
		// Use borderless windows instead of CGSetDisplayTransferByFormula() so that
		// 1. the menu bar remains visible (if it's on a different screen), and
		// 2. the user can't click on things that can't be seen.
														styleMask:NSWindowStyleMaskBorderless
														  backing:NSBackingStoreBuffered
															defer:YES];
#else
		NSWindow *const w = [[[NSWindow alloc] initWithContentRect:[screen frame] styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES] autorelease]; // Use borderless windows instead of CGSetDisplayTransferByFormula() so that 1. the menu bar remains visible (if it's on a different screen), and 2. the user can't click on things that can't be seen.
#endif
		[w setReleasedWhenClosed:NO];
		w.backgroundColor = [NSColor blackColor];
		[w setHasShadow:NO];
		w.level = NSFloatingWindowLevel - 1;
		[w orderFront:self];
		[_shieldWindows addObject:w];
	}
}
- (void)windowDidResignKey:(NSNotification *)aNotif
{
	if([[PGPreferenceWindowController sharedPrefController] displayScreen] != [NSScreen PG_mainScreen])
		return;
	[self _setMenuBarHidden:NO delayed:YES];
	[_shieldWindows makeObjectsPerformSelector:@selector(close)];
#if !__has_feature(objc_arc)
	[_shieldWindows release];
#endif
	_shieldWindows = nil;
}

//	MARK: - <PGDocumentWindowDelegate>

- (NSDragOperation)window:(PGDocumentWindow *)window dragOperationForInfo:(id<NSDraggingInfo>)info
{
	if(!(info.draggingSourceOperationMask & NSDragOperationGeneric)) return NSDragOperationNone;
	NSPasteboard *const pboard = info.draggingPasteboard;
	NSArray *const types = pboard.types;
#if 1
	if([types containsObject:NSPasteboardTypeFileURL]) {
		return NSDragOperationGeneric;	//	2023/08/16 bugfix: no complex testing is now done
	} else if([types containsObject:NSPasteboardTypeURL]) {
		return [NSURL URLFromPasteboard:pboard] ? NSDragOperationGeneric : NSDragOperationNone;
	}
#else
	if([types containsObject:NSFilenamesPboardType]) {
		NSArray *const paths = [pboard propertyListForType:NSFilenamesPboardType];
		return [paths count] == 1 ? NSDragOperationGeneric : NSDragOperationNone;
	} else if([types containsObject:NSPasteboardTypeURL]) {
		return [NSURL URLFromPasteboard:pboard] ? NSDragOperationGeneric : NSDragOperationNone;
	}
#endif
	return NSDragOperationNone;
}
- (BOOL)window:(PGDocumentWindow *)window performDragOperation:(id<NSDraggingInfo>)info
{
	NSPasteboard *const pboard = info.draggingPasteboard;
	NSArray *const types = pboard.types;
#if 1
	if([types containsObject:NSPasteboardTypeFileURL])
		return !![[PGDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[[[pboard propertyListForType:NSPasteboardTypeFileURL] lastObject] PG_fileURL] display:YES];
	else if([types containsObject:NSPasteboardTypeURL])
		return !![[PGDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL URLFromPasteboard:pboard] display:YES];
#else
	if([types containsObject:NSFilenamesPboardType])
		return !![[PGDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[[[pboard propertyListForType:NSFilenamesPboardType] lastObject] PG_fileURL] display:YES];
	else if([types containsObject:NSPasteboardTypeURL])
		return !![[PGDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL URLFromPasteboard:pboard] display:YES];
#endif
	return NO;
}

//	MARK: - <PGFullscreenWindowDelegate>

- (void)closeWindowContent:(PGFullscreenWindow *)sender
{
	[self.activeDocument close];
}

@end
