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
#import "PGBezelPanel.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGGeometry.h"
#import "PGFoundationAdditions.h"

NSString *const PGBezelPanelFrameShouldChangeNotification = @"PGBezelPanelFrameShouldChange";
NSString *const PGBezelPanelFrameDidChangeNotification    = @"PGBezelPanelFrameDidChange";

#if __has_feature(objc_arc)

@interface PGBezelPanel ()

@property (nonatomic, assign) BOOL canBecomeKey;

- (void)_updateFrameWithWindow:(NSWindow *)aWindow display:(BOOL)flag;

@end

#else

@interface PGBezelPanel(Private)

- (void)_updateFrameWithWindow:(NSWindow *)aWindow display:(BOOL)flag;

@end

#endif

//	MARK: -
@implementation PGBezelPanel

//	MARK: NSObject

+ (BOOL)instancesRespondToSelector:(SEL)aSelector
{
	if(@selector(cancelOperation:) == aSelector) return NO;
	if(@selector(performClose:) == aSelector) return NO;
	return [super instancesRespondToSelector:aSelector];
}

//	MARK: Instance Methods

- (instancetype)initWithContentView:(NSView *)aView
{
	if((self = [super initWithContentRect:(NSRect){NSZeroPoint, aView.frame.size} styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES])) {
		[self setOpaque:NO];
		self.backgroundColor = NSColor.clearColor;
	//	[self useOptimizedDrawing:YES];	2021/07/21 deprecated
		self.hidesOnDeactivate = NO;
		self.contentView = aView;
	}
	return self;
}
- (void)displayOverWindow:(NSWindow *)aWindow
{
	[self cancelFadeOut];
	if(aWindow != self.parentWindow) [self.parentWindow removeChildWindow:self];
	self.ignoresMouseEvents = !_acceptsEvents;
	[self _updateFrameWithWindow:aWindow display:NO];
	[aWindow addChildWindow:self ordered:NSWindowAbove];
}

//	MARK: -

/* - (id)content
{
	return self.contentView;
} */

//	MARK: -

#if !__has_feature(objc_arc)
- (BOOL)acceptsEvents
{
	return _acceptsEvents;
}
- (void)setAcceptsEvents:(BOOL)flag
{
	_acceptsEvents = flag;
}
#endif
- (void)setCanBecomeKey:(BOOL)flag
{
	_canBecomeKey = flag;
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGInset)frameInset
{
	return _frameInset;
}
- (void)setFrameInset:(PGInset)inset
{
	_frameInset = inset;
}
#endif

//	MARK: -

- (void)updateFrameDisplay:(BOOL)flag
{
	[self _updateFrameWithWindow:self.parentWindow display:flag];
}

//	MARK: -

- (void)frameShouldChange:(NSNotification *)aNotif
{
	[self updateFrameDisplay:YES];
}
- (void)windowDidResize:(NSNotification *)aNotif
{
	[self updateFrameDisplay:YES];
}

//	MARK: Private Protocol

- (void)_updateFrameWithWindow:(NSWindow *)aWindow display:(BOOL)flag
{
	if(![self.contentView respondsToSelector:@selector(bezelPanel:frameForContentRect:scale:)])
		return;
#if 1	//	2021/07/21 modernized
	NSRect const f = [self.contentView bezelPanel:self
							  frameForContentRect:PGInsetRect([aWindow PG_contentRect], _frameInset)
											scale:(CGFloat)1.0];
#else
	CGFloat const s = [self userSpaceScaleFactor];
	NSRect const f = [[self contentView] bezelPanel:self frameForContentRect:PGInsetRect([aWindow PG_contentRect], PGScaleInset(_frameInset, 1.0f / s)) scale:s];
#endif
	if(NSEqualRects(self.frame, f))
		return;
//	if(flag) NSDisableScreenUpdates();	2021/07/21 deprecated
	[self setFrame:f display:NO];
	if(flag) {
		[self.contentView display]; // Do this instead of sending -setFrame:display:YES to force redisplay no matter what.
	//	NSEnableScreenUpdates();	2021/07/21 deprecated
	}
	[self PG_postNotificationName:PGBezelPanelFrameDidChangeNotification];
}

//	MARK: NSStandardKeyBindingMethods Protocol

- (void)cancelOperation:(id)sender
{
	[self doesNotRecognizeSelector:_cmd];
}

//	MARK: NSObject Protocol

- (BOOL)respondsToSelector:(SEL)aSelector
{
	if(@selector(cancelOperation:) == aSelector) return NO;
	if(@selector(performClose:) == aSelector) return NO;
	return [super respondsToSelector:aSelector];
}

//	MARK: NSWindow

- (IBAction)performClose:(id)sender
{
	[self doesNotRecognizeSelector:_cmd];
}

//	MARK: -

- (BOOL)canBecomeKeyWindow
{
	if(self.isFadingOut) return NO;
	return _canBecomeKey || (_acceptsEvents && !self.parentWindow.keyWindow && self.parentWindow.canBecomeKeyWindow);
}
- (void)becomeKeyWindow
{
	[super becomeKeyWindow];
	if(!_canBecomeKey) [self.parentWindow makeKeyAndOrderFront:self];
}
- (void)setContentView:(NSView *)aView
{
	[self.contentView PG_removeObserver:self name:PGBezelPanelFrameShouldChangeNotification];
	super.contentView = aView;
	[self.contentView PG_addObserver:self selector:@selector(frameShouldChange:) name:PGBezelPanelFrameShouldChangeNotification];
}
- (void)setParentWindow:(NSWindow *)aWindow
{
	[self.parentWindow PG_removeObserver:self name:NSWindowDidResizeNotification];
	super.parentWindow = aWindow;
	[self.parentWindow PG_addObserver:self selector:@selector(windowDidResize:) name:NSWindowDidResizeNotification];
}

//	MARK: NSObject

- (void)dealloc
{
	[self PG_removeObserver];
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

@end

@implementation NSView(PGBezelPanelContentView)

+ (id)PG_bezelPanel
{
#if __has_feature(objc_arc)
	return [[PGBezelPanel alloc] initWithContentView:[[self alloc] initWithFrame:NSZeroRect]];
#else
	return [[[PGBezelPanel alloc] initWithContentView:[[[self alloc] initWithFrame:NSZeroRect] autorelease]] autorelease];
#endif
}

@end
