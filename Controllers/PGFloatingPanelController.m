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

@implementation PGFloatingPanelController

//	MARK: - PGFloatingPanelController

- (void)setShown:(BOOL)flag
{
	if(flag == _shown) return;
	_shown = flag;
	if(flag) {
		[self windowWillShow];
		[super showWindow:self];
	} else {
		[self windowWillClose];
		[[self window] performClose:self];
	}
}
#if !__has_feature(objc_arc)
- (PGDisplayController *)displayController
{
	return [[_displayController retain] autorelease];
}
#endif
- (void)toggleShown
{
	[self setShown:![self isShown]];
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
- (void)windowWillShow {}
- (void)windowWillClose {}
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

//	MARK: -

- (void)windowDidBecomeMain:(NSNotification *)aNotif
{
	[self _updateWithDisplayController:aNotif ? [[aNotif object] windowController] : [[NSApp mainWindow] windowController]];
}
- (void)windowDidResignMain:(NSNotification *)aNotif
{
	[self _updateWithDisplayController:nil];
}

//	MARK: - PGFloatingPanelController(Private)

- (void)_updateWithDisplayController:(PGDisplayController *)controller
{
	PGDisplayController *const c = controller ? controller : [[NSApp mainWindow] windowController];
	[self setDisplayControllerReturningWasChanged:[c isKindOfClass:[PGDisplayController class]] ? c : nil];
}

//	MARK: - NSWindowController

- (id)initWithWindowNibName:(NSString *)name
{
	if((self = [super initWithWindowNibName:name])) {
		[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidBecomeMain:) name:NSWindowDidBecomeMainNotification object:nil];
		[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidResignMain:) name:NSWindowDidResignMainNotification object:nil];
	}
	return self;
}

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
}

//	MARK: - NSObject

- (id)init
{
	return [self initWithWindowNibName:[self nibName]];
}
- (void)dealloc
{
	[self PG_removeObserver];
#if !__has_feature(objc_arc)
	[_displayController release];
	[super dealloc];
#endif
}

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
	[self windowWillClose];
}

@end
