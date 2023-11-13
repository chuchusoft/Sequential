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
#import "PGAttachments.h"

// Other Sources
#import "PGFoundationAdditions.h"

@implementation NSAttributedString(PGAdditions)

//	MARK: NSAttributedString(PGAdditions)

+ (NSMutableAttributedString *)PG_attributedStringWithAttachmentCell:(NSTextAttachmentCell *)cell label:(NSString *)label
{
#if __has_feature(objc_arc)
	NSMutableAttributedString *const result = [NSMutableAttributedString new];
#else
	NSMutableAttributedString *const result = [[[NSMutableAttributedString alloc] init] autorelease];
#endif
	if(cell) {
#if __has_feature(objc_arc)
		NSTextAttachment *const attachment = [NSTextAttachment new];
#else
		NSTextAttachment *const attachment = [[[NSTextAttachment alloc] init] autorelease];
#endif
		[attachment setAttachmentCell:cell];
		[result appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
		if(label) [[result mutableString] appendString:@" "];
	}
	if(label) [[result mutableString] appendString:label];
	// Use 14 instead of 0 (default) for the font size because the default seems to be 13, which is wrong.
	[result addAttribute:NSFontAttributeName
				   value:[NSFont menuFontOfSize:14.0f]
				   range:NSMakeRange(0, [result length])];
	return result;
}
+ (NSMutableAttributedString *)PG_attributedStringWithFileIcon:(NSImage *)anImage name:(NSString *)fileName
{
#if __has_feature(objc_arc)
	return [self PG_attributedStringWithAttachmentCell:[[PGIconAttachmentCell alloc] initImageCell:anImage]
												 label:fileName];
#else
	return [self PG_attributedStringWithAttachmentCell:[[[PGIconAttachmentCell alloc] initImageCell:anImage] autorelease] label:fileName];
#endif
}

@end

//	MARK: -
@implementation PGIconAttachmentCell

//	MARK: NSTextAttachmentCell

- (void)drawWithFrame:(NSRect)aRect inView:(NSView *)aView
{
	[NSGraphicsContext saveGraphicsState];
	[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
	NSRect r = aRect;
	[[NSAffineTransform PG_counterflipWithRect:&r] concat];
	r.origin.x = round(NSMinX(r));
	[[self image] drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0f];
	[NSGraphicsContext restoreGraphicsState];
}
- (NSSize)cellSize
{
	return NSMakeSize(16.0f, 16.0f);
}
- (NSPoint)cellBaselineOffset
{
	return NSMakePoint(0.0f, -3.0f);
}

//	MARK: - NSCell

- (id)initImageCell:(NSImage *)anImage
{
	if(anImage) return [super initImageCell:anImage];
#if __has_feature(objc_arc)
	self = nil;
#else
	[self release];
#endif
	return nil;
}

@end
