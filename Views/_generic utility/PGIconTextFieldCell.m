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
#import "PGIconTextFieldCell.h"

// Other Sources
#import "PGFoundationAdditions.h"

#define PGIconSize 16.0f
#define PGIconSpacingLeft 5.0f
#define PGIconSpacingRight 3.0f
#define PGTextInset (PGIconSpacingLeft + PGIconSize + PGIconSpacingRight)

//	MARK: -
@implementation PGIconTextFieldCell

//	MARK: - NSCell

- (NSRect)titleRectForBounds:(NSRect)aRect
{
	NSRect r = aRect;
	r.origin.x += PGTextInset;
	r.size.width -= PGTextInset;
	return r;
}
- (void)drawInteriorWithFrame:(NSRect)aRect inView:(NSView *)aView
{
	[super drawInteriorWithFrame:[self titleRectForBounds:aRect] inView:aView];

	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
	NSRect r = NSMakeRect(NSMinX(aRect) + PGIconSpacingLeft, NSMinY(aRect), PGIconSize, PGIconSize);
	[[NSAffineTransform PG_counterflipWithRect:&r] concat];
	[self.icon drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1.0f : 0.66f];
	[NSGraphicsContext restoreGraphicsState];
}
- (void)editWithFrame:(NSRect)aRect inView:(NSView *)aView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)anEvent
{
	[super editWithFrame:[self titleRectForBounds:aRect] inView:aView editor:textObj delegate:anObject event:anEvent];
}
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)aView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength
{
	[super selectWithFrame:[self titleRectForBounds:aRect] inView:aView editor:textObj delegate:anObject start:selStart length:selLength];
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_icon release];
	[super dealloc];
}
#endif

//	MARK: - <NSCopying>

- (id)copyWithZone:(NSZone *)aZone
{
	PGIconTextFieldCell *const dupe = [super copyWithZone:aZone];
#if __has_feature(objc_arc)
	dupe->_icon = _icon;
#else
	dupe->_icon = [_icon retain];
#endif
	return dupe;
}

@end
