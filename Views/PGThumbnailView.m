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
#import "PGThumbnailView.h"
#import <tgmath.h>

// Views
#import "PGClipView.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"
#import "PGDocumentController.h"	//	PGShowFileNameOnImageThumbnailKey PGShowCountsAndSizesOnContainerThumbnailKey

//extern	void	Unpack2HalfUInts(NSUInteger packed, NSUInteger* upper, NSUInteger* lower);
extern	void	Unpack_ByteSize_FolderImageCounts(uint64_t packed, uint64_t* byteSize,
												  NSUInteger* folders, NSUInteger* images);

#define PGBackgroundHoleWidth 7.0f
#define PGBackgroundHoleHeight 5.0f
#define PGBackgroundHoleSpacingWidth 3.0f
#define PGBackgroundHoleSpacingHeight 8.0f
#define PGBackgroundHeight (PGBackgroundHoleHeight + PGBackgroundHoleSpacingHeight)
#define PGThumbnailSize 128.0f
#define PGThumbnailMarginWidth (PGBackgroundHoleWidth + PGBackgroundHoleSpacingWidth * 2.0f)
#define PGThumbnailMarginHeight 2.0f
#define PGThumbnailTotalHeight (PGThumbnailSize + PGThumbnailMarginHeight * 2.0f)
#define PGInnerTotalWidth (PGThumbnailSize + PGThumbnailMarginWidth * 2.0f)
#define PGOuterTotalWidth (PGInnerTotalWidth + 2.0f)

typedef enum {
	PGBackgroundDeselected,
	PGBackgroundSelectedActive,
	PGBackgroundSelectedInactive,
	PGBackgroundCount,
} PGBackgroundType;
static NSColor *PGBackgroundColors[PGBackgroundCount];

@interface PGThumbnailView(Private)

- (void)_validateSelection;
- (NSColor *)_backgroundColorWithType:(PGBackgroundType)type;

@end

static void PGGradientCallback(void *info, CGFloat const *inData, CGFloat *outData)
{
	outData[0] = (0.25f - pow(inData[0] - 0.5f, 2.0f)) / 2.0f + 0.1f;
	outData[1] = 0.95f;
}

static void PGDrawGradient(void)
{
	static CGShadingRef shade = NULL;
	if(!shade) {
		CGColorSpaceRef const colorSpace = CGColorSpaceCreateDeviceGray();
		CGFloat const domain[] = {0.0f, 1.0f};
		CGFloat const range[] = {0.0f, 1.0f, 0.0f, 1.0f};
		CGFunctionCallbacks const callbacks = {0, PGGradientCallback, NULL};
		CGFunctionRef const function = CGFunctionCreate(NULL, 1, domain, 2, range, &callbacks);
		shade = CGShadingCreateAxial(colorSpace, CGPointMake(0.0f, 0.0f), CGPointMake(PGInnerTotalWidth, 0.0f), function, NO, NO);
		CFRelease(function);
		CFRelease(colorSpace);
	}
	CGContextDrawShading([[NSGraphicsContext currentContext] CGContext], shade);
}

typedef struct MeasuredText {
	NSRange		glyphRange;
	NSSize		size;
	CGVector	margins;
} MeasuredText;

static
void
MeasureTextInBubble(NSString *label,
	BOOL enabled, NSMutableDictionary *attributes, // NSColor *backGroundColor,
	NSTextStorage *textStorage, NSLayoutManager *layoutManager,
	NSTextContainer *textContainer, MeasuredText* outMeasuredText) {
	//	while disabledControlTextColor can be used, it's much harder
	//	to read so controlTextColor is used for disabled items
	attributes[NSForegroundColorAttributeName] = enabled ?
				NSColor.controlTextColor : //alternateSelectedControlTextColor :
				NSColor.controlTextColor; // disabledControlTextColor;
//	[attributes setObject:enabled ? [NSColor alternateSelectedControlTextColor] : [NSColor disabledControlTextColor]
//					forKey:NSForegroundColorAttributeName];

	textStorage.mutableString.string	=	label;
	[textStorage setAttributes:attributes range:NSMakeRange(0, textStorage.length)];
//textContainer.containerSize	=	NSMakeSize(PGThumbnailSize - 12.0f, PGThumbnailSize - 8.0f);
	//	*** -glyphRangeForTextContainer: MUST PRECEDE THE CALL TO -usedRectForTextContainer: ***
	outMeasuredText->glyphRange	=	[layoutManager glyphRangeForTextContainer:textContainer];
	// We center the text in the text container, so the
	// final size has to be the right width.
	outMeasuredText->size		=	textContainer.containerSize	=
									[layoutManager usedRectForTextContainer:textContainer].size;
	outMeasuredText->margins	=	CGVectorMake(-4.0f, -2.0f);
}

static
bool	//	returns true if text will fit inside the given frameSize
Measure2TextIn2Bubbles(NSString *label1, NSString *label2,
	BOOL enabled, NSMutableDictionary *attributes, // NSColor *backGroundColor,
	NSTextStorage *textStorage, NSLayoutManager *layoutManager,
	NSTextContainer *textContainer,
	NSSize frameSize, CGFloat verticalGapBetweenLabels,
	MeasuredText* outMeasuredText1, MeasuredText* outMeasuredText2) {
	textContainer.containerSize	=	frameSize;
	MeasureTextInBubble(label1, enabled, attributes, textStorage, layoutManager, textContainer, outMeasuredText1);

	textContainer.containerSize	=	frameSize;
	MeasureTextInBubble(label2, enabled, attributes, textStorage, layoutManager, textContainer, outMeasuredText2);

	const CGFloat upperH = outMeasuredText1->size.height - 2 * outMeasuredText1->margins.dy;
	const CGFloat lowerH = outMeasuredText2->size.height - 2 * outMeasuredText2->margins.dy;
	const CGFloat totalH = upperH + lowerH + verticalGapBetweenLabels;
	return totalH <= frameSize.height;
}

static
void
DrawTextInBubbleBy(NSColor *backGroundColor, NSRect frame,
	CGFloat dy, NSLayoutManager *layoutManager,
	const MeasuredText* measuredText) {
	NSRect const labelRect = NSIntegralRect(NSMakeRect(
								NSMidX(frame) - measuredText->size.width / 2.0f,
								NSMidY(frame) + dy,
								measuredText->size.width, measuredText->size.height));

	[[(backGroundColor ? backGroundColor : NSColor.controlBackgroundColor) colorWithAlphaComponent:0.6f] set];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSInsetRect(labelRect, measuredText->margins.dx, measuredText->margins.dy)
								 cornerRadius:6.0f] fill];

	[layoutManager drawGlyphsForGlyphRange:measuredText->glyphRange
								   atPoint:labelRect.origin];
}

typedef enum BubblePosition {
	BubblePositionAbove,
	BubblePositionMiddle,
	BubblePositionBelow,

	BubblePositionFrameTop,
	BubblePositionFrameBottom
} BubblePosition;

static
void
DrawTextInBubbleAtPos(NSColor *backGroundColor, NSRect frame,
	BubblePosition pos, NSLayoutManager *layoutManager,
	const MeasuredText* measuredText) {
	CGFloat	dy = measuredText->size.height;
	switch(pos) {
	case BubblePositionAbove:		dy	=	-dy;	break;
	case BubblePositionMiddle:		dy	/=	-2;		break;
	case BubblePositionBelow:		dy	/=	2;		break;
	case BubblePositionFrameTop:	dy	=	NSHeight(frame) / -2;		break;
	case BubblePositionFrameBottom:	dy	=	NSHeight(frame) / 2 - dy;	break;
	}
	DrawTextInBubbleBy(backGroundColor, frame, dy, layoutManager, measuredText);
}

static
bool	//	returns true if text will fit inside the given frameSize
DrawTextInBubble(NSString *label, NSColor *backGroundColor,
	NSMutableDictionary *attributes, BOOL enabled, NSRect frame,
	BubblePosition pos, NSTextStorage *textStorage,
	NSLayoutManager *layoutManager, NSTextContainer *textContainer) {
	MeasuredText	mt;
	textContainer.containerSize	=	frame.size;
	MeasureTextInBubble(label, enabled, attributes, textStorage,
						layoutManager, textContainer, &mt);
	const CGFloat	totalH = mt.size.height - 2 * mt.margins.dy;
	const bool		fits = totalH <= frame.size.height;
	if(fits)
		DrawTextInBubbleAtPos(backGroundColor, frame, pos,
							  layoutManager, &mt);
	return fits;
}

static
char*
DecimalDigitsChars(uint64_t n, int nDigits, char buf[4]) {
	assert(nDigits > 0 && nDigits < 4);

	uint64_t	factor	=	1u;
	for(int i=nDigits; --i; )
		factor	*=	10u;

	char*	p	=	buf;
	for(int i=nDigits; i--; ) {
		uint64_t	digit	=	n / factor;
		*p++	=	'0' + (char) digit;

		n		-=	digit * factor;
		factor	/=	10u;
		assert(0 != factor || 0 == i);
	}

	*p	=	'\0';
	return buf;
}

static
NSString*
MakeByteSizeStringWithUnit(uint64_t byte_unit_1, char unit, uint64_t bytes, int nDecimalDigits) {
	const uint64_t	unitBytes = bytes / byte_unit_1;

	if(nDecimalDigits > 0) {
		uint64_t	factor	=	1u;
		for(int i=nDecimalDigits; i--; )
			factor	*=	10u;

		char	buf[4];
		return [NSString stringWithFormat:@"%llu.%s %ciB", unitBytes,
				DecimalDigitsChars((bytes - unitBytes * byte_unit_1) * factor / byte_unit_1, nDecimalDigits, buf), unit];
	}

	if(bytes < 10u * byte_unit_1)
		return [NSString stringWithFormat:@"%llu.%llu %ciB", unitBytes, (bytes - unitBytes * byte_unit_1) * 10u / byte_unit_1, unit];
	else
		return [NSString stringWithFormat:@"%llu %ciB", unitBytes, unit];
}

static
NSString*
MakeByteSizeString(uint64_t bytes, int nDecimalDigits) {
	static const uint64_t	kiB_1	=	1024u;
	static const uint64_t	MiB_1	=	1024u * 1024u;
	static const uint64_t	GiB_1	=	1024u * 1024u * 1024u;
	static const uint64_t	TiB_1	=	1024ul * 1024ul * 1024ul * 1024ul;

	if(bytes < kiB_1)
		return [NSString stringWithFormat:@"%llu B", bytes];

	if(bytes < MiB_1)
		return MakeByteSizeStringWithUnit(kiB_1, 'k', bytes, nDecimalDigits);

	if(bytes < GiB_1)
		return MakeByteSizeStringWithUnit(MiB_1, 'M', bytes, nDecimalDigits);

	if(bytes < TiB_1)
		return MakeByteSizeStringWithUnit(GiB_1, 'G', bytes, nDecimalDigits);

//	if(bytes < PiB_1)	//	peta??
		return MakeByteSizeStringWithUnit(TiB_1, 'T', bytes, nDecimalDigits);
}

@implementation PGThumbnailView

#pragma mark -PGThumbnailView

@synthesize dataSource;
@synthesize delegate;
@synthesize representedObject;
@synthesize thumbnailOrientation = _thumbnailOrientation;
- (void)setThumbnailOrientation:(PGOrientation)orientation
{
	if(orientation == _thumbnailOrientation) return;
	_thumbnailOrientation = orientation;
	[self setNeedsDisplay:YES];
}
@synthesize items = _items;
@synthesize selection = _selection;
- (void)setSelection:(NSSet *)items
{
	if(items == _selection) return;
	NSMutableSet *const removedItems = [[_selection mutableCopy] autorelease];
	[removedItems minusSet:items];
	for(id const removedItem in removedItems) [self setNeedsDisplayInRect:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:removedItem] withMargin:YES]];
	NSMutableSet *const addedItems = [[items mutableCopy] autorelease];
	[addedItems minusSet:_selection];
	for(id const addedItem in addedItems) [self setNeedsDisplayInRect:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:addedItem] withMargin:YES]];
	[_selection setSet:items];
	[self _validateSelection];
	[self scrollToSelectionAnchor];
	[[self delegate] thumbnailViewSelectionDidChange:self];
}
@synthesize selectionAnchor = _selectionAnchor;
- (void)selectItem:(id)item byExtendingSelection:(BOOL)flag
{
	if(!item) return;
	BOOL const can = [[self dataSource] thumbnailView:self canSelectItem:item];
	if(!can) {
		if(!flag) [self setSelection:[NSSet set]];
		return;
	}
	if(!flag) {
		[_selection removeAllObjects];
		[self setNeedsDisplay:YES];
	}
	[_selection addObject:item];
	_selectionAnchor = item;
	NSRect const itemFrame = [self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:item] withMargin:YES];
	if(flag) [self setNeedsDisplayInRect:itemFrame];
	[self PG_scrollRectToVisible:itemFrame type:PGScrollLeastToRect];
	[[self delegate] thumbnailViewSelectionDidChange:self];
}
- (void)deselectItem:(id)item
{
	if(!item || ![_selection containsObject:item]) return;
	[_selection removeObject:item];
	if(item == _selectionAnchor) [self _validateSelection];
	[self setNeedsDisplayInRect:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:item] withMargin:YES]];
	[[self delegate] thumbnailViewSelectionDidChange:self];
}
- (void)toggleSelectionOfItem:(id)item
{
	if([_selection containsObject:item]) [self deselectItem:item];
	else [self selectItem:item byExtendingSelection:YES];
}
- (void)moveUp:(BOOL)up byExtendingSelection:(BOOL)ext
{
	NSUInteger const count = [_items count];
	if(!count) return;
	if(!_selectionAnchor) return [self selectItem:up ? [_items lastObject] : [_items objectAtIndex:0] byExtendingSelection:NO];
	NSUInteger const i = [_items indexOfObjectIdenticalTo:_selectionAnchor];
	NSParameterAssert(NSNotFound != i);
	NSArray *const items = [_items subarrayWithRange:up ? NSMakeRange(0, i) : NSMakeRange(i + 1, count - i - 1)];
	for(id const item in up ? (id<NSFastEnumeration>)[items reverseObjectEnumerator] : (id<NSFastEnumeration>)items) {
		if(![[self dataSource] thumbnailView:self canSelectItem:item]) continue;
		if([_selection containsObject:item]) [self deselectItem:_selectionAnchor];
		[self selectItem:item byExtendingSelection:ext];
		break;
	}
}

#pragma mark -

- (NSUInteger)indexOfItemAtPoint:(NSPoint)p
{
	return floor(p.y / PGThumbnailTotalHeight);
}
- (NSRect)frameOfItemAtIndex:(NSUInteger)index withMargin:(BOOL)flag
{
	NSRect frame = NSMakeRect(PGThumbnailMarginWidth, index * PGThumbnailTotalHeight + PGThumbnailMarginHeight, PGThumbnailSize, PGThumbnailSize);
	return flag ? NSInsetRect(frame, -PGThumbnailMarginWidth, -PGThumbnailMarginHeight) : frame;
}

#pragma mark -

- (void)reloadData
{
	BOOL const hadSelection = !![_selection count];
	[_items release];
	_items = [[[self dataSource] itemsForThumbnailView:self] copy];
	[self _validateSelection];
	[self sizeToFit];
	[self scrollToSelectionAnchor];
	[self setNeedsDisplay:YES];
	if(hadSelection) [[self delegate] thumbnailViewSelectionDidChange:self];
}
- (void)sizeToFit
{
	CGFloat const height = [self superview] ? NSHeight([[self superview] bounds]) : 0.0f;
	[super setFrameSize:NSMakeSize(PGOuterTotalWidth, MAX(height, [_items count] * PGThumbnailTotalHeight))];
}
- (void)scrollToSelectionAnchor
{
	NSUInteger const i = [_items indexOfObjectIdenticalTo:_selectionAnchor];
	if(NSNotFound != i) [self PG_scrollRectToVisible:[self frameOfItemAtIndex:i withMargin:YES] type:PGScrollCenterToRect];
}

#pragma mark -

- (void)windowDidChangeKey:(NSNotification *)aNotif
{
	[self setNeedsDisplay:YES];
}
- (void)systemColorsDidChange:(NSNotification *)aNotif
{
	NSUInteger i = PGBackgroundCount;
	while(i--) {
		[PGBackgroundColors[i] release];
		PGBackgroundColors[i] = nil;
	}
	[self setNeedsDisplay:YES];
}

#pragma mark -PGThumbnailView(Private)

- (void)_validateSelection
{
	for(id const selectedItem in [[_selection copy] autorelease]) if([_items indexOfObjectIdenticalTo:selectedItem] == NSNotFound) [_selection removeObject:selectedItem];
	if([_selection containsObject:_selectionAnchor]) return;
	_selectionAnchor = nil;
	for(id const anchor in _items) if([_selection containsObject:anchor]) {
		_selectionAnchor = anchor;
		break;
	}
}
- (NSColor *)_backgroundColorWithType:(PGBackgroundType)type
{
	if(PGBackgroundColors[type]) return PGBackgroundColors[type];
	NSImage *const background = [[[NSImage alloc] initWithSize:NSMakeSize(PGOuterTotalWidth, PGBackgroundHeight)] autorelease];
	[background lockFocus];

	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[shadow setShadowBlurRadius:4.0f];
	[shadow set];
	CGContextRef const imageContext = [[NSGraphicsContext currentContext] CGContext];
	CGContextBeginTransparencyLayerWithRect(imageContext, CGRectMake(0, 0, PGOuterTotalWidth, PGBackgroundHeight), NULL);
	NSRect const r = NSMakeRect(0.0f, 0.0f, PGInnerTotalWidth, PGBackgroundHeight);
	PGDrawGradient();
	if(PGBackgroundDeselected != type) {
		[[PGBackgroundSelectedActive == type ? [NSColor alternateSelectedControlColor] : [NSColor secondarySelectedControlColor] colorWithAlphaComponent:0.5f] set];
		NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
	}

	NSRect const leftHoleRect = NSMakeRect(PGBackgroundHoleSpacingWidth, 0.0f, PGBackgroundHoleWidth, PGBackgroundHoleHeight);
	NSRect const rightHoleRect = NSMakeRect(PGInnerTotalWidth - PGThumbnailMarginWidth + PGBackgroundHoleSpacingWidth, 0.0f, PGBackgroundHoleWidth, PGBackgroundHoleHeight);
	[[NSColor colorWithDeviceWhite:1.0f alpha:0.2f] set];
	[[NSBezierPath PG_bezierPathWithRoundRect:leftHoleRect cornerRadius:2.0f] fill];
	[[NSBezierPath PG_bezierPathWithRoundRect:rightHoleRect cornerRadius:2.0f] fill];
	[[NSColor clearColor] set];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(leftHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] PG_fillUsingOperation:NSCompositingOperationCopy];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(rightHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] PG_fillUsingOperation:NSCompositingOperationCopy];

	CGContextEndTransparencyLayer(imageContext);
	[background unlockFocus];
	NSColor *const color = [NSColor colorWithPatternImage:background];
	PGBackgroundColors[type] = [color retain];
	return color;
}

#pragma mark -NSView

- (id)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_selection = (NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(systemColorsDidChange:)
												   name:NSSystemColorsDidChangeNotification
												 object:nil];

		//	2022/10/15
		[NSUserDefaults.standardUserDefaults addObserver:self
											  forKeyPath:PGShowFileNameOnImageThumbnailKey
												 options:kNilOptions
												 context:NULL];
		[NSUserDefaults.standardUserDefaults addObserver:self
											  forKeyPath:PGShowCountsAndSizesOnContainerThumbnailKey
												 options:kNilOptions
												 context:NULL];
	}
	return self;
}

#pragma mark -

- (BOOL)isFlipped
{
	return YES;
}
- (BOOL)isOpaque
{
	return YES;
}
- (void)setUpGState
{
	[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
}
- (void)drawRect:(NSRect)aRect
{
	CGContextRef const context = [[NSGraphicsContext currentContext] CGContext];

	NSRect const patternRect = [self convertRect:[self bounds] toView:nil];
	CGContextSetPatternPhase(context, CGSizeMake(NSMinX(patternRect), floor(NSMaxY(patternRect) - PGBackgroundHoleHeight / 2.0f)));

	NSInteger count = 0;
	NSRect const *rects = NULL;
	[self getRectsBeingDrawn:&rects count:&count];

	[[self _backgroundColorWithType:PGBackgroundDeselected] set];
	NSRectFillList(rects, count);

	NSShadow *const nilShadow = [[[NSShadow alloc] init] autorelease];
	[nilShadow setShadowColor:nil];
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[shadow setShadowBlurRadius:4.0f];
	[shadow set];

	const BOOL	showCountsAndSizesOnContainerThumbnail =
		[NSUserDefaults.standardUserDefaults boolForKey:PGShowCountsAndSizesOnContainerThumbnailKey];
	NSUInteger i = 0;
	for(; i < [_items count]; i++) {
		NSRect const frameWithMargin = [self frameOfItemAtIndex:i withMargin:YES];
		if(!PGIntersectsRectList(frameWithMargin, rects, count)) continue;
		id const item = [_items objectAtIndex:i];
		if([_selection containsObject:item]) {
			[nilShadow set];
			[[self _backgroundColorWithType:[self PG_isActive] ? PGBackgroundSelectedActive : PGBackgroundSelectedInactive] set];
		//	[NSColor.yellowColor set];
			NSRectFill(frameWithMargin);
			[shadow set];
		}
		NSImage *const thumb = [[self dataSource] thumbnailView:self thumbnailForItem:item];
		if(!thumb) {
			[NSBezierPath PG_drawSpinnerInRect:NSInsetRect([self frameOfItemAtIndex:i withMargin:NO], 20.0f, 20.0f)
								  startAtPetal:-1];
			continue;
		}
		NSSize originalSize = [thumb size];
		if(PGRotated90CCW & _thumbnailOrientation) originalSize = NSMakeSize(originalSize.height, originalSize.width);
		NSRect const frame = [self frameOfItemAtIndex:i withMargin:NO];
		NSRect const thumbnailRect = PGIntegralRect(PGCenteredSizeInRect(PGScaleSizeByFloat(originalSize, MIN(1, MIN(NSWidth(frame) / originalSize.width, NSHeight(frame) / originalSize.height))), frame));
		BOOL const enabled = [[self dataSource] thumbnailView:self canSelectItem:item];

		NSRect const highlight = [self dataSource] ? [[self dataSource] thumbnailView:self highlightRectForItem:item] : NSZeroRect;
		BOOL const entirelyHighlighted = NSEqualRects(highlight, NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f));
		if(!entirelyHighlighted) {
			CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(thumbnailRect), NULL);
			[nilShadow set];
		}
		NSRect transformedThumbnailRect = thumbnailRect;
		NSAffineTransform *const transform = [NSAffineTransform PG_transformWithRect:&transformedThumbnailRect orientation:[[self dataSource] thumbnailView:self shouldRotateThumbnailForItem:item] ? PGAddOrientation(_thumbnailOrientation, PGFlippedVert) : PGFlippedVert]; // Also flip it vertically because our view is flipped and -drawInRect:… ignores that.
		[transform concat];
		[thumb drawInRect:transformedThumbnailRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:enabled ? 1.0f : 0.33f];
		[transform invert];
		[transform concat];
		if(!entirelyHighlighted) {
			NSRect rects[4];
			NSUInteger count = 0;
			NSRect const r = NSIntersectionRect(thumbnailRect, PGIntegralRect(NSOffsetRect(PGScaleRect(highlight, NSWidth(thumbnailRect), NSHeight(thumbnailRect)), NSMinX(thumbnailRect), NSMinY(thumbnailRect))));
			PGGetRectDifference(rects, &count, thumbnailRect, r);
			[[NSColor colorWithDeviceWhite:0.0f alpha:0.5f] set];
			NSRectFillListUsingOperation(rects, count, NSCompositingOperationSourceAtop);
			CGContextEndTransparencyLayer(context);
			[nilShadow set];
			[[NSColor whiteColor] set];
			NSFrameRect(r);
			[shadow set];
		}

		NSString *const label = [[self dataSource] thumbnailView:self labelForItem:item];
		NSColor *const labelColor = [[self dataSource] thumbnailView:self labelColorForItem:item];
		if(label) {
			[nilShadow set];
			static NSMutableDictionary *attributes = nil;
			static CGFloat fontLineHeight = 0;
			if(!attributes) {
				NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
				[style setLineBreakMode:NSLineBreakByWordWrapping];
				[style setAlignment:NSTextAlignmentCenter];
				NSShadow *const textShadow = [[[NSShadow alloc] init] autorelease];
				[textShadow setShadowBlurRadius:2.0f];
				[textShadow setShadowOffset:NSMakeSize(0.0f, -1.0f)];
				NSFont *font = [NSFont systemFontOfSize:11];
				attributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:textShadow, NSShadowAttributeName,
							  font, NSFontAttributeName, style, NSParagraphStyleAttributeName, nil];

				fontLineHeight = ceil(font.ascender - font.descender);
			}

#if 1
			//	this is now done inside MeasureTextInBubble()
#else
			//	while disabledControlTextColor can be used, it's much harder
			//	to read so controlTextColor is used for disabled items
			attributes[NSForegroundColorAttributeName] = enabled ?
						NSColor.controlTextColor : //alternateSelectedControlTextColor :
						NSColor.controlTextColor; // disabledControlTextColor;
		//	[attributes setObject:enabled ? [NSColor alternateSelectedControlTextColor] : [NSColor disabledControlTextColor]
		//					forKey:NSForegroundColorAttributeName];
#endif

			static NSTextStorage *textStorage = nil;
			static NSLayoutManager *layoutManager = nil;
			static NSTextContainer *textContainer = nil;
			if(!textStorage) {
				textStorage = [[NSTextStorage alloc] init];
				layoutManager = [[NSLayoutManager alloc] init];
				textContainer = [[NSTextContainer alloc] init];
				[layoutManager addTextContainer:[textContainer autorelease]];
				[textStorage addLayoutManager:[layoutManager autorelease]];
				[textContainer setLineFragmentPadding:0];
			}

#if 1	//	v5: 2 bubbles, no need for localized strings, can work on 10.14 (does not rely on 11.x APIs),
		//	and supports text bubble fitting into the smallest rectangle possible
			uint64_t const byteSizeAndFolderAndImageCount = [self.dataSource thumbnailView:self
									   byteSizeAndFolderAndImageCountOfDirectChildrenForItem:item];
			if(!showCountsAndSizesOnContainerThumbnail ||
			   byteSizeAndFolderAndImageCount == ULONG_MAX ||
			   0 == byteSizeAndFolderAndImageCount) {
				BOOL hasRealThumbnail = [self.dataSource thumbnailView:self shouldRotateThumbnailForItem:item];
//frameWithMargin.size;//NSMakeSize(PGThumbnailSize - 12.0f, PGThumbnailSize - 8.0f);
				//	try various rectangles for the label to be rendered into, from the smallest to the largest
				if(!DrawTextInBubble(label, labelColor, attributes, enabled, NSMakeRect(frame.origin.x + 6.0f,
									 frame.origin.y + 4.0f, frame.size.width - 12.0f, frame.size.height - 8.0f),
									 hasRealThumbnail ? BubblePositionFrameBottom : BubblePositionMiddle,
									 textStorage, layoutManager, textContainer) &&
				   !DrawTextInBubble(label, labelColor, attributes, enabled, frame,
									 hasRealThumbnail ? BubblePositionFrameBottom : BubblePositionMiddle,
									 textStorage, layoutManager, textContainer))
					(void) DrawTextInBubble(label, labelColor, attributes, enabled, frameWithMargin,
											hasRealThumbnail ? BubblePositionFrameBottom : BubblePositionMiddle,
											textStorage, layoutManager, textContainer);
			/*	if(hasRealThumbnail) {	//	image
					/ *	if there is room underneath the thumbnail to display the file name, do so
					MeasuredText	theMT;
					MeasureTextInBubble(label, enabled, attributes, textStorage, layoutManager, textContainer, &theMT);

					NSString* s = [NSString stringWithFormat:@"th_space %5.2f    mt_height %5.2f",
								   frame.size.height - thumbnailRect.size.height, theMT.size.height];
					DrawTextInBubble(s, labelColor, attributes, enabled, frame, BubblePositionFrameBottom,
									 textStorage, layoutManager, textContainer);
				}	*/
			/*	if(!hasRealThumbnail) {	//	folder
					DrawTextInBubble(label, labelColor, attributes, enabled, frame, BubblePositionMiddle,
									 textStorage, layoutManager, textContainer);	*/
			} else {
				uint64_t	byteSize;
				NSUInteger	folderCount = 0, imageCount = 0;
				Unpack_ByteSize_FolderImageCounts(byteSizeAndFolderAndImageCount, &byteSize,
												  &folderCount, &imageCount);
				NSMutableString*	s = [NSMutableString string]; // [[NSMutableString new] autorelease];
				if(0 != folderCount) {
					[s appendFormat:@"%lu 📂", folderCount];
				}
				if(0 != imageCount) {
					if(0 != folderCount)
						[s appendString:@" "];	//	[s appendString:@" │ "];

//#define	STRING_IMAGE_ICON	"□"		//	WHITE SQUARE	Unicode: U+25A1, UTF-8: E2 96 A1
#define	STRING_IMAGE_ICON	"❑"		//	LOWER RIGHT SHADOWED WHITE SQUARE	Unicode: U+2751, UTF-8: E2 9D 91
//#define	STRING_IMAGE_ICON	"▢"		//	WHITE SQUARE WITH ROUNDED CORNERS	Unicode: U+25A2, UTF-8: E2 96 A2
//#define	STRING_IMAGE_ICON	"🏞"	//	national park Unicode: U+1F3DE, UTF-8: F0 9F 8F 9E
//#define	STRING_IMAGE_ICON	"🖼"	//	frame with picture	Unicode: U+1F5BC, UTF-8: F0 9F 96 BC
					[s appendFormat:@"%lu "STRING_IMAGE_ICON" ", imageCount];

					//	if possible, display the size with as many decimal digits as
					//	possible (with a max. of 2) on a single line; if the text needs
					//	more than a single line, fall back to using the default number of
					//	decimal digits, which is 0 digits if the string shows more than or
					//	equal to 10 <units> or 1 digit if the string shows less than 10 <units>,
					//	eg, 12kiB or 9.3MiB (the default string is achieved by passing -1)
					NSMutableString*	finalStr	=	nil;
					for(int nDecimalDigits = 3; nDecimalDigits--; ) @autoreleasepool {
						NSMutableString*	test	=	[NSMutableString stringWithFormat:@"%@%@",
														 s, MakeByteSizeString(byteSize, nDecimalDigits)];
						MeasuredText	testMT;
						MeasureTextInBubble(test, enabled, attributes, textStorage, layoutManager, textContainer, &testMT);
						if(testMT.size.height <= fontLineHeight) {
							finalStr	=	[test retain];
							break;
						}
					}
					if(finalStr)
						s	=	[finalStr autorelease];
					else
						s	=	[NSMutableString stringWithFormat:@"%@%@", s, MakeByteSizeString(byteSize, -1)];
				}
				assert(0 != s.length);

				MeasuredText	lowerMT;
				MeasuredText	upperMT;
#define UPPER_LOWER_GAP 2.0f
				//	try various rectangles for the label and metadata to be rendered into,
				//	from the smallest to the largest
				if (!Measure2TextIn2Bubbles(s, label, enabled, attributes, textStorage,
											layoutManager, textContainer,
											NSMakeSize(frame.size.width - 12.0f,
													   frame.size.height - 8.0f),
											UPPER_LOWER_GAP, &lowerMT, &upperMT) &&
					!Measure2TextIn2Bubbles(s, label, enabled, attributes, textStorage,
											layoutManager, textContainer, frame.size,
											UPPER_LOWER_GAP, &lowerMT, &upperMT))
					(void) Measure2TextIn2Bubbles(s, label, enabled, attributes, textStorage,
												  layoutManager, textContainer, frameWithMargin.size,
												  UPPER_LOWER_GAP, &lowerMT, &upperMT);

				//	now ready to draw into the smallest bubble possible...
				const CGFloat upperH = upperMT.size.height - 2 * upperMT.margins.dy;
				const CGFloat lowerH = lowerMT.size.height - 2 * lowerMT.margins.dy;
				const CGFloat totalH = upperH + lowerH + UPPER_LOWER_GAP;
				CGFloat dy = totalH * -0.5f;
#define BOTTOM_GAP 8.0f
				if((frame.size.height * -0.5f) + BOTTOM_GAP < dy)	//	is there enough space to shift the bubbles down?
#define BUBBLE_DOWN_SHIFT 8.0f
					dy	+=	BUBBLE_DOWN_SHIFT;

				//	always draw folder name first because its rectangle is vertically larger than the metadata's rect
				DrawTextInBubbleBy(labelColor, frame, dy, layoutManager, &upperMT);

				//	need to reset layoutManager and textContainer before drawing metadata (lower) string
				//	(no need to reset textContainer.containerSize because its rect is smaller than label's rect)
				MeasureTextInBubble(s, enabled, attributes, textStorage, layoutManager, textContainer, &lowerMT);
				DrawTextInBubbleBy(labelColor, frame, dy + upperH + UPPER_LOWER_GAP, layoutManager, &lowerMT);
			}
#elif 1	//	v4: 2 bubbles, no need for localized strings, can work on 10.14 (does not rely on 11.x APIs)
			NSUInteger const folderAndImageCount = [self.dataSource thumbnailView:self
										 folderAndImageDirectChildrenCountForItem:item];
			if(folderAndImageCount == NSUIntegerMax || 0 == folderAndImageCount) {
				DrawTextInBubble(label, labelColor, attributes, enabled, frame, BubblePositionMiddle,
								 textStorage, layoutManager, textContainer);
			} else {
				NSUInteger	folderCount = 0, imageCount = 0;
				Unpack2HalfUInts(folderAndImageCount, &folderCount, &imageCount);
				NSMutableString*	s = [[NSMutableString new] autorelease];
				if(0 != folderCount)
					[s appendFormat:@"📂 %lu", folderCount];
				if(0 != imageCount) {
					if(0 != folderCount)
						[s appendString:@"  "];
					[s appendFormat:@"🖼 %lu", imageCount];
				}
				assert(0 != s.length);

				MeasuredText	lowerMT, upperMT;
				MeasureTextInBubble(s, enabled, attributes, textStorage, layoutManager, textContainer, &lowerMT);

				MeasureTextInBubble(label, enabled, attributes, textStorage, layoutManager, textContainer, &upperMT);

				const CGFloat upperH = upperMT.size.height - 2 * upperMT.margins.dy;
				const CGFloat lowerH = lowerMT.size.height - 2 * lowerMT.margins.dy;
#define UPPER_LOWER_GAP 2.0f
				const CGFloat totalH = upperH + lowerH + UPPER_LOWER_GAP;
				CGFloat dy = totalH / -2.0f;
#define BOTTOM_GAP 8.0f
				if((PGThumbnailSize / -2.0f) + BOTTOM_GAP < dy)	//	is there enough space to shift the bubbles down?
#define BUBBLE_DOWN_SHIFT 8.0f
					dy	+=	BUBBLE_DOWN_SHIFT;
				DrawTextInBubbleBy(labelColor, frame, dy, layoutManager, &upperMT);

				//	need to reset layoutManager and textContainer before drawing lower string
				MeasureTextInBubble(s, enabled, attributes, textStorage, layoutManager, textContainer, &lowerMT);
				DrawTextInBubbleBy(labelColor, frame, dy + upperH + UPPER_LOWER_GAP, layoutManager, &lowerMT);
			}
#elif 1	//	v3: 2 bubbles (needs localized strings but those strings are now removed from the .strings file)
			NSInteger const childCount = [self.dataSource thumbnailView:self directChildrenCountForItem:item];

			DrawTextInBubble(label, labelColor, attributes, enabled, frame,
							 NSNotFound != childCount ? BubblePositionAbove : BubblePositionMiddle,
							 textStorage, layoutManager, textContainer);
			if(NSNotFound != childCount) {
				NSString* formattedMessage = nil;
				if(!childCount)
					formattedMessage = NSLocalizedString(@"empty", @"(empty)");
				else if(1 == childCount)
					formattedMessage = NSLocalizedString(@"1 item", @"1 item");
				else
					formattedMessage = NSLocalizedString(@"%lu items", @"%lu items");

				DrawTextInBubble([NSString stringWithFormat:formattedMessage, childCount],
								 labelColor, attributes, enabled, frame, BubblePositionBelow,
								 textStorage, layoutManager, textContainer);
			}
#elif 1	//	v2: moved into a function
			DrawTextInBubble(label, labelColor, attributes, enabled, frame, BubblePositionMiddle,
							 textStorage, layoutManager, textContainer);
#else	//	v1: original code
			(void)DrawTextInBubble;
			[[textStorage mutableString] setString:label];
			[textStorage setAttributes:attributes range:NSMakeRange(0, [textStorage length])];
			textContainer.containerSize	=	NSMakeSize(PGThumbnailSize - 12.0f, PGThumbnailSize - 8.0f);
			NSRange const glyphRange = [layoutManager glyphRangeForTextContainer:textContainer];
			NSSize const labelSize = [layoutManager usedRectForTextContainer:textContainer].size;
			[textContainer setContainerSize:labelSize]; // We center the text in the text container, so the final size has to be the right width.
			NSRect const labelRect = NSIntegralRect(NSMakeRect(NSMidX(frame) - labelSize.width / 2.0f, NSMidY(frame) - labelSize.height / 2.0f, labelSize.width, labelSize.height));
			[[(labelColor ? labelColor : NSColor.controlBackgroundColor) colorWithAlphaComponent:0.5f] set];
			[[NSBezierPath PG_bezierPathWithRoundRect:NSInsetRect(labelRect, -4.0f, -2.0f) cornerRadius:6.0f] fill];
			[layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:labelRect.origin];
#endif
			[shadow set];
		} else if(labelColor) {
			NSRect const labelRect = NSMakeRect(NSMaxX(frame) - 16.0f, round(MAX(NSMaxY(thumbnailRect) - 16.0f, NSMidY(thumbnailRect) - 6.0f)), 12.0f, 12.0f);
			[NSGraphicsContext saveGraphicsState];
			CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(NSInsetRect(labelRect, -5.0f, -5.0f)), NULL);
			NSBezierPath *const labelDot = [NSBezierPath bezierPathWithOvalInRect:labelRect];
			[labelColor set];
			[labelDot fill];
			[[NSColor whiteColor] set];
			[labelDot setLineWidth:2.0f];
			[labelDot stroke];
			CGContextEndTransparencyLayer(context);
			[NSGraphicsContext restoreGraphicsState];
		}
	}
	[nilShadow set];
}

#pragma mark -

- (void)setFrameSize:(NSSize)oldSize
{
	[self sizeToFit];
}
- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
	[[self window] PG_removeObserver:self name:NSWindowDidBecomeKeyNotification];
	[[self window] PG_removeObserver:self name:NSWindowDidResignKeyNotification];
	[aWindow PG_addObserver:self selector:@selector(windowDidChangeKey:) name:NSWindowDidBecomeKeyNotification];
	[aWindow PG_addObserver:self selector:@selector(windowDidChangeKey:) name:NSWindowDidResignKeyNotification];
}

#pragma mark -NSView(PGClipViewAdditions)

- (BOOL)PG_acceptsClicksInClipView:(PGClipView *)sender
{
	return NO;
}

#pragma mark -NSResponder

- (IBAction)moveUp:(id)sender
{
	[self moveUp:YES byExtendingSelection:NO];
}
- (IBAction)moveDown:(id)sender
{
	[self moveUp:NO byExtendingSelection:NO];
}
- (IBAction)moveUpAndModifySelection:(id)sender
{
	[self moveUp:YES byExtendingSelection:YES];
}
- (IBAction)moveDownAndModifySelection:(id)sender
{
	[self moveUp:NO byExtendingSelection:YES];
}
- (IBAction)selectAll:(id)sender
{
	NSMutableSet *const selection = [NSMutableSet set];
	for(id const item in _items) if([[self dataSource] thumbnailView:self canSelectItem:item]) [selection addObject:item];
	[self setSelection:selection];
}

#pragma mark -

- (BOOL)acceptsFirstResponder
{
	return YES;
}
- (BOOL)becomeFirstResponder
{
	[self setNeedsDisplay:YES];
	return [super becomeFirstResponder];
}
- (BOOL)resignFirstResponder
{
	[self setNeedsDisplay:YES];
	return [super resignFirstResponder];
}

#pragma mark -

- (void)mouseDown:(NSEvent *)anEvent
{
	NSPoint const p = [anEvent PG_locationInView:self];
	NSUInteger const i = [self indexOfItemAtPoint:p];
	id const item = [self mouse:p inRect:[self bounds]] && i < [_items count] ? [_items objectAtIndex:i] : nil;
	if([anEvent modifierFlags] & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) [self toggleSelectionOfItem:item];
	else [self selectItem:item byExtendingSelection:NO];
}
- (void)keyDown:(NSEvent *)anEvent
{
	if([anEvent modifierFlags] & NSEventModifierFlagCommand) return [super keyDown:anEvent];
	if(![[NSApp mainMenu] performKeyEquivalent:anEvent]) [self interpretKeyEvents:[NSArray arrayWithObject:anEvent]];
}

#pragma mark -NSObject

- (void)dealloc
{
	//	2022/10/15
	[NSUserDefaults.standardUserDefaults removeObserver:self forKeyPath:PGShowFileNameOnImageThumbnailKey];
	[NSUserDefaults.standardUserDefaults removeObserver:self forKeyPath:PGShowCountsAndSizesOnContainerThumbnailKey];

	[self PG_removeObserver];
	[representedObject release];
	[_items release];
	[_selection release];
	[super dealloc];
}

#pragma mark -NSObject(NSKeyValueObserving)

//	2022/10/15
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	if(PGEqualObjects(keyPath, PGShowFileNameOnImageThumbnailKey) ||
	   PGEqualObjects(keyPath, PGShowCountsAndSizesOnContainerThumbnailKey))
		self.needsDisplay	=	YES;
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end

@implementation NSObject(PGThumbnailViewDataSource)

- (NSArray *)itemsForThumbnailView:(PGThumbnailView *)sender
{
	return nil;
}
- (NSImage *)thumbnailView:(PGThumbnailView *)sender thumbnailForItem:(id)item
{
	return nil;
}
- (BOOL)thumbnailView:(PGThumbnailView *)sender canSelectItem:(id)item;
{
	return YES;
}
- (NSString *)thumbnailView:(PGThumbnailView *)sender labelForItem:(id)item
{
	return nil;
}
- (NSColor *)thumbnailView:(PGThumbnailView *)sender labelColorForItem:(id)item
{
	return nil;
}
- (NSRect)thumbnailView:(PGThumbnailView *)sender highlightRectForItem:(id)item
{
	return NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f);
}
- (BOOL)thumbnailView:(PGThumbnailView *)sender shouldRotateThumbnailForItem:(id)item
{
	return NO;
}

- (NSInteger)thumbnailView:(PGThumbnailView *)sender directChildrenCountForItem:(id)item
{
	return NSNotFound;
}

@end

@implementation NSObject(PGThumbnailViewDelegate)

- (void)thumbnailViewSelectionDidChange:(PGThumbnailView *)sender {}

@end
