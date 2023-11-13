/* Copyright © 2007-2008, The Sequential Project
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
#import "PGFadeOutPanel.h"

#define PGFadeOutPanelFrameRate (1.0 / 30.0)
#define PGFadeOutPanelDuration  0.20

#if __has_feature(objc_arc)
@interface PGFadeOutPanel ()

@property (readonly) unsigned frameCount;
@property (nonatomic, assign) float savedAlphaValue;
@property (nonatomic, assign) BOOL savedIgnoresMouseEvents;

@end

#endif

@implementation PGFadeOutPanel

#pragma mark -PGFadeOutPanel

- (BOOL)isFadingOut
{
	return _frameCount != 0;
}
- (void)fadeOut
{
#if !__has_feature(objc_arc)
	[[self retain] autorelease];
#endif
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeOut) object:nil];
	if(![self isFadingOut]) {
		_savedAlphaValue = [self alphaValue];
		_savedIgnoresMouseEvents = [self ignoresMouseEvents];
		[self setIgnoresMouseEvents:YES];
	}

	float const x = ++_frameCount / (PGFadeOutPanelDuration / PGFadeOutPanelFrameRate) - 1;
	if(x >= 0) return [self close];
	[self setAlphaValue:_savedAlphaValue * powf(x, 2)];
	[self performSelector:@selector(fadeOut) withObject:nil afterDelay:PGFadeOutPanelFrameRate inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
}
- (void)cancelFadeOut
{
	if(![self isFadingOut]) return;
	[self setAlphaValue:_savedAlphaValue];
	[self setIgnoresMouseEvents:_savedIgnoresMouseEvents];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeOut) object:nil];
	_frameCount = 0;
}

#pragma mark -NSWindow

- (IBAction)makeKeyAndOrderFront:(id)sender
{
	[self cancelFadeOut];
	[super makeKeyAndOrderFront:sender];
}
- (IBAction)orderFront:(id)sender
{
	[self cancelFadeOut];
	[super orderFront:sender];
}

- (void)orderFrontRegardless
{
	[self cancelFadeOut];
	[super orderFrontRegardless];
}

- (void)close
{
	[[self parentWindow] removeChildWindow:self];
	[super close];
	[self cancelFadeOut];
}

#pragma mark -NSObject

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

@end
