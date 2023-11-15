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
#import "PGInfoView.h"
#import <tgmath.h>

// Views
#import "PGBezelPanel.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"

#define PGGraphicalProgressBarStyle true
#define PGMarginSize 4.0f // Outside the window.
#define PGPaddingSize 2.0f // Inside the window.
#define PGTotalPaddingSize (PGPaddingSize * 2.0f)
#define PGTextBottomPadding (PGPaddingSize - 1.0f)
#define PGTextTotalVertPadding (PGPaddingSize + PGTextBottomPadding)
#define PGTextHorzPadding 4.0f
#define PGTextTotalHorzPadding (PGTextHorzPadding * 2.0f)
#define PGProgressBarMargin 1.0f
#define PGProgressBarBorder (PGPaddingSize + PGProgressBarMargin)
#define PGProgressBarHeight 10.0f
#define PGProgressBarRadius (PGProgressBarHeight / 2.0f)
#define PGProgressBarWidth 100.0f
#define PGProgressKnobSize (PGProgressBarHeight - 2.0f)
#define PGCornerRadius (PGProgressBarBorder + PGProgressBarRadius)

//	MARK: -
@implementation PGInfoView

- (NSAttributedString *)attributedStringValue
{
#if __has_feature(objc_arc)
	NSMutableParagraphStyle *const style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
#else
	NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
#endif
	[style setAlignment:NSTextAlignmentCenter];
	[style setLineBreakMode:NSLineBreakByTruncatingMiddle];
#if __has_feature(objc_arc)
	return [[NSAttributedString alloc] initWithString:self.stringValue attributes:@{
		NSFontAttributeName: [NSFont labelFontOfSize:0.0f],
		NSForegroundColorAttributeName: NSColor.whiteColor,
		NSParagraphStyleAttributeName: style}];
#elif 1
	return [[[NSAttributedString alloc] initWithString:self.stringValue attributes:@{
		NSFontAttributeName: [NSFont labelFontOfSize:0.0f],
		NSForegroundColorAttributeName: NSColor.whiteColor,
		NSParagraphStyleAttributeName: style,
	}] autorelease];
#else
	if(![self showsProgressBar]) [style setAlignment:NSTextAlignmentCenter];
	NSString *const string = PGGraphicalProgressBarStyle ? [self stringValue] : [NSString stringWithFormat:@"%@ (%lu/%lu)", [self stringValue], (unsigned long)[self index] + 1, (unsigned long)[self count]];
	return [[[NSAttributedString alloc] initWithString:string attributes:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont labelFontOfSize:0.0f], NSFontAttributeName,
		[NSColor whiteColor], NSForegroundColorAttributeName,
		style, NSParagraphStyleAttributeName,
		nil]] autorelease];
#endif
}
#if __has_feature(objc_arc)
@synthesize stringValue = _stringValue;
#endif
- (NSString *)stringValue
{
#if __has_feature(objc_arc)
	return _stringValue ? _stringValue : [NSString string];
#else
	return _stringValue ? [[_stringValue retain] autorelease] : @"";
#endif
}
- (void)setStringValue:(NSString *)aString
{
	NSString *const string = aString ? aString : @"";
	if(string == _stringValue) return;
#if !__has_feature(objc_arc)
	[_stringValue release];
#endif
	_stringValue = [string copy];
	[self setNeedsDisplay:YES];
	[self PG_postNotificationName:PGBezelPanelFrameShouldChangeNotification];
}
- (void)setIndex:(NSUInteger)anInt
{
	if(anInt == _index) return;
	_index = anInt;
	[self setNeedsDisplay:YES];
}
- (void)setCount:(NSUInteger)anInt
{
	if(anInt == _count) return;
	BOOL const showedProgressBar = [self showsProgressBar];
	_count = anInt;
	if(!showedProgressBar != ![self showsProgressBar]) [self PG_postNotificationName:PGBezelPanelFrameShouldChangeNotification];
	else [self setNeedsDisplay:YES];
}

- (void)setCurrentFolderIndex:(NSUInteger)anInt
{
	if(anInt == _currentFolderIndex) return;
	_currentFolderIndex = anInt;
	[self setNeedsDisplay:YES];
}
- (void)setCurrentFolderCount:(NSUInteger)anInt
{
	if(anInt == _currentFolderCount) return;
	_currentFolderCount = anInt;
	[self setNeedsDisplay:YES];
}

- (BOOL)showsProgressBar
{
	return PGGraphicalProgressBarStyle && [self count] > 1;
}

//	MARK: - NSView

- (BOOL)isFlipped
{
	return NO;
}
- (void)drawRect:(NSRect)aRect
{
	NSRect const b = [self bounds];

	//	[1] fill the background region
	{
		NSBezierPath *const bezel = [NSBezierPath PG_bezierPathWithRoundRect:b cornerRadius:PGCornerRadius];
		[[NSColor PG_bezelBackgroundColor] set];
		[bezel fill];
	}

	if([self showsProgressBar]) {
		BOOL const canAlignToBackingStore = [self respondsToSelector:@selector(backingAlignedRect:options:)];	//	10.7+
		CGFloat const origin = [self originCorner] == PGMaxXMinYCorner ?
								NSMaxX(b) - 1.0f - PGProgressBarBorder : PGProgressBarBorder;
		NSRect progressBarRect = NSMakeRect(
			[self originCorner] == PGMinXMinYCorner ? 0.5f + origin : 0.5f + origin - PGProgressBarWidth,
			0.5f + PGProgressBarBorder, PGProgressBarWidth, PGProgressBarHeight);

		//	if possible, draw the outline in a backing store aligned rectangle;
		//	doing so will look better on high pixel density display devices
		NSBezierPath *const progressBarOutline =
			[NSBezierPath PG_bezierPathWithRoundRect:(canAlignToBackingStore ?
				[self backingAlignedRect:progressBarRect options:NSAlignAllEdgesNearest] :
				progressBarRect)
										cornerRadius:PGProgressBarRadius];

#define	COLOR_FILLED_BAR_IS_ENTIRE_PROGRESS	1

#if COLOR_FILLED_BAR_IS_ENTIRE_PROGRESS
		//	[2] 2023/11/15 draw the entire progress as a color-filled bar
		if(_count > 1) {
			CGFloat const w = PGProgressBarWidth * _index / (_count - 1);
#else
		//	[2] [2023/10/01 draw the current folder progress as a color-filled bar
		if(_currentFolderCount > 1) {
			CGFloat const w = PGProgressBarWidth * _currentFolderIndex /
								(_currentFolderCount - 1);
#endif
			if(w > 0) {
				progressBarRect.size.width = w;
				#define PGProgressBarDiameter	(2 * PGProgressBarRadius)
				BOOL const needsClipping = w < PGProgressBarDiameter;
				if(needsClipping) {
					progressBarRect.origin.x += w - PGProgressBarDiameter;
					progressBarRect.size.width = PGProgressBarDiameter;

					//	need to clip otherwise the folder-progress bar is drawn outside the outline's region
					[NSGraphicsContext saveGraphicsState];
					[progressBarOutline setClip];
				}

				//	using a backing aligned rect causes the progress to look jerky as several indexes
				//	end up drawing to the same rectangle whereas a rect with a fractional width
				//	appears to progress smoothly, so use progressBarRect unaligned (as it is)
				NSBezierPath *const folderProgress = [NSBezierPath PG_bezierPathWithRoundRect:progressBarRect
																				 cornerRadius:PGProgressBarRadius];
#if 0	//	debugging only:
				if(needsClipping) {
				/*	this does not work because system colors are dynamic
					NSColor *const scbgColor = NSColor.selectedContentBackgroundColor;
				    if ((scbgColor.type == NSColorTypeComponentBased) &&
						(scbgColor.colorSpace.colorSpaceModel == NSColorSpaceModelRGB))
						[[NSColor colorWithHue:1-scbgColor.hueComponent
									saturation:scbgColor.saturationComponent
									brightness:scbgColor.brightnessComponent
										 alpha:scbgColor.alphaComponent] set];
					else	*/
						[[NSColor yellowColor] set];
				} else
#endif
					[[NSColor selectedContentBackgroundColor] set];
				[folderProgress fill];

				if(needsClipping)
					[NSGraphicsContext restoreGraphicsState];
			}
		}

		//	draw knob in progress bar and progress bar outline

#if 0	//	debugging only:
		[[[NSColor PG_bezelForegroundColor] colorWithAlphaComponent:0.2f] set];
#else
		[[NSColor PG_bezelForegroundColor] set];

		//	[3] draw knob in progress bar
	#if COLOR_FILLED_BAR_IS_ENTIRE_PROGRESS
		if(_currentFolderCount > 1) {
			NSUInteger const maxValue = _currentFolderCount - 1;
			NSUInteger const curValue = _currentFolderIndex;
	#else
		if([self count] > 1) {
			NSUInteger const maxValue = [self count] - 1;
			NSUInteger const curValue = [self index];
	#endif

	#if 1
			//	2023/10/26 draw anti-aliased rounded knob at fractional locations
			CGFloat x = ((CGFloat)MIN(curValue, maxValue) / maxValue) * (PGProgressBarWidth - PGProgressBarHeight) +
						PGProgressBarHeight / 2.0f;
	#else
			//	original code: draws unaliased diamond at integral locations
			CGFloat x = round(((CGFloat)MIN(curValue, maxValue) / maxValue) * (PGProgressBarWidth - PGProgressBarHeight) +
								PGProgressBarHeight / 2.0f);
	#endif
			if([self originCorner] == PGMaxXMinYCorner) x = -x + origin;
			else x = x + origin;

			{
	#if 1
				//	2023/10/26 draw anti-aliased rounded knob at fractional locations
				#define PGProgressThreeQuartersKnobSize (PGProgressKnobSize * 0.75f)
				NSRect const knobRect = NSMakeRect(x + (0.5f - PGProgressThreeQuartersKnobSize / 2.0f),
													0.5f + PGProgressBarHeight / 2.0f,
													PGProgressThreeQuartersKnobSize, PGProgressThreeQuartersKnobSize);
				NSBezierPath *const knob = [NSBezierPath PG_bezierPathWithRoundRect:knobRect
																	   cornerRadius:PGProgressThreeQuartersKnobSize / 2.0f];
				[knob fill];
	#else
				//	original code: draws unaliased diamond at integral locations
				[NSGraphicsContext saveGraphicsState];
				[[NSGraphicsContext currentContext] setShouldAntialias:NO];
				NSBezierPath *const knob = [NSBezierPath bezierPath];
				CGFloat const halfKnob = PGProgressKnobSize / 2.0f;
				[knob moveToPoint:NSMakePoint(0.5f + x           , 1.5f + PGProgressBarBorder)];
				[knob lineToPoint:NSMakePoint(0.5f + x - halfKnob, 1.5f + PGProgressBarBorder + halfKnob)];
				[knob lineToPoint:NSMakePoint(0.5f + x           , 1.5f + PGProgressBarBorder + PGProgressKnobSize)];
				[knob lineToPoint:NSMakePoint(0.5f + x + halfKnob, 1.5f + PGProgressBarBorder + halfKnob)];
				[knob closePath];
				[knob fill];
				[NSGraphicsContext restoreGraphicsState];
	#endif
			}
		}
#endif

		//	[4] draw progress bar outline
		[progressBarOutline stroke];
	}

	//	[5] draw name of image file
	CGFloat const progressBarWidth = [self showsProgressBar] ? PGProgressBarWidth : 0.0f;
	CGFloat const textOffset = [self originCorner] == PGMinXMinYCorner ? progressBarWidth : 0.0f;
	[[self attributedStringValue] drawInRect:NSMakeRect(NSMinX(b) + PGPaddingSize + PGTextHorzPadding + textOffset,
														NSMinY(b) + PGTextBottomPadding,
														NSWidth(b) - PGTotalPaddingSize - PGTextTotalHorzPadding - progressBarWidth,
														NSHeight(b) - PGTextTotalVertPadding)];
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_stringValue release];
	[super dealloc];
}
#endif

//	MARK: - <PGBezelPanelContentView>

- (NSRect)bezelPanel:(PGBezelPanel *)sender frameForContentRect:(NSRect)aRect scale:(CGFloat)scaleFactor
{
	NSSize const messageSize = [[self attributedStringValue] size];
	NSSize const progressBarSize = [self showsProgressBar] ? NSMakeSize(PGProgressBarWidth + 1.0f + PGProgressBarMargin * 2.0f, PGProgressBarHeight + 1.0f + PGProgressBarBorder * 2.0f) : NSZeroSize;
	CGFloat const scaledMarginSize = PGMarginSize * scaleFactor;
	NSRect frame = NSIntersectionRect(
		NSMakeRect(
			NSMinX(aRect) + scaledMarginSize,
			NSMinY(aRect) + scaledMarginSize,
			ceilf((messageSize.width + PGTextTotalHorzPadding + progressBarSize.width + PGTotalPaddingSize) * scaleFactor),
			ceilf(MAX(messageSize.height + PGTextTotalVertPadding, progressBarSize.height) * scaleFactor)),
		NSInsetRect(aRect, scaledMarginSize, scaledMarginSize));
	frame.size.width = MAX(NSWidth(frame), NSHeight(frame)); // Don't allow the panel to be narrower than it is tall.
	if([self originCorner] == PGMaxXMinYCorner) frame.origin.x = NSMaxX(aRect) - scaledMarginSize - NSWidth(frame);
	return frame;
}

@end
