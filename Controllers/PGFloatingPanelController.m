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
#import "PGFloatingPanelController.h"

// Models
#import "PGNode.h"

// Controllers
#import "PGDisplayController.h"

// Other Sources
#import "PGFoundationAdditions.h"

#if __has_feature(objc_arc)

@interface PGFloatingPanelController ()

//@property (nonatomic, assign, getter = isShown) BOOL shown;
@property (nonatomic, strong) PGDisplayController *displayController;

- (void)_updateWithDisplayController:(PGDisplayController *)controller;

@end

#else

@interface PGFloatingPanelController(Private)

- (void)_updateWithDisplayController:(PGDisplayController *)controller;

@end

#endif

//	MARK: -
@implementation PGFloatingPanelController

- (void)_updateWithDisplayController:(PGDisplayController *)controller
{
	PGDisplayController *const c = controller ? controller : [[NSApp mainWindow] windowController];
	[self setDisplayControllerReturningWasChanged:[c isKindOfClass:[PGDisplayController class]] ? c : nil];
}

- (void)setShown:(BOOL)flag forFullScreenTransition:(BOOL)forFullScreenTransition
{
	if(flag == _shown) return;
	_shown = flag;
	id<PGFloatingPanelProtocol> pr = !forFullScreenTransition &&
		[self conformsToProtocol:@protocol(PGFloatingPanelProtocol)] ?
		(id<PGFloatingPanelProtocol>)self : nil;
	if(flag) {
		[pr windowWillShow];
		[super showWindow:self];
	} else {
		[pr windowWillClose];
		if(forFullScreenTransition)
			[[self window] orderOut:self];
		else
			[[self window] performClose:self];
	}
}
#if !__has_feature(objc_arc)
- (PGDisplayController *)displayController
{
	return [[_displayController retain] autorelease];
}
#endif
- (void)toggleShown {
	[self setShown:![self isShown] forFullScreenTransition:NO];
}
- (void)toggleShownUsing:(PGFloatingPanelToggleInstruction)i
{
	NSAssert(PGFloatingPanelToggleInstructionHide == i && self.isShown ||
		PGFloatingPanelToggleInstructionShowAtStatusWindowLevel == i && !self.isShown,
		@"");
	if(PGFloatingPanelToggleInstructionShowAtStatusWindowLevel == i)
		self.window.level = NSStatusWindowLevel;
	[self setShown:![self isShown] forFullScreenTransition:YES];
}

//	MARK: -

- (NSString *)nibName
{
	return nil;
}
- (NSString *)windowFrameAutosaveName
{
	NSString *const name = [self nibName];
	return name ? [NSString stringWithFormat:@"%@PanelFrame", name] : [NSString string];
}
- (BOOL)setDisplayControllerReturningWasChanged:(PGDisplayController *)controller
{
	if(controller == _displayController) return NO;
#if __has_feature(objc_arc)
	_displayController = controller;
#else
	[_displayController release];
	_displayController = [controller retain];
#endif
	return YES;
}

//	MARK: - NSWindowController

/* - (id)initWithWindowNibName:(NSString *)name
{
	if((self = [super initWithWindowNibName:name])) {
		//	these are not needed anymore (NSWindow will call these methods even if self
		//	is not registered as an observer)
		[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidBecomeMain:) name:NSWindowDidBecomeMainNotification object:nil];
		[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidResignMain:) name:NSWindowDidResignMainNotification object:nil];
	}
	return self;
} */

//	MARK: -

- (IBAction)showWindow:(id)sender
{
	[self setShown:YES];
}

//	MARK: -

- (BOOL)shouldCascadeWindows
{
	return NO;
}
- (void)windowDidLoad
{
	[super windowDidLoad];
	[self windowDidBecomeMain:nil];
	[(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded:YES];
#if 1	//	2022/02/15
	[self.window setFrameUsingName:self.windowFrameAutosaveName];
#else
	NSString *const savedFrame = [[NSUserDefaults standardUserDefaults] objectForKey:[self windowFrameAutosaveName]];
	if(savedFrame) {
		NSRect r = NSRectFromString(savedFrame);
		NSSize const min = [[self window] minSize];
		NSSize const max = [[self window] maxSize];
		r.size.width = MIN(MAX(min.width, NSWidth(r)), max.width);
		r.size.height = MIN(MAX(min.height, NSHeight(r)), max.height);
		[[self window] setFrame:r display:YES];
	}
#endif

//NSLog(@"collectionBehavior %lu", self.window.collectionBehavior);

	//	Do not do this; it causes the floating windows to not transition to macOS
	//	fullscreen mode correctly - probably one of the settings is incorrect;
	//	because the default behavior works correctly anyway, there's no need for this.
	//	It looks like Preview.app hides its Info window before entering fullscreen
	//	mode and then shows the Info window once the transition to fullscreen mode
	//	has been completed. That's now what this app does too.
/*	NSWindowCollectionBehavior cb = NSWindowCollectionBehaviorMoveToActiveSpace |
		NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle |
		NSWindowCollectionBehaviorFullScreenAuxiliary |
		NSWindowCollectionBehaviorFullScreenDisallowsTiling;
	if(@available(macOS 13.0, *))
		cb |= NSWindowCollectionBehaviorAuxiliary;

	self.window.collectionBehavior = cb;	*/
}

//	MARK: - NSObject

- (id)init
{
	return [self initWithWindowNibName:[self nibName]];
}
#if !__has_feature(objc_arc)
- (void)dealloc
{
//	[self PG_removeObserver];	no longer needed

	[_displayController release];
	[super dealloc];
}
#endif

//	MARK: - <NSWindowDelegate>

- (void)windowDidResize:(NSNotification *)notification
{
#if 1	//	2022/02/15
	[self.window saveFrameUsingName:self.windowFrameAutosaveName];
#else
	[[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect([[self window] frame]) forKey:[self windowFrameAutosaveName]];
#endif
}
- (void)windowDidMove:(NSNotification *)notification
{
	[self windowDidResize:nil];
}
- (void)windowWillClose:(NSNotification *)aNotif
{
	_shown = NO;

	if([self conformsToProtocol:@protocol(PGFloatingPanelProtocol)])
		[(id<PGFloatingPanelProtocol>)self windowWillClose];
}
- (void)windowDidBecomeMain:(NSNotification *)aNotif
{
	[self _updateWithDisplayController:aNotif ? [[aNotif object] windowController] : [[NSApp mainWindow] windowController]];
}
- (void)windowDidResignMain:(NSNotification *)aNotif
{
	[self _updateWithDisplayController:nil];
}

@end
