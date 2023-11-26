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
#import "PGFullscreenWindow.h"

// Other Sources
#import "PGAppKitAdditions.h"

extern	const NSString* const	PGUseEntireScreenWhenInFullScreenKey;

static
BOOL
ShouldUseEntireScreenWhenInFullScreen(void) {
	return [NSUserDefaults.standardUserDefaults
			boolForKey:(NSString*)PGUseEntireScreenWhenInFullScreenKey];
}

static
CGFloat
GetNotchHeight(NSScreen* screen) {
	if(@available(macOS 12.0, *))
		return screen.safeAreaInsets.top;
	else
		return 0;
}

static
NSRect
GetSuitableFrameForScreenWithNotch(BOOL useEntireScreen, NSScreen* screen) {
	if(nil == screen)
		return NSZeroRect;

//if(useEntireScreen) NSLog(@"screen.frame = %5.2f x %5.2f", screen.frame.size.width, screen.frame.size.height);

	if(useEntireScreen)
		return screen.frame;

	//	return a frame that positions the window under the notch
	return NSMakeRect(screen.frame.origin.x, screen.frame.origin.y,
						screen.frame.size.width,
						screen.frame.size.height - GetNotchHeight(screen));
}

//	MARK: -

#if __has_feature(objc_arc)
@interface PGFullscreenWindow ()
@property (nonatomic, strong) NSWindow* blackHideTheNotchWindow;	//	2023/08/14 added
@end
#endif

//	MARK: -
@implementation PGFullscreenWindow

//	MARK: Instance Methods

- (void)_allocateAndShowTheBlackHideTheNotchWindowOn:(NSScreen*)screen {
	NSParameterAssert(nil == _blackHideTheNotchWindow);

	//	2023/08/14 when a notch is present, create an extra window to
	//	"paint" the areas besides the notch as black to obscure it.
	const CGFloat	notchHeight = GetNotchHeight(screen);
	if(0 != notchHeight) {
		_blackHideTheNotchWindow	=	[[NSWindow alloc]
			initWithContentRect:NSMakeRect(0, 0, screen.frame.size.width,
											screen.frame.size.height)
					  styleMask:NSWindowStyleMaskBorderless
						backing:NSBackingStoreBuffered
						  defer:YES
						 screen:screen];

		_blackHideTheNotchWindow.backgroundColor	=	NSColor.blackColor;
		[_blackHideTheNotchWindow orderBack:self];
	}
}

- (void)_deallocateTheBlackHideTheNotchWindow {
	if(_blackHideTheNotchWindow) {
		[_blackHideTheNotchWindow orderOut:self];
#if !__has_feature(objc_arc)
		[_blackHideTheNotchWindow release];
#endif
		_blackHideTheNotchWindow	=	nil;
	}
}

- (void)dealloc {
	[self _deallocateTheBlackHideTheNotchWindow];

#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

- (instancetype)initWithScreen:(NSScreen *)screen
{
	const BOOL	useEntireScreen = ShouldUseEntireScreenWhenInFullScreen();
	if((self = [super initWithContentRect:GetSuitableFrameForScreenWithNotch(useEntireScreen, screen)
								styleMask:NSWindowStyleMaskFullSizeContentView // NSWindowStyleMaskBorderless
								  backing:NSBackingStoreBuffered
									defer:YES])) {
		if(!useEntireScreen)
			[self _allocateAndShowTheBlackHideTheNotchWindowOn:screen];
		[self setHasShadow:NO];
	}
	return self;
}

- (void)moveToScreen:(NSScreen *)screen
{
	if(nil == screen)
		return;

	const BOOL	useEntireScreen = ShouldUseEntireScreenWhenInFullScreen();

	if(!useEntireScreen) {
		if(nil != _blackHideTheNotchWindow) {
			if(0 != GetNotchHeight(screen))
				//	already exists and new screen has notch ---> move helper window
				[_blackHideTheNotchWindow setFrame:screen.frame
										   display:YES];
			else
				//	this screen does not have a notch --> dealloc helper window
				[self _deallocateTheBlackHideTheNotchWindow];
		} else
			[self _allocateAndShowTheBlackHideTheNotchWindowOn:screen];
	}

	[self setFrame:GetSuitableFrameForScreenWithNotch(useEntireScreen, screen)
		   display:YES];
}

- (void)resizeToUseEntireScreen	//	called when the "Use Entire Screen" command is used
{
	NSScreen*	screen = self.screen;
	const BOOL	useEntireScreen = ShouldUseEntireScreenWhenInFullScreen();
	if(useEntireScreen) {
		NSParameterAssert(nil != _blackHideTheNotchWindow);
		[self _deallocateTheBlackHideTheNotchWindow];
	} else {
		NSParameterAssert(nil == _blackHideTheNotchWindow);
		[self _allocateAndShowTheBlackHideTheNotchWindowOn:screen];
	}

	[self setFrame:GetSuitableFrameForScreenWithNotch(useEntireScreen, screen)
		   display:YES];
}

//	MARK: NSMenuValidation Protocol

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	// NSWindow doesn't like -performClose: for borderless windows.
	return anItem.action == @selector(performClose:) ? YES :
			[super validateMenuItem:anItem];
}

//	MARK: NSWindow

- (IBAction)performClose:(id)sender
{
	[(NSObject<PGFullscreenWindowDelegate> *)self.delegate closeWindowContent:self];
}

//	MARK: -

- (BOOL)canBecomeKeyWindow
{
	return YES;
}

- (BOOL)canBecomeMainWindow
{
	return self.isVisible; // Return -isVisible because that's (the relevant part of) what NSWindow does.
}

@end

//	MARK: -
@implementation NSObject(PGFullscreenWindowDelegate)

- (void)closeWindowContent:(PGFullscreenWindow *)sender {
}

@end
