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
#import "PGOrientationMenuItemCell.h"

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

#if __has_feature(objc_arc)
@interface PGOrientationMenuIconCell ()

@property (nonatomic, weak) NSMenuItem *item;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initTextCell:(NSString *)string NS_UNAVAILABLE;
- (instancetype)initImageCell:(nullable NSImage *)image NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

#endif

//	MARK: -
@implementation PGOrientationMenuIconCell

//	MARK: +PGOrientationMenuIconCell

+ (void)addOrientationMenuIconCellToMenuItem:(NSMenuItem *)anItem
{
	if(!anItem.separatorItem)
#if __has_feature(objc_arc)
		anItem.attributedTitle = [NSAttributedString PG_attributedStringWithAttachmentCell:[[self alloc] initWithMenuItem:anItem]
																					 label:anItem.title];
#else
		[anItem setAttributedTitle:[NSAttributedString PG_attributedStringWithAttachmentCell:[[[self alloc] initWithMenuItem:anItem] autorelease] label:[anItem title]]];
#endif
}

//	MARK: - PGOrientationMenuIconCell

- (instancetype)initWithMenuItem:(NSMenuItem *)anItem
{
	if((self = [super init])) {
		_item = anItem;
	}
	return self;
}
- (NSImage *)iconForOrientation:(inout PGOrientation *)orientation highlighted:(BOOL)flag
{
	switch(*orientation) {
		case PGFlippedHorz:
			*orientation = PGUpright;
			return [NSImage imageNamed:flag ? @"Mirror-White" : @"Mirror-Black"];
		case PGFlippedVert:
			*orientation = PGRotated90CCW;
			return [NSImage imageNamed:flag ? @"Mirror-White" : @"Mirror-Black"];
		default: return [NSImage imageNamed:flag ? @"Silhouette-White" : @"Silhouette-Black"];
	}
}

//	MARK: - NSTextAttachmentCell

- (void)drawWithFrame:(NSRect)aRect inView:(NSView *)aView
{
	[NSGraphicsContext saveGraphicsState];
	PGOrientation orientation = _item.tag;
	NSImage *const icon = [self iconForOrientation:&orientation highlighted:_item.highlighted];
	NSRect r = aRect;
	[[NSAffineTransform PG_transformWithRect:&r orientation:PGAddOrientation(orientation, [NSGraphicsContext currentContext].flipped ? PGFlippedVert : PGUpright)] concat];
	[icon drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:!_item || _item.enabled ? 1.0f : 0.5f];
	[NSGraphicsContext restoreGraphicsState];
}

@end
