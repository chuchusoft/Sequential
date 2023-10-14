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
#import "PGThumbnailInfoView.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"
#import "PGDocumentController.h"	//	for thumbnail userDefault keys

//	2023/10/02 for _infoWindow:
typedef enum SizeFormat { SizeFormatNone, SizeFormatBase10, SizeFormatBase2, SizeFormatBytes } SizeFormat;
extern	NSString*	StringForByteSizeWithFormat(SizeFormat format, uint64_t bytes, int nDecimalDigits);
extern	NSString*	StringForImageCount(NSUInteger const imageCount);
extern	NSInteger	GetThumbnailSizeFormat(void);

static
NSString*
StringForDisplay(NSUInteger imageCount, uint64_t byteSizeTotal) {
	enum { DECIMAL_DIGITS = 2 };
	return [NSString stringWithFormat:@"%@ %@", StringForImageCount(imageCount),
			StringForByteSizeWithFormat((SizeFormat) (1 + GetThumbnailSizeFormat()),
										byteSizeTotal, DECIMAL_DIGITS)];
}

@implementation PGThumbnailInfoView

- (id)initWithFrame:(NSRect)frameRect {
	if((self = [super initWithFrame:frameRect])) {
		NSUserDefaults *sud = NSUserDefaults.standardUserDefaults;
		[sud addObserver:self
			  forKeyPath:PGThumbnailSizeFormatKey
				 options:kNilOptions
				 context:NULL];
	}
	return self;
}

- (NSAttributedString *)attributedStringValue
{
	NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	[style setAlignment:NSTextAlignmentCenter];
	[style setLineBreakMode:NSLineBreakByTruncatingMiddle];
	return [[[NSAttributedString alloc] initWithString:StringForDisplay(_imageCount, _byteSizeTotal)
											attributes:@{
		NSFontAttributeName: [NSFont labelFontOfSize:0.0f],
		NSForegroundColorAttributeName: NSColor.whiteColor,
		NSParagraphStyleAttributeName: style,
	}] autorelease];
}
- (void)setImageCount:(NSUInteger)imageCount byteSizeTotal:(uint64_t)byteSizeTotal {
	_imageCount = imageCount;
	_byteSizeTotal = byteSizeTotal;

	self.needsDisplay = YES;
}

#pragma mark - NSView

- (BOOL)isFlipped
{
	return NO;
}

#define PGMarginSize 4.0f // Outside the window.
#define PGPaddingSize 2.0f // Inside the window.
#define PGTotalPaddingSize (PGPaddingSize * 2.0f)
#define PGTextBottomPadding (PGPaddingSize - 1.0f)
#define PGTextTotalVertPadding (PGPaddingSize + PGTextBottomPadding)
#define PGTextHorzPadding 4.0f
#define PGTextTotalHorzPadding (PGTextHorzPadding * 2.0f)

- (void)drawRect:(NSRect)aRect
{
	NSRect const b = [self bounds];

	[[NSColor PG_bezelBackgroundColor] set];
	[[NSBezierPath bezierPathWithRect:b] fill];

	[[NSColor PG_bezelForegroundColor] set];
	[[self attributedStringValue] drawInRect:NSMakeRect(NSMinX(b) + PGPaddingSize + PGTextHorzPadding,
														NSMinY(b) + PGTextBottomPadding,
														NSWidth(b) - PGTotalPaddingSize - PGTextTotalHorzPadding,
														NSHeight(b) - PGTextTotalVertPadding)];
}

#pragma mark - NSObject

- (void)dealloc
{
	NSUserDefaults *sud = NSUserDefaults.standardUserDefaults;
	[sud removeObserver:self forKeyPath:PGThumbnailSizeFormatKey];

	[super dealloc];
}

#pragma mark - NSObject(NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	if(PGEqualObjects(keyPath, PGThumbnailSizeFormatKey))
		self.needsDisplay	=	YES;
	else
		[super observeValueForKeyPath:keyPath
							 ofObject:object
							   change:change
							  context:context];
}

#pragma mark - <PGBezelPanelContentView>

- (NSRect)bezelPanel:(PGBezelPanel *)sender frameForContentRect:(NSRect)aRect scale:(CGFloat)scaleFactor
{
	NSSize const messageSize = [[self attributedStringValue] size];
	CGFloat const scaledMarginSize = PGMarginSize * scaleFactor;
	NSRect const frame = NSIntersectionRect(
		NSMakeRect(
			NSMinX(aRect) + scaledMarginSize,
			NSMinY(aRect) + scaledMarginSize,
			ceilf((messageSize.width + PGTextTotalHorzPadding + messageSize.width + PGTotalPaddingSize) * scaleFactor),
			ceilf(MAX(messageSize.height + PGTextTotalVertPadding, messageSize.height) * scaleFactor)),
		NSInsetRect(aRect, scaledMarginSize, scaledMarginSize));
	return frame;
}

@end
