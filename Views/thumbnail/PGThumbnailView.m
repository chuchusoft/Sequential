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

// Controller
#import "PGThumbnailController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"
#import "PGDocumentController.h"	//	for thumbnail userDefault keys

#if !defined(NDEBUG) && 0	//	used to fix the incorrect -[PGNode isEqual:] bug
	#import "PGNode.h"
	#import "PGResourceIdentifier.h"
#endif

//extern	void	Unpack2HalfUInts(NSUInteger packed, NSUInteger* upper, NSUInteger* lower);
extern	void	Unpack_ByteSize_FolderImageCounts(uint64_t packed, uint64_t* byteSize,
												  NSUInteger* folders, NSUInteger* images);

//	MARK: -

extern	NSInteger	GetThumbnailSizeFormat(void);

//	extern
NSInteger
GetThumbnailSizeFormat(void) {
	NSUserDefaults *sud = NSUserDefaults.standardUserDefaults;
	NSInteger	thumbnailSizeFormat = [sud integerForKey:PGThumbnailSizeFormatKey];
	NSCAssert(0 <= thumbnailSizeFormat && thumbnailSizeFormat <= 2, @"thumbnailSizeFormat");
	if(thumbnailSizeFormat < 0 || thumbnailSizeFormat > 2)
		thumbnailSizeFormat	=	0;
	return thumbnailSizeFormat;
}


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

typedef NS_ENUM(unsigned int, PGBackgroundType) {
#if 1
	PGBackground_NotSelected,

	PGBackground_Selected_Active_MainWindow,
	PGBackground_Selected_Active_NotMainWindow,
	PGBackground_Selected_ParentOfActive_MainWindow,
	PGBackground_Selected_ParentOfActive_NotMainWindow,
	PGBackground_Selected_NotActive_MainWindow,
	PGBackground_Selected_NotActive_NotMainWindow,
#else
	PGBackgroundDeselected,
	PGBackgroundSelectedActive,
	PGBackgroundSelectedInactive,
#endif
	PGBackgroundCount,
};
static NSColor *PGBackgroundColors[PGBackgroundCount];

#if __has_feature(objc_arc)

//	There are several ways to implement a public @property(copy) NSSet*
//	selection:
//	[1] use a special NSMutableSet ivar, which is what the original code
//		uses: it creates a special CFMutableSet but then disguises it as
//		a NSMutableSet*. It's special because it does not specify a
//		callbacks struct so retain, release, equal, hash, copy-description,
//		etc. are all no-ops. Con: it's not obvious that the _selection ivar
//		behaves in a non-standard manner (it has NULL callbacks).
//	[2] use a standard NSSet ivar and create/use temporary working
//		objects before assigning the final set to the ivar. Con:
//		creates/uses more memory (temporary objects).
//	[3] use a special CFMutableSetRef ivar which what the original code
//		actually creates. It's special because it does not specify a
//		callbacks struct so retain, release, equal, hash, copy-description,
//		etc. are all no-ops. Con: need more support code to get/mutate the
//		selection, but does not incur extra memory use.
//	[4] same as [1] but the ivar is named the same as [3]
//
//	[1] requires an ivar to be specified explicitly, [2], [3] and [4] can
//	use the ARC compiler to synthesize the ivar automatically. For [2], it
//	must be a NSSet - the compiler will not accept a NSMutableSet @property
//	declaration. For [3] and [4], a property with a name different from the
//	public property is used (mutableSelection) and the public property's
//	getter/setter are custom methods which use the _mutableSelection ivar.
//
//	To keep the code as identical to the original as possible, it was decided
//	to use implementation [4].

//	#define SELECTION_IVAR_ORIGINAL_NSMUTABLESET	//	impl [1]
//	#define SELECTION_IVAR_NSSET					//	impl [2]
//	#define SELECTION_IVAR_SPECIAL_CFMUTABLESET		//	impl [3]
	#define SELECTION_IVAR_SPECIAL_NSMUTABLESET		//	impl [4]

@interface PGThumbnailView ()
	#if defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
/*	The compiler will not accept this declaration:

@property (nonatomic, copy) NSMutableSet *selection;

	so the only way to make this work is to manually specify
	the actual backing ivar; this is the only place in the
	codebase which has such an ivar when compiling under ARC.
 */
{
	NSMutableSet *_selection;
}
	#elif defined(SELECTION_IVAR_NSSET)	//	[2]
//	nothing needed because the compiler will synthesize the ivar
	#elif defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
@property (nonatomic, assign) CFMutableSetRef mutableSelection;
	#elif defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
@property (nonatomic, strong) NSMutableSet *mutableSelection;
	#endif
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, weak) id selectionAnchor;

@end

#else

@interface PGThumbnailView(Private)

- (void)_validateSelection;
- (NSColor *)_backgroundColorWithType:(PGBackgroundType)type;
//	2023/08/17 made this method private; was -(void)scrollToSelectionAnchor;
- (void)_scrollToSelectionAnchor:(PGScrollToRectType)scrollToRect;

@end

#endif

//	MARK: -

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
	CGContextDrawShading([NSGraphicsContext currentContext].CGContext, shade);
}

typedef struct MeasuredText {
	NSSize		containerSize;	//	in

	NSRange		glyphRange;		//	out
	NSSize		textSize;		//	out
	CGVector	margins;		//	out
} MeasuredText;

static
void
MeasureTextInBubble(NSString *label,
	BOOL enabled, NSMutableDictionary *attributes, // NSColor *backGroundColor,
	NSTextStorage *textStorage, NSLayoutManager *layoutManager,
	NSTextContainer *textContainer, MeasuredText* inOutMeasuredText) {
	//	while disabledControlTextColor can be used, it's much harder
	//	to read so controlTextColor is used for disabled items
	attributes[NSForegroundColorAttributeName] = enabled ?
				NSColor.controlTextColor : //alternateSelectedControlTextColor :
				NSColor.controlTextColor; // disabledControlTextColor;
//	[attributes setObject:enabled ? [NSColor alternateSelectedControlTextColor] : [NSColor disabledControlTextColor]
//					forKey:NSForegroundColorAttributeName];

	textStorage.mutableString.string	=	label;
	[textStorage setAttributes:attributes range:NSMakeRange(0, textStorage.length)];
//	textContainer.containerSize		=	NSMakeSize(PGThumbnailSize - 12.0f, PGThumbnailSize - 8.0f);
	textContainer.containerSize		=	inOutMeasuredText->containerSize;
	//	*** -glyphRangeForTextContainer: MUST PRECEDE THE CALL TO -usedRectForTextContainer: ***
	inOutMeasuredText->glyphRange	=	[layoutManager glyphRangeForTextContainer:textContainer];
	// We center the text in the text container, so the
	// final size has to be the right width.
	inOutMeasuredText->textSize		=	textContainer.containerSize	=
		[layoutManager usedRectForTextContainer:textContainer].size;
	inOutMeasuredText->margins		=	CGVectorMake(-4.0f, -2.0f);
}

static
void
MeasureTextInBubbleUsing(NSString *label,
	BOOL enabled, NSMutableDictionary *attributes, // NSColor *backGroundColor,
	NSTextStorage *textStorage, NSLayoutManager *layoutManager,
	NSTextContainer *textContainer, const NSSize frameSize,
	MeasuredText* inOutMeasuredText) {
	inOutMeasuredText->containerSize	=	frameSize;
	MeasureTextInBubble(label, enabled, attributes, textStorage,
						layoutManager, textContainer, inOutMeasuredText);
}

static
bool	//	returns true if text will fit inside the given frameSize
Measure2TextIn2Bubbles(NSString *const label1, NSString *const label2,
	BOOL const enabled, NSMutableDictionary *const attributes, // NSColor *backGroundColor,
	NSTextStorage *const textStorage, NSLayoutManager *const layoutManager,
	NSTextContainer *const textContainer, NSSize const frameSize,
	CGFloat const verticalGapBetweenLabels, CGFloat const heightOfOneFontLine,
	MeasuredText* inOutMeasuredText1, MeasuredText* inOutMeasuredText2) {
	MeasureTextInBubbleUsing(label1, enabled, attributes, textStorage,
		layoutManager, textContainer, frameSize, inOutMeasuredText1);

	MeasureTextInBubbleUsing(label2, enabled, attributes, textStorage,
		layoutManager, textContainer, frameSize, inOutMeasuredText2);

	CGFloat const H1 = inOutMeasuredText1->textSize.height -
							2 * inOutMeasuredText1->margins.dy;
	CGFloat const H2 = inOutMeasuredText2->textSize.height -
							2 * inOutMeasuredText2->margins.dy;
	CGFloat const totalH = H1 + H2 + verticalGapBetweenLabels;

/*	{
		NSFont *font = [NSFont systemFontOfSize:11];
		CGFloat	dy = font.pointSize;
		CGFloat	a = font.ascender;
		CGFloat	d = font.descender;
		CGFloat	l = font.leading;
printf("dy %f a %f d %f l %f LH %f\n", dy, a, d, l, dy - d);
	} */
	return totalH <= frameSize.height &&
		inOutMeasuredText1->textSize.height <= heightOfOneFontLine;
}

static
void
DrawTextInBubbleBy(NSColor *const backGroundColor, NSRect const frame,
	CGFloat const dy, NSLayoutManager *const layoutManager,
	const MeasuredText* const measuredText) {
	NSRect const labelRect = NSIntegralRect(NSMakeRect(
								NSMidX(frame) - measuredText->textSize.width / 2.0f,
								NSMidY(frame) + dy,
								measuredText->textSize.width,
								measuredText->textSize.height));

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
DrawTextInBubbleAtPos(NSColor *const backGroundColor, NSRect const frame,
	BubblePosition const pos, NSLayoutManager *const layoutManager,
	const MeasuredText* const measuredText) {
	CGFloat	dy = measuredText->textSize.height;
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
DrawTextInBubble(NSString *const label, NSColor *const backGroundColor,
	NSMutableDictionary *const attributes, BOOL const enabled, NSRect const frame,
	BubblePosition const pos, NSTextStorage *const textStorage,
	NSLayoutManager *const layoutManager, NSTextContainer *const textContainer) {
	MeasuredText	mt;
	MeasureTextInBubbleUsing(label, enabled, attributes, textStorage,
						layoutManager, textContainer, frame.size, &mt);
	CGFloat const	totalH = mt.textSize.height - 2 * mt.margins.dy;
	bool const		fits = totalH <= frame.size.height;
	if(fits)
		DrawTextInBubbleAtPos(backGroundColor, frame, pos,
							  layoutManager, &mt);
	return fits;
}

static
void
DrawSingleTextLabelIn(BOOL const drawLabelAtMidY, NSString *const label,
	NSColor *const backGroundColor, NSMutableDictionary *const attributes,
	BOOL const enabled, NSRect const frame, NSRect const frameWithMargin,
	NSTextStorage *const textStorage, NSLayoutManager *const layoutManager,
	NSTextContainer *const textContainer) {
	BubblePosition const pos = drawLabelAtMidY ? BubblePositionMiddle : BubblePositionFrameBottom;
	//	try various rectangles for the label to be rendered into, from the smallest to the largest
	if(!DrawTextInBubble(label, backGroundColor, attributes, enabled, NSMakeRect(frame.origin.x + 6.0f,
						 frame.origin.y + 4.0f, frame.size.width - 12.0f, frame.size.height - 8.0f),
						 pos, textStorage, layoutManager, textContainer) &&
	   !DrawTextInBubble(label, backGroundColor, attributes, enabled, frame,
						 pos, textStorage, layoutManager, textContainer))
		(void) DrawTextInBubble(label, backGroundColor, attributes, enabled, frameWithMargin,
								pos, textStorage, layoutManager, textContainer);
}

//	MARK: -

static
char*
DecimalDigitsChars(uint64_t n, int nDigits, char buf[4]) {
	NSCAssert(nDigits > 0 && nDigits < 4, @"nDigits");

	uint64_t	factor	=	1u;
	for(int i=nDigits; --i; )
		factor	*=	10u;

	char*	p	=	buf;
	for(int i=nDigits; i--; ) {
		uint64_t	digit	=	n / factor;
		*p++	=	'0' + (char) digit;

		n		-=	digit * factor;
		factor	/=	10u;
		NSCAssert(0 != factor || 0 == i, @"i");
	}

	*p	=	'\0';
	return buf;
}

static
NSString*
StringForByteSizeWithUnit(uint64_t byte_unit_1, const char* units, uint64_t bytes, int nDecimalDigits) {
	const uint64_t	unitBytes = bytes / byte_unit_1;

	if(nDecimalDigits > 0) {
		uint64_t	factor	=	1u;
		for(int i=nDecimalDigits; i--; )
			factor	*=	10u;

		char	buf[4];
		return [NSString stringWithFormat:@"%llu.%s %sB", unitBytes,
				DecimalDigitsChars((bytes - unitBytes * byte_unit_1) * factor / byte_unit_1, nDecimalDigits, buf), units];
	}

	if(bytes < 10u * byte_unit_1)
		return [NSString stringWithFormat:@"%llu.%llu %sB", unitBytes, (bytes - unitBytes * byte_unit_1) * 10u / byte_unit_1, units];
	else
		return [NSString stringWithFormat:@"%llu %sB", unitBytes, units];
}

static
NSString*
StringForByteSizeAsBaseTen(uint64_t bytes, int nDecimalDigits) {
	static const uint64_t	kB_1	=	1000u;
	static const uint64_t	MB_1	=	1000u * 1000u;
	static const uint64_t	GB_1	=	1000u * 1000u * 1000u;
	static const uint64_t	TB_1	=	1000ul * 1000ul * 1000ul * 1000ul;

	if(bytes < kB_1)
		return [NSString stringWithFormat:@"%llu B", bytes];

	char	units[2] = { '?', '\0' };

	if(bytes < MB_1)
		return units[0] = 'k', StringForByteSizeWithUnit(kB_1, units, bytes, nDecimalDigits);

	if(bytes < GB_1)
		return units[0] = 'M', StringForByteSizeWithUnit(MB_1, units, bytes, nDecimalDigits);

	if(bytes < TB_1)
		return units[0] = 'G', StringForByteSizeWithUnit(GB_1, units, bytes, nDecimalDigits);

//	if(bytes < PB_1)	//	peta??
		return units[0] = 'T', StringForByteSizeWithUnit(TB_1, units, bytes, nDecimalDigits);
}

static
NSString*
StringForByteSizeAsBaseTwo(uint64_t bytes, int nDecimalDigits) {
	static const uint64_t	kiB_1	=	1024u;
	static const uint64_t	MiB_1	=	1024u * 1024u;
	static const uint64_t	GiB_1	=	1024u * 1024u * 1024u;
	static const uint64_t	TiB_1	=	1024ul * 1024ul * 1024ul * 1024ul;

	if(bytes < kiB_1)
		return [NSString stringWithFormat:@"%llu B", bytes];

	char	units[4] = { '?', 'i', '\0', '\0' };

	if(bytes < MiB_1)
		return units[0] = 'k', StringForByteSizeWithUnit(kiB_1, units, bytes, nDecimalDigits);

	if(bytes < GiB_1)
		return units[0] = 'M', StringForByteSizeWithUnit(MiB_1, units, bytes, nDecimalDigits);

	if(bytes < TiB_1)
		return units[0] = 'G', StringForByteSizeWithUnit(GiB_1, units, bytes, nDecimalDigits);

//	if(bytes < PiB_1)	//	peta??
		return units[0] = 'T', StringForByteSizeWithUnit(TiB_1, units, bytes, nDecimalDigits);
}

static
NSString*
StringForByteSizeAsBytes(uint64_t bytes) {
	//	UINT64_MAX = 18446744073709551615ULL and is 20 digits long
	char	s[32];	//	20 digits + 6 commas + 2 for " B" + 1 for '\0' = 29 chars
	size_t	i = sizeof s;

	//	build string in reverse (from lowest digit to highest)
	s[--i] = '\0';
	s[--i] = 'B';
	s[--i] = ' ';
	for(unsigned groupCount = 0; ;) {
		unsigned	mod10	=	bytes % 10ul;
		s[--i]	=	'0' + mod10;
		if(bytes < 10)
			break;

		bytes	/=	10u;

		//	when a group of 3 digits is placed in the output buffer, prepend a ','
		if(++groupCount == 3) {
			s[--i]	=	',';
			groupCount	=	0;
		}
	}
	return @(s+i);
}

typedef enum SizeFormat { SizeFormatNone, SizeFormatBase10, SizeFormatBase2, SizeFormatBytes } SizeFormat;

extern	NSString*	StringForByteSizeWithFormat(SizeFormat format, uint64_t bytes, int nDecimalDigits);

//	extern
NSString*
StringForByteSizeWithFormat(SizeFormat format, uint64_t bytes, int nDecimalDigits) {
	switch(format) {
	case SizeFormatNone:	abort();
	case SizeFormatBase10:	return StringForByteSizeAsBaseTen(bytes, nDecimalDigits);
	case SizeFormatBase2:	return StringForByteSizeAsBaseTwo(bytes, nDecimalDigits);
	case SizeFormatBytes:	return StringForByteSizeAsBytes(bytes);
	}
}

/*	2023/09/17 this is no longer needed

extern	NSString*	StringForByteSize(uint64_t bytes, int nDecimalDigits);

//	extern
NSString*
StringForByteSize(uint64_t bytes, int nDecimalDigits) {
	const NSUInteger	thumbnailContainerLabelType =
		[NSUserDefaults.standardUserDefaults integerForKey:PGThumbnailContainerLabelTypeKey];
	const int	sizeFormat 	=	thumbnailContainerLabelType & 3;
	if(SizeFormatNone == sizeFormat)
		return nil; // [NSString string];

	return StringForByteSizeWithFormat(sizeFormat, bytes, nDecimalDigits);
}	*/

extern	NSString*	StringForImageCount(NSUInteger const imageCount);

//	extern
NSString*
StringForImageCount(NSUInteger const imageCount) {
//#define	STRING_IMAGE_ICON	"□"		//	WHITE SQUARE	Unicode: U+25A1, UTF-8: E2 96 A1
#define	STRING_IMAGE_ICON	"❑"		//	LOWER RIGHT SHADOWED WHITE SQUARE	Unicode: U+2751, UTF-8: E2 9D 91
//#define	STRING_IMAGE_ICON	"▢"		//	WHITE SQUARE WITH ROUNDED CORNERS	Unicode: U+25A2, UTF-8: E2 96 A2
//#define	STRING_IMAGE_ICON	"🏞"	//	national park Unicode: U+1F3DE, UTF-8: F0 9F 8F 9E
//#define	STRING_IMAGE_ICON	"🖼"	//	frame with picture	Unicode: U+1F5BC, UTF-8: F0 9F 96 BC
	return [NSString stringWithFormat:@"%lu "STRING_IMAGE_ICON, imageCount];
#undef STRING_IMAGE_ICON
}

/*	extern	NSMutableString*	StringForCountAndSize(BOOL const showCounts,
								NSUInteger const folderCount, NSUInteger const imageCount,
								SizeFormat const sizeFormat,
								uint64_t const byteSize, int const nDecimalDigits);

//	extern
NSMutableString*
StringForCountAndSize(BOOL const showCounts, NSUInteger const folderCount,
	NSUInteger const imageCount, SizeFormat const sizeFormat,
	uint64_t const byteSize, int const nDecimalDigits) {
	NSMutableString*	s	=	[NSMutableString string]; // [[NSMutableString new] autorelease];
#if 1
	if(showCounts && 0 != folderCount) {
		[s appendFormat:@"%lu 📂", folderCount];
	}
	if(0 != imageCount && showCounts) {
		if(0 != s.length)
			[s appendString:@" "];	//	[s appendString:@" │ "];

//#define	STRING_IMAGE_ICON	"□"		//	WHITE SQUARE	Unicode: U+25A1, UTF-8: E2 96 A1
#define	STRING_IMAGE_ICON	"❑"		//	LOWER RIGHT SHADOWED WHITE SQUARE	Unicode: U+2751, UTF-8: E2 9D 91
//#define	STRING_IMAGE_ICON	"▢"		//	WHITE SQUARE WITH ROUNDED CORNERS	Unicode: U+25A2, UTF-8: E2 96 A2
//#define	STRING_IMAGE_ICON	"🏞"	//	national park Unicode: U+1F3DE, UTF-8: F0 9F 8F 9E
//#define	STRING_IMAGE_ICON	"🖼"	//	frame with picture	Unicode: U+1F5BC, UTF-8: F0 9F 96 BC
		[s appendFormat:@"%lu "STRING_IMAGE_ICON, imageCount];
	}

	//	if byte size is not zero and user wants size displayed
	//	then append it (PDFs return a zero byteSize)
	if(0 != byteSize && SizeFormatNone != sizeFormat) {
		if(0 != s.length)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		//	if possible, display the size with as many decimal digits as
		//	possible (with a max. of 2) on a single line
		NSMutableString*	finalStr	=	nil;
		for(int nDecimalDigits = 3; nDecimalDigits--; ) @autoreleasepool {
			NSMutableString*	test	=	[NSMutableString stringWithFormat:@"%@%@",
											 s, StringForByteSizeWithFormat(sizeFormat, byteSize, nDecimalDigits)];
			MeasuredText	testMT;
			//	?use frameWithMargin.size instead?
			MeasureTextInBubbleUsing(test, enabled, attributes, textStorage, layoutManager,
									 textContainer, frameWithMarginSize, &testMT);
			if(testMT.textSize.height <= fontLineHeight) {
				finalStr	=	[test retain];
				break;
			}
		}
		if(finalStr)
			s	=	[finalStr autorelease];
		else
			//	if the text needs more than a single line, fall back to using
			//	the default number of decimal digits, which is 0 digits if the
			//	string shows more than or equal to 10 <units> or 1 digit if the
			//	string shows less than 10 <units>, eg, 12kiB or 9.3MiB (the
			//	default string is achieved by passing -1)
			s	=	[NSMutableString stringWithFormat:@"%@%@",
					 s, StringForByteSizeWithFormat(sizeFormat, byteSize, -1)];
	} else if(0 == imageCount && SizeFormatNone != sizeFormat) {
		if(0 != s.length)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		//	this is a container which has zero images in it; instead of
		//	showing nothing, show the total size of all of this
		//	container's children
		enum { DECIMAL_DIGITS = 2 };
		s	=	[NSMutableString stringWithFormat:@"%@[%@]", s,
				 StringForByteSizeWithFormat(sizeFormat, byteSizeOfAllChildren, DECIMAL_DIGITS)];
	} else if(0 == s.length) {
		if(!showCounts)
			return;	//	nothing to draw

		assert(0 == imageCount);
		[s appendFormat:@"0 "STRING_IMAGE_ICON];
	}
#else
	if(showCounts && 0 != folderCount) {
		[s appendFormat:@"%lu 📂", folderCount];
		if(0 != imageCount)
			[s appendString:@" "];	//	[s appendString:@" │ "];
	}
	if(0 != imageCount) {
		if(showCounts)
//#define	STRING_IMAGE_ICON	"□"		//	WHITE SQUARE	Unicode: U+25A1, UTF-8: E2 96 A1
#define	STRING_IMAGE_ICON	"❑"		//	LOWER RIGHT SHADOWED WHITE SQUARE	Unicode: U+2751, UTF-8: E2 9D 91
//#define	STRING_IMAGE_ICON	"▢"		//	WHITE SQUARE WITH ROUNDED CORNERS	Unicode: U+25A2, UTF-8: E2 96 A2
//#define	STRING_IMAGE_ICON	"🏞"	//	national park Unicode: U+1F3DE, UTF-8: F0 9F 8F 9E
//#define	STRING_IMAGE_ICON	"🖼"	//	frame with picture	Unicode: U+1F5BC, UTF-8: F0 9F 96 BC
			[s appendFormat:@"%lu "STRING_IMAGE_ICON" ", imageCount];

		//	if byte size is not zero and user wants size displayed
		//	then append it (PDFs return a zero byteSize)
		if(0 != byteSize && SizeFormatNone != sizeFormat) {
			//	if possible, display the size with as many decimal digits as
			//	possible (with a max. of 2) on a single line
			NSMutableString*	finalStr	=	nil;
			for(int nDecimalDigits = 3; nDecimalDigits--; ) @autoreleasepool {
				NSMutableString*	test	=	[NSMutableString stringWithFormat:@"%@%@",
												 s, StringForByteSizeWithFormat(sizeFormat, byteSize, nDecimalDigits)];
				MeasuredText	testMT;
				//	?use frameWithMargin.size instead?
				MeasureTextInBubbleUsing(test, enabled, attributes, textStorage, layoutManager,
										 textContainer, frameWithMarginSize, &testMT);
				if(testMT.textSize.height <= fontLineHeight) {
					finalStr	=	[test retain];
					break;
				}
			}
			if(finalStr)
				s	=	[finalStr autorelease];
			else
				//	if the text needs more than a single line, fall back to using
				//	the default number of decimal digits, which is 0 digits if the
				//	string shows more than or equal to 10 <units> or 1 digit if the
				//	string shows less than 10 <units>, eg, 12kiB or 9.3MiB (the
				//	default string is achieved by passing -1)
				s	=	[NSMutableString stringWithFormat:@"%@%@",
						 s, StringForByteSizeWithFormat(sizeFormat, byteSize, -1)];
		}
	} else if(SizeFormatNone != sizeFormat) {
		if(showCounts && 0 != folderCount)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		//	this is a container which has zero images in it; instead of
		//	showing nothing, show the total size of all of this
		//	container's children
		enum { DECIMAL_DIGITS = 2 };
		s	=	[NSMutableString stringWithFormat:@"%@[%@]", s,
				 StringForByteSizeWithFormat(sizeFormat, byteSizeOfAllChildren, DECIMAL_DIGITS)];
	}
#endif
	NSCAssert(0 != s.length, @"s.length");
	return s;
}	*/

//	MARK: -

//	2023/09/17 moved into separate function to enable code reuse and remove complexity
//	from the -drawRect: method.
static
void
DrawUpperAndLower(BOOL const drawAtMidY, NSString* const label, NSColor* const labelColor,

	BOOL const showCounts, SizeFormat const sizeFormat,
	uint64_t const byteSize, NSUInteger const folderCount, NSUInteger const imageCount,

	uint64_t const byteSizeOfAllChildren,	//	ignored if value is ~0ull

	BOOL const enabled, NSMutableDictionary* const attributes,
	NSTextStorage* const textStorage, NSLayoutManager* const layoutManager,
	NSTextContainer* const textContainer, CGFloat fontLineHeight,

	NSRect const frame, NSSize const frameWithMarginSize
) {
	//	stage 1: build the metadata string
	NSMutableString*	s	=	[NSMutableString string]; // [[NSMutableString new] autorelease];
#if 1
	if(showCounts && 0 != folderCount) {
		[s appendFormat:@"%lu 📂", folderCount];
	}
	if(showCounts && 0 != imageCount) {
		if(0 != s.length)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		[s appendString:StringForImageCount(imageCount)];
	}

	//	if byte size is not zero and user wants size displayed
	//	then append it (PDFs return a zero byteSize)
	if(0 != byteSize && SizeFormatNone != sizeFormat) {
		if(0 != s.length)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		//	if possible, display the size with as many decimal digits as
		//	possible (with a max. of 2) on a single line
		NSMutableString*	finalStr	=	nil;
		for(int nDecimalDigits = 3; nDecimalDigits--; ) @autoreleasepool {
			NSMutableString*	test	=	[NSMutableString stringWithFormat:@"%@%@",
											 s, StringForByteSizeWithFormat(sizeFormat, byteSize, nDecimalDigits)];
			MeasuredText	testMT;
			//	?use frameWithMargin.size instead?
			MeasureTextInBubbleUsing(test, enabled, attributes, textStorage, layoutManager,
									 textContainer, frameWithMarginSize, &testMT);
			if(testMT.textSize.height <= fontLineHeight) {
#if __has_feature(objc_arc)
				finalStr	=	test;
#else
				finalStr	=	[test retain];
#endif
				break;
			}
		}
		if(finalStr)
#if __has_feature(objc_arc)
			s	=	finalStr;
#else
			s	=	[finalStr autorelease];
#endif
		else
			//	if the text needs more than a single line, fall back to using
			//	the default number of decimal digits, which is 0 digits if the
			//	string shows more than or equal to 10 <units> or 1 digit if the
			//	string shows less than 10 <units>, eg, 12kiB or 9.3MiB (the
			//	default string is achieved by passing -1)
			s	=	[NSMutableString stringWithFormat:@"%@%@",
					 s, StringForByteSizeWithFormat(sizeFormat, byteSize, -1)];
	} else if(SizeFormatNone != sizeFormat && ~0ull != byteSizeOfAllChildren) {
		if(0 != s.length)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		//	this is a container which has zero images in it; instead of
		//	showing nothing, show the total size of all of this
		//	container's children
		enum { DECIMAL_DIGITS = 2 };
		s	=	[NSMutableString stringWithFormat:@"%@[%@]", s,
				 StringForByteSizeWithFormat(sizeFormat, byteSizeOfAllChildren, DECIMAL_DIGITS)];
	} else if(0 == s.length) {
		if(!showCounts)
			return;	//	nothing to draw

		assert(0 == imageCount);
	//	[s appendFormat:@"0 "STRING_IMAGE_ICON];
		[s appendString:StringForImageCount(0)];
	}
#else
	if(showCounts && 0 != folderCount) {
		[s appendFormat:@"%lu 📂", folderCount];
		if(0 != imageCount)
			[s appendString:@" "];	//	[s appendString:@" │ "];
	}
	if(0 != imageCount) {
		if(showCounts)
//#define	STRING_IMAGE_ICON	"□"		//	WHITE SQUARE	Unicode: U+25A1, UTF-8: E2 96 A1
#define	STRING_IMAGE_ICON	"❑"		//	LOWER RIGHT SHADOWED WHITE SQUARE	Unicode: U+2751, UTF-8: E2 9D 91
//#define	STRING_IMAGE_ICON	"▢"		//	WHITE SQUARE WITH ROUNDED CORNERS	Unicode: U+25A2, UTF-8: E2 96 A2
//#define	STRING_IMAGE_ICON	"🏞"	//	national park Unicode: U+1F3DE, UTF-8: F0 9F 8F 9E
//#define	STRING_IMAGE_ICON	"🖼"	//	frame with picture	Unicode: U+1F5BC, UTF-8: F0 9F 96 BC
			[s appendFormat:@"%lu "STRING_IMAGE_ICON" ", imageCount];

		//	if byte size is not zero and user wants size displayed
		//	then append it (PDFs return a zero byteSize)
		if(0 != byteSize && SizeFormatNone != sizeFormat) {
			//	if possible, display the size with as many decimal digits as
			//	possible (with a max. of 2) on a single line
			NSMutableString*	finalStr	=	nil;
			for(int nDecimalDigits = 3; nDecimalDigits--; ) @autoreleasepool {
				NSMutableString*	test	=	[NSMutableString stringWithFormat:@"%@%@",
												 s, StringForByteSizeWithFormat(sizeFormat, byteSize, nDecimalDigits)];
				MeasuredText	testMT;
				//	?use frameWithMargin.size instead?
				MeasureTextInBubbleUsing(test, enabled, attributes, textStorage, layoutManager,
										 textContainer, frameWithMarginSize, &testMT);
				if(testMT.textSize.height <= fontLineHeight) {
					finalStr	=	[test retain];
					break;
				}
			}
			if(finalStr)
				s	=	[finalStr autorelease];
			else
				//	if the text needs more than a single line, fall back to using
				//	the default number of decimal digits, which is 0 digits if the
				//	string shows more than or equal to 10 <units> or 1 digit if the
				//	string shows less than 10 <units>, eg, 12kiB or 9.3MiB (the
				//	default string is achieved by passing -1)
				s	=	[NSMutableString stringWithFormat:@"%@%@",
						 s, StringForByteSizeWithFormat(sizeFormat, byteSize, -1)];
		}
	} else if(SizeFormatNone != sizeFormat) {
		if(showCounts && 0 != folderCount)
			[s appendString:@" "];	//	[s appendString:@" │ "];

		//	this is a container which has zero images in it; instead of
		//	showing nothing, show the total size of all of this
		//	container's children
		enum { DECIMAL_DIGITS = 2 };
		s	=	[NSMutableString stringWithFormat:@"%@[%@]", s,
				 StringForByteSizeWithFormat(sizeFormat, byteSizeOfAllChildren, DECIMAL_DIGITS)];
	}
#endif
	NSCAssert(0 != s.length, @"s.length");

	//	stage 2: measure the extent of the rendered strings, then
	//	build a rect which will correctly show them on the thumbnail
	MeasuredText	lowerMT;
	MeasuredText	upperMT;
#define UPPER_LOWER_GAP 2.0f
	//	try various rectangles for the label and metadata to be rendered into,
	//	from the smallest to the largest
	if(!Measure2TextIn2Bubbles(s, label, enabled, attributes, textStorage,
								layoutManager, textContainer,
								NSMakeSize(frame.size.width - 12.0f,
										   frame.size.height - 8.0f),
								UPPER_LOWER_GAP, fontLineHeight, &lowerMT, &upperMT) &&
		!Measure2TextIn2Bubbles(s, label, enabled, attributes, textStorage,
								layoutManager, textContainer, frame.size,
								UPPER_LOWER_GAP, fontLineHeight, &lowerMT, &upperMT))
		(void) Measure2TextIn2Bubbles(s, label, enabled, attributes, textStorage,
									  layoutManager, textContainer, frameWithMarginSize,
									  UPPER_LOWER_GAP, fontLineHeight, &lowerMT, &upperMT);

	//	now ready to draw into the smallest bubble possible...
	CGFloat const upperH = upperMT.textSize.height - 2 * upperMT.margins.dy;
	CGFloat const lowerH = lowerMT.textSize.height - 2 * lowerMT.margins.dy;
	CGFloat const totalH = upperH + lowerH + UPPER_LOWER_GAP;
	CGFloat const halfFrameHeight = frame.size.height * 0.5f;
#define BOTTOM_GAP 8.0f
	CGFloat dy = drawAtMidY ? totalH * -0.5f : halfFrameHeight - totalH - BOTTOM_GAP;
//	if(-halfFrameHeight + BOTTOM_GAP < dy)	//	is there enough space to shift the bubbles down?
	if(BOTTOM_GAP - halfFrameHeight < dy)	//	is there enough space to shift the bubbles down?
#define BUBBLE_DOWN_SHIFT 8.0f
		dy	+=	BUBBLE_DOWN_SHIFT;

	//	stage 3: draw the strings

	//	always draw item name first because its rectangle is vertically larger than the metadata's rect
	DrawTextInBubbleBy(labelColor, frame, dy, layoutManager, &upperMT);

	//	need to reset layoutManager and textContainer before drawing metadata (lower) string
	//	(no need to reset textContainer.containerSize because its rect is smaller than label's rect)
	MeasureTextInBubble(s, enabled, attributes, textStorage, layoutManager, textContainer, &lowerMT);
	DrawTextInBubbleBy(labelColor, frame, dy + upperH + UPPER_LOWER_GAP, layoutManager, &lowerMT);
}

//	MARK: -

#if __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET) || \
	__has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[3] or [4]

typedef const void *id_type;

typedef struct RemoveParametersBase {
	id_type items;
	id_type *next;
} RemoveParametersBase;

typedef struct RemoveParameters {
	RemoveParametersBase base;
	id_type firstValueToRemove;
} RemoveParameters;

static
void
RemoveAllNotIn_CFSetApplierFunction(id_type value, void *context) {
	RemoveParameters *removeParameters = (RemoveParameters *)context;
	if([(__bridge id)removeParameters->base.items isKindOfClass:NSSet.class]) {
		NSSet *const items = (__bridge NSSet *)removeParameters->base.items;
		if([items containsObject:(__bridge id _Nonnull)value])
			return;
	} else if([(__bridge id)removeParameters->base.items isKindOfClass:NSArray.class]) {
		NSArray *const items = (__bridge NSArray *)removeParameters->base.items;
		if([items containsObject:(__bridge id _Nonnull)value])
			return;
	} else
		abort();

	*removeParameters->base.next++ = value;
}

static
void
RemoveAllNotInArray(CFMutableSetRef mutableSet, NSArray *const items) {
	NSCAssert(items, @"");
	CFIndex n = CFSetGetCount(mutableSet);
	size_t sz = sizeof(RemoveParametersBase) + sizeof(const void*) * n;
	RemoveParameters *const removeParameters = alloca(sz);	//	no heap usage
	memset(removeParameters, 0, sz);
	removeParameters->base.items = (__bridge void *)items;
	removeParameters->base.next = &removeParameters->firstValueToRemove;
	CFSetApplyFunction(mutableSet, &RemoveAllNotIn_CFSetApplierFunction, removeParameters);
	NSCAssert(removeParameters->base.next <= n + &removeParameters->firstValueToRemove, @"");
	for(id_type *p = &removeParameters->firstValueToRemove;
		p < removeParameters->base.next; ++p) {
		CFSetRemoveValue(mutableSet, *p);
	}
}

	#if defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)

static
void
RemoveAllNotInSet(CFMutableSetRef mutableSet, NSSet *const items) {
	NSCAssert(items, @"");
	CFIndex n = CFSetGetCount(mutableSet);
	size_t sz = sizeof(RemoveParametersBase) + sizeof(const void*) * n;
	RemoveParameters *const removeParameters = alloca(sz);
	memset(removeParameters, 0, sz);
	removeParameters->base.items = (__bridge void *)items;
	removeParameters->base.next = &removeParameters->firstValueToRemove;
	CFSetApplyFunction(mutableSet, &RemoveAllNotIn_CFSetApplierFunction, removeParameters);
	NSCAssert(removeParameters->base.next <= n + &removeParameters->firstValueToRemove, @"");
	for(id_type *p = &removeParameters->firstValueToRemove;
		p < removeParameters->base.next; ++p) {
		CFSetRemoveValue(mutableSet, *p);
	}
}

static
BOOL
SetPtrEqualsSet(CFSetRef cfSet, NSSet *const nsSet) {
	if((NSUInteger)CFSetGetCount(cfSet) != nsSet.count)
		return NO;

	for(id item in nsSet)
		if(!CFSetContainsValue(cfSet, (const void *)item))
			return NO;

	return YES;
}

	#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)

static
BOOL
SetEqualsSet(NSSet *const nsSet1, NSSet *const nsSet2) {
	if(nsSet1.count != nsSet2.count)
		return NO;

	for(id item in nsSet2)
		if(![nsSet1 containsObject:item])
			return NO;

	return YES;
}

	#endif
#endif

//	MARK: -

@implementation PGThumbnailView

- (instancetype)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
		// [NSMutableSet new] creates the wrong kind of mutable set
		// because inserted objects are NOT to be retained; the code
		// in this class requires that behavior so it must be created
		// as a CF object which is then transferred to ARC to manage
	//	_selection = [NSMutableSet new];  <=== wrong
		_selection = (NSMutableSet *)CFBridgingRelease(CFSetCreateMutable(kCFAllocatorDefault, 0, NULL));
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
		_selection = [NSSet set];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
		_mutableSelection = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
		_mutableSelection = (NSMutableSet *)CFBridgingRelease(CFSetCreateMutable(kCFAllocatorDefault, 0, NULL));
#else
		_selection = (NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
#endif
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(systemColorsDidChange:)
												   name:NSSystemColorsDidChangeNotification
												 object:nil];

		//	2022/10/15
		NSUserDefaults *sud = NSUserDefaults.standardUserDefaults;
		[sud addObserver:self forKeyPath:PGShowThumbnailImageNameKey options:kNilOptions context:NULL];
		[sud addObserver:self forKeyPath:PGShowThumbnailImageSizeKey options:kNilOptions context:NULL];
		[sud addObserver:self forKeyPath:PGShowThumbnailContainerNameKey options:kNilOptions context:NULL];
		[sud addObserver:self forKeyPath:PGShowThumbnailContainerChildCountKey options:kNilOptions context:NULL];
		[sud addObserver:self forKeyPath:PGShowThumbnailContainerChildSizeTotalKey options:kNilOptions context:NULL];
		[sud addObserver:self forKeyPath:PGThumbnailSizeFormatKey options:kNilOptions context:NULL];
	}
	return self;
}

//	MARK: - private selection methods

- (void)_invalidateItem:(id)item {
	NSUInteger const i = [_items indexOfObjectIdenticalTo:item];
#if !defined(NDEBUG) && 0	//	used to fix the incorrect -[PGNode isEqual:] bug
	NSParameterAssert([item isKindOfClass:PGNode.class]);
	if (NSNotFound == i) {
		NSLog(@"item 0x%p [%@]/[%@] is NOT in items [%lu]", (__bridge void*)item,
			[[[(PGNode*)item parentNode] identifier] displayName],
			[[(PGNode*)item identifier] displayName], _items.count);
		for (id i in _items) {
			NSLog(@"\titem 0x%p [%@]/[%@]", (__bridge void*)i,
					[[[(PGNode*)i parentNode] identifier] displayName],
					[[(PGNode*)i identifier] displayName]);
		}
	}
#endif
	NSAssert(NSNotFound != i, @"i");
	NSRect const r = [self frameOfItemAtIndex:i withMargin:YES];
	[self setNeedsDisplayInRect:r];
}

- (void)_invalidateItems:(NSSet*)items {
	for(id const item in items)
		[self _invalidateItem:item];
}

- (NSUInteger)_selectionCount {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	return _selection.count;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	return _selection.count;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	return (NSUInteger) CFSetGetCount(_mutableSelection);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	return _mutableSelection.count;
#else
	return _selection.count;
#endif
}

- (NSSet *)_immutableSelection {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	return _selection;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	return _selection;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	return (__bridge NSSet * _Nonnull)_mutableSelection;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	return _mutableSelection;
#else
	return _selection;
#endif
}

- (NSSet *)_copyOfSelection {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	return [_selection copy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	return [_selection copy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	return [(__bridge NSSet *)_mutableSelection copy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	return [_mutableSelection copy];
#else
	return [[_selection copy] autorelease];
#endif
}

- (NSMutableSet *)_mutableCopyOfSelection {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	return [_selection mutableCopy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	return [_selection mutableCopy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	return [(__bridge NSMutableSet *)_mutableSelection mutableCopy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	return [_mutableSelection mutableCopy];
#else
	return [_selection mutableCopy];
#endif
}

- (BOOL)_isItemSelected:(id)item {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	return [_selection containsObject:item];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	return [_selection containsObject:item];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	return CFSetContainsValue(_mutableSelection, (const void *)item);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	return [_mutableSelection containsObject:item];
#else
	return [_selection containsObject:item];
#endif
}

- (void)_selectItem:(id)item {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	[_selection addObject:item];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	NSMutableSet *s = [_selection mutableCopy];
	[s addObject:item];
	_selection = s;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	CFSetAddValue(_mutableSelection, (__bridge const void *)item);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	[_mutableSelection addObject:item];
#else	//	non-ARC (MMR)
	[_selection addObject:item];
#endif
}

- (void)_deselectItem:(id)item {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	[_selection removeObject:item];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	NSMutableSet *s = [_selection mutableCopy];
	[s removeObject:item];
	_selection = s;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	CFSetRemoveValue(_mutableSelection, (__bridge const void *)item);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	[_mutableSelection removeObject:item];
#else	//	non-ARC (MMR)
	[_selection removeObject:item];
#endif
}

- (void)_selectItems:(NSSet *)items {
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	[_selection setSet:items];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	_selection = [items copy];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	//	remove all objects from _mutableSelection which are not in items
	if(items)	RemoveAllNotInSet(_mutableSelection, items);
	else		CFSetRemoveAllValues(_mutableSelection);

	for(id item in items)
		CFSetSetValue(_mutableSelection, (__bridge const void *)item);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	[_mutableSelection setSet:items];
#else	//	non-ARC (MMR)
	[_selection setSet:items];
#endif
}

- (void)_selectItemsFrom:(NSUInteger)first to:(NSUInteger)last {
	NSParameterAssert(NSNotFound != first);
	NSParameterAssert(NSNotFound != last);
	NSArray *const items = [_items subarrayWithRange:last < first ?
							NSMakeRange(last, first-last) : NSMakeRange(first, 1+last-first)];
	id<NSFastEnumeration> itemsEnumerator = last < first ?
		(id<NSFastEnumeration>)items.reverseObjectEnumerator : (id<NSFastEnumeration>)items;
#if 1	//	optimized
	NSRect lastItemFrame = NSZeroRect;
#endif
	for(id const item in itemsEnumerator) {
		if([self _isItemSelected:item]) {
			NSRect const itemFrame = [self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:item] withMargin:YES];
		//	[self setNeedsDisplayInRect:itemFrame];
			lastItemFrame = itemFrame;
			continue;
		}
		if(![self.dataSource thumbnailView:self canSelectItem:item])
			continue;
#if 1	//	optimized
		//	containers (any kind of folder) are not selected ==> only select viewable items
		if([self.dataSource thumbnailView:self isContainerItem:item])
			continue;

		[self _selectItem:item];
		_selectionAnchor = item;
		NSRect const itemFrame = [self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:item] withMargin:YES];
	//	[self setNeedsDisplayInRect:itemFrame];
		lastItemFrame = itemFrame;	//	[self PG_scrollRectToVisible:itemFrame type:PGScrollLeastToRect];
#else
		[self selectItem:item byExtendingSelection:YES]; // NB: this call mutates _selectionAnchor
#endif
	}

#if 1	//	optimized
	if(!NSEqualRects(lastItemFrame, NSZeroRect)) {
		[self PG_scrollRectToVisible:lastItemFrame type:PGScrollLeastToRect];
		self.needsDisplay = YES;
	}

	[self.delegate thumbnailViewSelectionDidChange:self];
#else
#endif
}

- (void)_selectAllDirectChildrenOf:(id)item {
	//	first, perform default action of selecting the item
	[self selectItem:item byExtendingSelection:NO];

	//	if the item is a container then select all of its direct children
	uint64_t const byteSizeAndFolderAndImageCount = [self.dataSource thumbnailView:self
								byteSizeAndFolderAndImageCountOfDirectChildrenForItem:item];
	if(byteSizeAndFolderAndImageCount != ULONG_MAX && byteSizeAndFolderAndImageCount != 0) {
		//	this is a container of some kind: tell thumbnail browser to select all direct
		//	children of item (which are shown in the next column to the right of this column)
		[self.delegate thumbnailView:self selectAllDirectChildrenOf:item];
	//	[self selectItemsFrom:si to:i];
	/*	uint64_t	byteSize;
		NSUInteger	folderCount = 0, imageCount = 0;
		Unpack_ByteSize_FolderImageCounts(byteSizeAndFolderAndImageCount, &byteSize,
										  &folderCount, &imageCount);
		if(0 != imageCount) {
			//	select all direct children
			{}
			return;
		}	*/
	}
}

//	MARK: - public selection methods

#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
//@synthesize selection = _selection;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
//@synthesize selection = _selection;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
- (NSSet *)selection {
	return [self _copyOfSelection];
}
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
- (NSSet *)selection {
	return [self _copyOfSelection];
}
#else
//@synthesize selection = _selection;
#endif

- (void)setSelection:(NSSet *)items
{
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	if([_selection isEqualToSet:items])	//	probably incorrect: -isEqualToSet: does not work with the custom set
		return;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	if([_selection isEqualToSet:items])	//	probably incorrect: -isEqualToSet: does not work with the custom set
		return;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	NSAssert((__bridge void *)items != _mutableSelection, @"");
//	if((__bridge void *)items == _mutableSelection)
//		return;
	if(SetPtrEqualsSet(_mutableSelection, items))
		return;	//	contents are identical (all pointer match)
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	NSAssert(items != _mutableSelection, @"");
	//	SetEqualsSet() works correctly whereas -isEqualToSet: does not
	if(SetEqualsSet(_mutableSelection, items))	//	if([_mutableSelection isEqualToSet:items])
		return;	//	contents are identical (all pointer match)
#else
	if(items == _selection)	//	NB: original code uses an incorrect test
		return;
#endif
	if(items) {
		NSMutableSet *const removedItems = [self _mutableCopyOfSelection];
		[removedItems minusSet:items];
		[self _invalidateItems:removedItems];
#if !__has_feature(objc_arc)
		[removedItems release];
#endif
	}
	if(items) {
		NSMutableSet *const addedItems = [items mutableCopy];
		[addedItems minusSet:[self _immutableSelection]];
		[self _invalidateItems:addedItems];
#if !__has_feature(objc_arc)
		[addedItems release];
#endif
	}

	PGScrollToRectType scrollToRect = PGScrollCenterToRect;	//	default is scroll to center
	if(1 == [self _selectionCount] && 1 == items.count) {
		//	regardless of the selection direction, PGScrollMostToRect is the correct scrollTo value
		scrollToRect	=	PGScrollMostToRect;
	/*	NSUInteger const oldI = [_items indexOfObjectIdenticalTo:[_selection anyObject]];
		NSAssert(NSNotFound != oldI, @"oldI");
		NSUInteger const newI = [_items indexOfObjectIdenticalTo:[items anyObject]];
		NSAssert(NSNotFound != newI, @"newI");
		NSAssert(newI != oldI, @"newI oldI");
		scrollToRect	=	newI > oldI ? PGScrollMostToRect : PGScrollMostToRect;	*/
	}

	[self _selectItems:items];
	[self _validateSelection];
	[self _scrollToSelectionAnchor:scrollToRect];
	[self.delegate thumbnailViewSelectionDidChange:self];
}
- (void)selectItem:(id)item byExtendingSelection:(BOOL)flag
{
	if(!item) return;
	BOOL const can = [self.dataSource thumbnailView:self canSelectItem:item];
	if(!can) {
		if(!flag) self.selection = [NSSet set];
		return;
	}

#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	if(!flag) {
		[_selection removeAllObjects];
		[self setNeedsDisplay:YES];
	}
	[self _selectItem:item];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	if(!flag) {
		[self _invalidateItems:_selection];
		_selection = [NSSet setWithObject:item];
	} else {
		[self _selectItem:item];
	}
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	if(!flag) {
		CFSetRemoveAllValues(_mutableSelection);
		[self setNeedsDisplay:YES];
	}
	[self _selectItem:item];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	if(!flag) {
		[_mutableSelection removeAllObjects];
		[self setNeedsDisplay:YES];
	}
	[self _selectItem:item];
#else	//	non-ARC (MMR)
	if(!flag) {
		[_selection removeAllObjects];
		[self setNeedsDisplay:YES];
	}
	[self _selectItem:item];
#endif

	_selectionAnchor = item;
	NSRect const itemFrame = [self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:item] withMargin:YES];
	if(flag) [self setNeedsDisplayInRect:itemFrame];
	[self PG_scrollRectToVisible:itemFrame type:PGScrollLeastToRect];
	[self.delegate thumbnailViewSelectionDidChange:self];
}
- (void)deselectItem:(id)item
{
	if(!item || ![self _isItemSelected:item]) return;
	[self _deselectItem:item];
	if(item == _selectionAnchor) [self _validateSelection];
	[self setNeedsDisplayInRect:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:item] withMargin:YES]];
	[self.delegate thumbnailViewSelectionDidChange:self];
}
- (void)toggleSelectionOfItem:(id)item
{
	if([self _isItemSelected:item]) [self deselectItem:item];
	else [self selectItem:item byExtendingSelection:YES];
}
- (void)moveUp:(BOOL)up byExtendingSelection:(BOOL)ext
{
	NSUInteger const count = _items.count;
	if(!count) return;
	if(!_selectionAnchor) return [self selectItem:up ? _items.lastObject : _items[0] byExtendingSelection:NO];
	NSUInteger const i = [_items indexOfObjectIdenticalTo:_selectionAnchor];
	NSAssert(NSNotFound != i, @"i");
	NSArray *const items = [_items subarrayWithRange:up ? NSMakeRange(0, i) : NSMakeRange(i + 1, count - i - 1)];
	for(id const item in up ? (id<NSFastEnumeration>)[items reverseObjectEnumerator] : (id<NSFastEnumeration>)items) {
		if(![self.dataSource thumbnailView:self canSelectItem:item]) continue;
		if([self _isItemSelected:item]) [self deselectItem:_selectionAnchor];
		[self selectItem:item byExtendingSelection:ext];
		break;
	}
}
- (BOOL)selectActiveNodeIfDisplayedInThisView {
	//	if this view has the active node but it isn't selected
	//	then select the active node and return true
	//	else return false
	id const activeNode = [self.dataSource activeNodeForThumbnailView:self];
	BOOL const mustSelectActiveNode = nil != activeNode &&
		[_items containsObject:activeNode] && ![self _isItemSelected:activeNode];
	if(mustSelectActiveNode) {
		[self _selectItem:activeNode];
		[self _validateSelection];

		[self _invalidateItem:activeNode];

		_selectionAnchor = activeNode;
		[self _scrollToSelectionAnchor:PGScrollCenterToRect];

	//	[[self delegate] thumbnailViewSelectionDidChange:self];	<== do not do this; this call executes during a similar notification
	}
	return mustSelectActiveNode;
}
/* - (void)selectAll {
	//	2023/09/18 option-clicking selects the item's direct children;
	//	this method implements the select-all-direct-children
	NSUInteger const count = [_items count];
	if(0 == count)
		return;

	[self _selectItemsFrom:count to:0];
} */

//	MARK: - PGThumbnailView

#if !__has_feature(objc_arc)
@synthesize dataSource;
@synthesize delegate;
@synthesize representedObject;
//@synthesize thumbnailOrientation = _thumbnailOrientation;
//@synthesize items = _items;
#endif
- (void)setThumbnailOrientation:(PGOrientation)orientation
{
	if(orientation == _thumbnailOrientation) return;
	_thumbnailOrientation = orientation;
	[self setNeedsDisplay:YES];
}
- (NSUInteger)indexOfItemAtPoint:(NSPoint)p
{
	return floor(p.y / PGThumbnailTotalHeight);
}
- (NSRect)frameOfItemAtIndex:(NSUInteger)index withMargin:(BOOL)flag
{
	NSRect frame = NSMakeRect(PGThumbnailMarginWidth, index * PGThumbnailTotalHeight + PGThumbnailMarginHeight, PGThumbnailSize, PGThumbnailSize);
	return flag ? NSInsetRect(frame, -PGThumbnailMarginWidth, -PGThumbnailMarginHeight) : frame;
}

//	MARK: -

- (void)reloadData
{
	BOOL const hadSelection = 0 != [self _selectionCount];
	NSArray *items = [self.dataSource itemsForThumbnailView:self];
	if(![_items isEqualToArray:items]) {
#if !__has_feature(objc_arc)
		[_items release];
#endif
		_items = [items copy];
	}
#if !defined(NDEBUG) && 0	//	used to fix the incorrect -[PGNode isEqual:] bug
	else {
		NSParameterAssert(_items.count == items.count);
		for(NSUInteger i = 0; i != items.count; ++i) {
			PGNode *n1 = [_items objectAtIndex:i];
			PGNode *n2 = [items objectAtIndex:i];
NSLog(@"n1 %@/%@", n1.parentNode.identifier.displayName, n1.identifier.displayName);
NSLog(@"n2 %@/%@", n2.parentNode.identifier.displayName, n2.identifier.displayName);
			NSParameterAssert([n1 isEqualTo:n2]);
		}
		NSParameterAssert(_items.count == items.count);
	}
#endif
	[self _validateSelection];
	[self sizeToFit];
	[self _scrollToSelectionAnchor:PGScrollCenterToRect];
	[self setNeedsDisplay:YES];
	if(hadSelection) [self.delegate thumbnailViewSelectionDidChange:self];
}

- (void)sizeToFit
{
	CGFloat const height = self.superview ? NSHeight(self.superview.bounds) : 0.0f;
	[super setFrameSize:NSMakeSize(PGOuterTotalWidth, MAX(height, [_items count] * PGThumbnailTotalHeight))];
}

//	2023/08/17 added scrollToRect parameter
- (void)_scrollToSelectionAnchor:(PGScrollToRectType)scrollToRect
{
	NSUInteger const i = [_items indexOfObjectIdenticalTo:_selectionAnchor];
	if(NSNotFound == i)
		return;

	[self PG_scrollRectToVisible:[self frameOfItemAtIndex:i withMargin:YES] type:scrollToRect];
}

- (void)selectionNeedsDisplay {	//	2023/11/23
	[self _invalidateItems:[self _immutableSelection]];
}

//	MARK: -

- (void)windowDidChangeKey:(NSNotification *)aNotif
{
	[self setNeedsDisplay:YES];
}
- (void)systemColorsDidChange:(NSNotification *)aNotif
{
	NSUInteger i = PGBackgroundCount;
	while(i--) {
#if !__has_feature(objc_arc)
		[PGBackgroundColors[i] release];
#endif
		PGBackgroundColors[i] = nil;
	}
	[self setNeedsDisplay:YES];
}

//	MARK: - PGThumbnailView(Private)

- (void)_validateSelection
{
#if __has_feature(objc_arc) && defined(SELECTION_IVAR_ORIGINAL_NSMUTABLESET)	//	[1]
	for(id const selectedItem in [_selection copy])
		if([_items indexOfObjectIdenticalTo:selectedItem] == NSNotFound)
			[_selection removeObject:selectedItem];
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_NSSET)	//	[2]
	NSMutableSet *s = [_selection mutableCopy];
	for(id const selectedItem in _selection)
		if([_items indexOfObjectIdenticalTo:selectedItem] == NSNotFound)
			[s removeObject:selectedItem];

	if(s.count != _selection.count)
		_selection = s;
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)	//	[3]
	RemoveAllNotInArray(_mutableSelection, _items);
#elif __has_feature(objc_arc) && defined(SELECTION_IVAR_SPECIAL_NSMUTABLESET)	//	[4]
	RemoveAllNotInArray((__bridge CFMutableSetRef) _mutableSelection, _items);	//	no heap usage
	//	this version creates a temporary object on the heap:
//	for(id const selectedItem in [_mutableSelection copy])
//		if([_items indexOfObjectIdenticalTo:selectedItem] == NSNotFound)
//			[_mutableSelection removeObject:selectedItem];
#else	//	non-ARC (MMR)
	for(id const selectedItem in [[_selection copy] autorelease])
		if([_items indexOfObjectIdenticalTo:selectedItem] == NSNotFound)
			[_selection removeObject:selectedItem];
#endif

	if([self _isItemSelected:_selectionAnchor]) return;
	_selectionAnchor = nil;
	for(id const anchor in _items)
		if([self _isItemSelected:anchor]) {
			_selectionAnchor = anchor;
			break;
		}
}

//	MARK: - private drawing

- (NSColor *)_backgroundColorWithType:(PGBackgroundType)type
{
	if(PGBackgroundColors[type]) return PGBackgroundColors[type];
#if __has_feature(objc_arc)
	NSImage *const background = [[NSImage alloc] initWithSize:NSMakeSize(PGOuterTotalWidth, PGBackgroundHeight)];
#else
	NSImage *const background = [[[NSImage alloc] initWithSize:NSMakeSize(PGOuterTotalWidth, PGBackgroundHeight)] autorelease];
#endif
	[background lockFocus];

#if __has_feature(objc_arc)
	NSShadow *const shadow = [NSShadow new];
#else
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
#endif
	shadow.shadowOffset = NSMakeSize(0.0f, -2.0f);
	shadow.shadowBlurRadius = 4.0f;
	[shadow set];
	CGContextRef const imageContext = [NSGraphicsContext currentContext].CGContext;
	CGContextBeginTransparencyLayerWithRect(imageContext, CGRectMake(0, 0, PGOuterTotalWidth, PGBackgroundHeight), NULL);
	NSRect const r = NSMakeRect(0.0f, 0.0f, PGInnerTotalWidth, PGBackgroundHeight);
	PGDrawGradient();
#if 1
	if(PGBackground_NotSelected != type) {
		NSColor* c = nil;
		switch(type) {
		case PGBackground_Selected_Active_MainWindow:
		case PGBackground_Selected_ParentOfActive_MainWindow:
		case PGBackground_Selected_NotActive_MainWindow:
			c = [NSColor selectedContentBackgroundColor];
			break;
		case PGBackground_Selected_Active_NotMainWindow:
		case PGBackground_Selected_ParentOfActive_NotMainWindow:
		case PGBackground_Selected_NotActive_NotMainWindow:
			c = [NSColor unemphasizedSelectedContentBackgroundColor];
			break;
		default:
			break;
		}

		if(c) {
			if(PGBackground_Selected_ParentOfActive_MainWindow == type ||
				PGBackground_Selected_NotActive_MainWindow == type ||
				PGBackground_Selected_ParentOfActive_NotMainWindow == type ||
				PGBackground_Selected_NotActive_NotMainWindow == type)
				c = [c highlightWithLevel:0.80f];
			else if (PGBackground_Selected_Active_NotMainWindow == type)
				c = [c highlightWithLevel:0.40f];

			[[c colorWithAlphaComponent:0.5f] set];
			NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
		}
	}
#else
	if(PGBackgroundDeselected != type) {
		NSColor* c = PGBackgroundSelectedActive == type ?
						[NSColor selectedContentBackgroundColor] :				//	PGBackgroundSelectedActive
						[NSColor unemphasizedSelectedContentBackgroundColor];	//	PGBackgroundSelectedInactive
		[[c colorWithAlphaComponent:0.5f] set];
		NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
	}
#endif

	NSRect const leftHoleRect = NSMakeRect(PGBackgroundHoleSpacingWidth, 0.0f, PGBackgroundHoleWidth, PGBackgroundHoleHeight);
	NSRect const rightHoleRect = NSMakeRect(PGInnerTotalWidth - PGThumbnailMarginWidth + PGBackgroundHoleSpacingWidth, 0.0f, PGBackgroundHoleWidth, PGBackgroundHoleHeight);
	[[NSColor colorWithDeviceWhite:1.0f alpha:0.2f] set];
	[[NSBezierPath PG_bezierPathWithRoundRect:leftHoleRect cornerRadius:2.0f] fill];
	[[NSBezierPath PG_bezierPathWithRoundRect:rightHoleRect cornerRadius:2.0f] fill];
	[[NSColor clearColor] set];

#if 1
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext currentContext].compositingOperation = NSCompositingOperationCopy;
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(leftHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] fill];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(rightHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] fill];
	[NSGraphicsContext restoreGraphicsState];
#else
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(leftHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] PG_fillUsingOperation:NSCompositingOperationCopy];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(rightHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] PG_fillUsingOperation:NSCompositingOperationCopy];
#endif

	CGContextEndTransparencyLayer(imageContext);
	[background unlockFocus];
	NSColor *const color = [NSColor colorWithPatternImage:background];
#if __has_feature(objc_arc)
	PGBackgroundColors[type] = color;
#else
	PGBackgroundColors[type] = [color retain];
#endif
	return color;
}

- (BOOL)_isDisplayControllerTheMainWindow 
{
	NSWindow *const tvw = self.window;	//	tvw = thumbnail view window
	//	2023/11/23 bugfix: the key window will be the display controller's window and
	//	not the thumbnail view's window; the original code was testing the thumbnail
	//	view's window instead of the display controller's window
	id<NSWindowDelegate> wd = tvw.delegate;
	NSWindow *dcw = nil;	//	dcw = display controller window
	if([wd isKindOfClass:PGThumbnailController.class]) {
		PGDisplayController *const dc = ((PGThumbnailController *)wd).displayController;
		dcw = dc.window;
	}
/*
NSLog(@"view %p [%@], has window: %p [%@] \"%@\", is key %c, is 1st responder %c, keyWindow %p [%@] \"%@\"",
	  (__bridge const void*) self, self.className, (__bridge const void*) tvw, tvw.title, tvw.className,
	  tvw.isKeyWindow ? 'Y' : 'N', tvw.firstResponder == self ? 'Y' : 'N',
	  NSApplication.sharedApplication.keyWindow,
	  NSApplication.sharedApplication.keyWindow.className,
	  NSApplication.sharedApplication.keyWindow.title);
 */
	//	2023/11/12 replaced with is-main-window test
//	return [tvw isKeyWindow] && [tvw firstResponder] == self;
	return dcw.mainWindow;
}

//	MARK: - NSView

- (BOOL)isFlipped
{
	return YES;
}
- (BOOL)isOpaque
{
	return YES;
}
- (void)drawRect:(NSRect)aRect
{
	CGContextRef const context = [NSGraphicsContext currentContext].CGContext;

	NSRect const patternRect = [self convertRect:self.bounds toView:nil];
	CGContextSetPatternPhase(context, CGSizeMake(NSMinX(patternRect), floor(NSMaxY(patternRect) - PGBackgroundHoleHeight / 2.0f)));

	NSInteger count = 0;
	NSRect const *rects = NULL;
	[self getRectsBeingDrawn:&rects count:&count];

#if 1
	[[self _backgroundColorWithType:PGBackground_NotSelected] set];
#else
	[[self _backgroundColorWithType:PGBackgroundDeselected] set];
#endif
	NSRectFillList(rects, count);

#if __has_feature(objc_arc)
	NSShadow *const nilShadow = [NSShadow new];
#else
	NSShadow *const nilShadow = [[[NSShadow alloc] init] autorelease];
#endif
	[nilShadow setShadowColor:nil];
#if __has_feature(objc_arc)
	NSShadow *const shadow = [NSShadow new];
#else
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
#endif
	shadow.shadowOffset = NSMakeSize(0.0f, -2.0f);
	shadow.shadowBlurRadius = 4.0f;
	[shadow set];

	NSUserDefaults *sud = NSUserDefaults.standardUserDefaults;
	BOOL const	showThumbnailImageName = [sud boolForKey:PGShowThumbnailImageNameKey];
	BOOL const	showThumbnailImageSize = [sud boolForKey:PGShowThumbnailImageSizeKey];
	BOOL const	showThumbnailContainerName = [sud boolForKey:PGShowThumbnailContainerNameKey];
	BOOL const	showThumbnailContainerChildCount = [sud boolForKey:PGShowThumbnailContainerChildCountKey];
	BOOL const	showThumbnailContainerChildSizeTotal = [sud boolForKey:PGShowThumbnailContainerChildSizeTotalKey];
	NSInteger const	thumbnailSizeFormat = GetThumbnailSizeFormat();
	NSUInteger i = 0;
#if 1
	id activeNode = [self.dataSource activeNodeForThumbnailView:self];
#endif
#if 0	//	debugging
NSMutableString *logStr = [NSMutableString stringWithFormat:@"self %p activeNode %p sel.count %lu",
(__bridge const void *)self, (__bridge const void *)activeNode, [self _selectionCount]];
#endif	//	debugging
	for(; i < _items.count; i++) {
		NSRect const frameWithMargin = [self frameOfItemAtIndex:i withMargin:YES];
		if(!PGIntersectsRectList(frameWithMargin, rects, count)) continue;
		id const item = _items[i];
		if([self _isItemSelected:item]) {
			[nilShadow set];
#if 1
	#if 0	//	debugging
if(activeNode == item)
	[logStr appendFormat:@" [%lu]%p*", i, (__bridge const void *)item];
else
	[logStr appendFormat:@" [%lu]%p", i, (__bridge const void *)item];
	#endif	//	debugging
			PGBackgroundType bgType;
			if ([self _isDisplayControllerTheMainWindow]) {
				if(activeNode == item)
					bgType = PGBackground_Selected_Active_MainWindow;
				else if([self.dataSource thumbnailView:self isParentOfActiveNode:item])
					bgType = PGBackground_Selected_ParentOfActive_MainWindow;
				else
					bgType = PGBackground_Selected_NotActive_MainWindow;
			} else {
				if(activeNode == item)
					bgType = PGBackground_Selected_Active_NotMainWindow;
				else if([self.dataSource thumbnailView:self isParentOfActiveNode:item])
					bgType = PGBackground_Selected_ParentOfActive_NotMainWindow;
				else
					bgType = PGBackground_Selected_NotActive_NotMainWindow;
			}
			[[self _backgroundColorWithType:bgType] set];
#else
			[[self _backgroundColorWithType:[self PG_isActive] ? PGBackgroundSelectedActive : PGBackgroundSelectedInactive] set];
#endif
		//	[NSColor.yellowColor set];
			NSRectFill(frameWithMargin);
			[shadow set];
		}
#if 0	//	debugging
else {
if(activeNode == item)
	[logStr appendFormat:@" [%lu]%p!", i, (__bridge const void *)item];
}
#endif	//	debugging
		NSImage *const thumb = [self.dataSource thumbnailView:self thumbnailForItem:item];
		if(!thumb) {
			[NSBezierPath PG_drawSpinnerInRect:NSInsetRect([self frameOfItemAtIndex:i withMargin:NO], 20.0f, 20.0f)
								  startAtPetal:-1];
			continue;
		}
		NSSize originalSize = thumb.size;
		if(PGRotated90CCW & _thumbnailOrientation) originalSize = NSMakeSize(originalSize.height, originalSize.width);
		NSRect const frame = [self frameOfItemAtIndex:i withMargin:NO];
		NSRect const thumbnailRect = PGIntegralRect(PGCenteredSizeInRect(PGScaleSizeByFloat(originalSize, MIN(1, MIN(NSWidth(frame) / originalSize.width, NSHeight(frame) / originalSize.height))), frame));
		BOOL const enabled = [self.dataSource thumbnailView:self canSelectItem:item];

		NSRect const highlight = self.dataSource ? [self.dataSource thumbnailView:self highlightRectForItem:item] : NSZeroRect;
		BOOL const entirelyHighlighted = NSEqualRects(highlight, NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f));
		if(!entirelyHighlighted) {
			CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(thumbnailRect), NULL);
			[nilShadow set];
		}
		BOOL const hasRealThumbnail = [self.dataSource thumbnailView:self hasRealThumbnailForItem:item];
		NSRect transformedThumbnailRect = thumbnailRect;
		NSAffineTransform *const transform = [NSAffineTransform PG_transformWithRect:&transformedThumbnailRect
			 // Also flip it vertically because our view is flipped and -drawInRect:… ignores that.
			orientation:hasRealThumbnail ? PGAddOrientation(_thumbnailOrientation, PGFlippedVert) : PGFlippedVert];
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

		BOOL const isContainer = [self.dataSource thumbnailView:self isContainerItem:item];
		BOOL const willDrawText = !isContainer // || hasRealThumbnail
			? showThumbnailImageName || showThumbnailImageSize	//	images and non-containers
			: showThumbnailContainerName || showThumbnailContainerChildCount || showThumbnailContainerChildSizeTotal;
		if(willDrawText) {
			[nilShadow set];
			static NSMutableDictionary *attributes = nil;
			static CGFloat fontLineHeight = 0;
			if(!attributes) {
#if __has_feature(objc_arc)
				NSMutableParagraphStyle *const style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
#else
				NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
#endif
				style.lineBreakMode = NSLineBreakByWordWrapping;
				style.alignment = NSTextAlignmentCenter;
#if __has_feature(objc_arc)
				NSShadow *const textShadow = [NSShadow new];
#else
				NSShadow *const textShadow = [[[NSShadow alloc] init] autorelease];
#endif
				textShadow.shadowBlurRadius = 2.0f;
				textShadow.shadowOffset = NSMakeSize(0.0f, -1.0f);
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
#if __has_feature(objc_arc)
				[layoutManager addTextContainer:textContainer];
				[textStorage addLayoutManager:layoutManager];
#else
				[layoutManager addTextContainer:[textContainer autorelease]];
				[textStorage addLayoutManager:[layoutManager autorelease]];
#endif
				textContainer.lineFragmentPadding = 0;
			}

#if 1	//	v5: 2 bubbles, no need for localized strings, can work on 10.14 (does not rely on 11.x APIs),
		//	and supports text bubble fitting into the smallest rectangle possible
			NSColor *const labelColor = [self.dataSource thumbnailView:self labelColorForItem:item];
			if(!isContainer /* || hasRealThumbnail */) {
				NSAssert(showThumbnailImageName || showThumbnailImageSize, @"");
				NSString *const label = showThumbnailImageName ?
										[self.dataSource thumbnailView:self labelForItem:item] : nil;
				uint64_t const byteSize = showThumbnailImageSize ?
											[self.dataSource thumbnailView:self byteSizeOf:item] : 0ull;
				//	image or non-container non-image (in a folder, archive, etc.)
				if(showThumbnailImageName && showThumbnailImageSize) {
					if(0 != byteSize)
						DrawUpperAndLower(NO, label, labelColor, NO /* showCounts */,
							showThumbnailImageSize ? (SizeFormat) (1 + thumbnailSizeFormat) : SizeFormatNone,
							byteSize, 0, 0, ~0ull,
							enabled, attributes, textStorage, layoutManager, textContainer, fontLineHeight,
							frame, frameWithMargin.size);
					else
						DrawSingleTextLabelIn(NO, label, labelColor, attributes,
							enabled, frame, frameWithMargin, textStorage, layoutManager, textContainer);
				} else if(showThumbnailImageName)
					DrawSingleTextLabelIn(NO, label, labelColor, attributes,
						enabled, frame, frameWithMargin, textStorage, layoutManager, textContainer);
				else if(showThumbnailImageSize) {
					enum { DECIMAL_DIGITS = 2 };
					DrawSingleTextLabelIn(NO,
						StringForByteSizeWithFormat((SizeFormat) (1 + thumbnailSizeFormat), byteSize, DECIMAL_DIGITS),
						labelColor, attributes, enabled, frame, frameWithMargin,
						textStorage, layoutManager, textContainer);
				}
			} else if(!showThumbnailContainerChildCount && !showThumbnailContainerChildSizeTotal) {
				//	folders/containers which only show a name
				NSAssert(showThumbnailContainerName && !showThumbnailContainerChildCount &&
						!showThumbnailContainerChildSizeTotal, @"name-only");
				NSString *const	label = [self.dataSource thumbnailView:self labelForItem:item];
				DrawSingleTextLabelIn(!hasRealThumbnail, label, labelColor, attributes, enabled, frame,
										frameWithMargin, textStorage, layoutManager, textContainer);
			} else {
				//	folders/containers which show an image count and/or size (and maybe a name)
				NSString *const	label = showThumbnailContainerName ?
										[self.dataSource thumbnailView:self labelForItem:item] : nil;
				SizeFormat const	sizeFormat = showThumbnailContainerChildSizeTotal ?
													(SizeFormat) (1 + thumbnailSizeFormat) : SizeFormatNone;
				uint64_t const	byteSizeAndFolderAndImageCount = [self.dataSource thumbnailView:self
										  byteSizeAndFolderAndImageCountOfDirectChildrenForItem:item];
				uint64_t		byteSizeDirectChildren;
				NSUInteger		folderCount = 0, imageCount = 0;
				Unpack_ByteSize_FolderImageCounts(byteSizeAndFolderAndImageCount, &byteSizeDirectChildren,
												  &folderCount, &imageCount);

				OSType const	typeCode = [self.dataSource thumbnailView:self typeCodeForItem:item];
				if('fold' != typeCode) {	//	PDF/ZIP/RAR/etc.
					//	draw the 2 lines at the bottom of the thumbnail if there is a real
					//	thumbnail being displayed (eg, on a PDF container node)
					DrawUpperAndLower(!hasRealThumbnail, showThumbnailContainerName ? label : [NSString string],
						labelColor, showThumbnailContainerChildCount, sizeFormat,
						byteSizeDirectChildren, folderCount, imageCount,

						//	show byte size of PDF/ZIP/RAR/etc. file as "[123MB]"
						showThumbnailContainerChildSizeTotal ?
							[self.dataSource thumbnailView:self byteSizeOf:item] : ~0ull,

						enabled, attributes, textStorage, layoutManager, textContainer, fontLineHeight,
						frame, frameWithMargin.size);
				} else	//	folder on a disk or in an archive
					DrawUpperAndLower(YES, showThumbnailContainerName ? label : [NSString string],
						labelColor, showThumbnailContainerChildCount, sizeFormat,
						byteSizeDirectChildren, folderCount, imageCount,

						//	if 0 direct children and showThumbnailContainerChildSizeTotal then calculate
						//	the value for byteSizeOfAllChildren else pass ~0ull
						0 == imageCount && showThumbnailContainerChildSizeTotal ?
							[self.dataSource thumbnailView:self byteSizeOfAllChildrenForItem:item] : ~0ull,

						enabled, attributes, textStorage, layoutManager, textContainer, fontLineHeight,
						frame, frameWithMargin.size);
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
				NSAssert(0 != s.length, @"s.length");

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
		} else {
			NSColor *const labelColor = [self.dataSource thumbnailView:self labelColorForItem:item];
			if(labelColor) {
				NSRect const labelRect = NSMakeRect(NSMaxX(frame) - 16.0f, round(MAX(NSMaxY(thumbnailRect) - 16.0f, NSMidY(thumbnailRect) - 6.0f)), 12.0f, 12.0f);
				[NSGraphicsContext saveGraphicsState];
				CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(NSInsetRect(labelRect, -5.0f, -5.0f)), NULL);
				NSBezierPath *const labelDot = [NSBezierPath bezierPathWithOvalInRect:labelRect];
				[labelColor set];
				[labelDot fill];
				[[NSColor whiteColor] set];
				labelDot.lineWidth = 2.0f;
				[labelDot stroke];
				CGContextEndTransparencyLayer(context);
				[NSGraphicsContext restoreGraphicsState];
			}
		}
	}
#if 0	//	debugging
NSLog(@"%@", logStr);
#endif	//	debugging
	[nilShadow set];
}

//	MARK: -

- (void)setFrameSize:(NSSize)oldSize
{
	[self sizeToFit];
}
- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
	[self.window PG_removeObserver:self name:NSWindowDidBecomeKeyNotification];
	[self.window PG_removeObserver:self name:NSWindowDidResignKeyNotification];
	[aWindow PG_addObserver:self selector:@selector(windowDidChangeKey:) name:NSWindowDidBecomeKeyNotification];
	[aWindow PG_addObserver:self selector:@selector(windowDidChangeKey:) name:NSWindowDidResignKeyNotification];
}

//	MARK: - NSView(PGClipViewAdditions)

- (BOOL)PG_acceptsClicksInClipView:(PGClipView *)sender
{
	return NO;
}

//	MARK: - NSResponder

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
#if 1
	//	2023/09/18 optimized version
	NSUInteger const count = _items.count;
	if(0 == count)
		return;

	[self _selectItemsFrom:count to:0];
#else
	NSMutableSet *const selection = [NSMutableSet set];
	for(id const item in _items)
		if([[self dataSource] thumbnailView:self canSelectItem:item])
			[selection addObject:item];
	[self setSelection:selection];
#endif
}

//	MARK: -

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

//	MARK: -

- (void)mouseDown:(NSEvent *)anEvent
{
	NSPoint const p = [anEvent PG_locationInView:self];
	NSUInteger const i = [self indexOfItemAtPoint:p];
	BOOL const validItemHit = i < _items.count;
	id const item = ([self mouse:p inRect:self.bounds] && validItemHit) ? _items[i] : nil;

	//	2023/09/06 shift-clicking now extends the selection;
	//	cmd-clicking still adds/removes a single item to/from the selection
	if(anEvent.modifierFlags & NSEventModifierFlagCommand) [self toggleSelectionOfItem:item];
	else if(validItemHit && _selectionAnchor && (anEvent.modifierFlags & NSEventModifierFlagShift)) {
		NSUInteger const si = [_items indexOfObjectIdenticalTo:_selectionAnchor];
#if 1
		[self _selectItemsFrom:si to:i];
#else
		NSAssert(NSNotFound != si, @"si");
		NSArray *const items = [_items subarrayWithRange:i < si ? NSMakeRange(i, si-i) : NSMakeRange(si, 1+i-si)];
		for(id const item in i < si ? (id<NSFastEnumeration>)items.reverseObjectEnumerator : (id<NSFastEnumeration>)items) {
			if(![self.dataSource thumbnailView:self canSelectItem:item]) continue;
			if([self _isItemSelected:item]) continue;
			[self selectItem:item byExtendingSelection:YES]; // NB: this call mutates _selectionAnchor
		}
#endif
	} else if(validItemHit && _selectionAnchor && (anEvent.modifierFlags & NSEventModifierFlagOption)) {
		//	2023/09/18 option-clicking selects the item's direct children
		[self _selectAllDirectChildrenOf:item];
	} else [self selectItem:item byExtendingSelection:NO];
//	if([anEvent modifierFlags] & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) [self toggleSelectionOfItem:item];
//	else [self selectItem:item byExtendingSelection:NO];
}
- (void)keyDown:(NSEvent *)anEvent
{
	if(anEvent.modifierFlags & NSEventModifierFlagCommand) return [super keyDown:anEvent];
	if(![NSApp.mainMenu performKeyEquivalent:anEvent]) [self interpretKeyEvents:@[anEvent]];
}

//	MARK: - NSObject

- (void)dealloc
{
	//	2022/10/15
	NSUserDefaults *sud = NSUserDefaults.standardUserDefaults;
	[sud removeObserver:self forKeyPath:PGShowThumbnailImageNameKey];
	[sud removeObserver:self forKeyPath:PGShowThumbnailImageSizeKey];
	[sud removeObserver:self forKeyPath:PGShowThumbnailContainerNameKey];
	[sud removeObserver:self forKeyPath:PGShowThumbnailContainerChildCountKey];
	[sud removeObserver:self forKeyPath:PGShowThumbnailContainerChildSizeTotalKey];
	[sud removeObserver:self forKeyPath:PGThumbnailSizeFormatKey];

	[self PG_removeObserver];

#if defined(SELECTION_IVAR_SPECIAL_CFMUTABLESET)
	CFRelease(_mutableSelection);
#endif

#if !__has_feature(objc_arc)
	[representedObject release];
	[_items release];
	[_selection release];
	[super dealloc];
#endif
}

//	MARK: - NSObject(NSKeyValueObserving)

//	2022/10/15
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	if(PGEqualObjects(keyPath, PGShowThumbnailImageNameKey) ||
	   PGEqualObjects(keyPath, PGShowThumbnailImageSizeKey) ||
	   PGEqualObjects(keyPath, PGShowThumbnailContainerNameKey) ||
	   PGEqualObjects(keyPath, PGShowThumbnailContainerChildCountKey) ||
	   PGEqualObjects(keyPath, PGShowThumbnailContainerChildSizeTotalKey) ||
	   PGEqualObjects(keyPath, PGThumbnailSizeFormatKey))
		self.needsDisplay	=	YES;
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end

//	MARK: -
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
- (BOOL)thumbnailView:(PGThumbnailView *)sender hasRealThumbnailForItem:(id)item
{
	return NO;
}

- (NSInteger)thumbnailView:(PGThumbnailView *)sender directChildrenCountForItem:(id)item
{
	return NSNotFound;
}

@end

//	MARK: -
@implementation NSObject(PGThumbnailViewDelegate)

- (void)thumbnailViewSelectionDidChange:(PGThumbnailView *)sender {}

@end
