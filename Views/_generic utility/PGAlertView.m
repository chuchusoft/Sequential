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
#import "PGAlertView.h"

// Views
#import "PGBezelPanel.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGDelayedPerforming.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

#define PGAlertViewSize 100.0f
#define PGMarginSize 4.0f

#if __has_feature(objc_arc)

@interface PGAlertView ()

@property (nonatomic, strong) NSMutableArray *graphicStack;
//	PGAlertGraphic *_currentGraphic;
//	NSUInteger _frameCount;
@property (nonatomic, weak) NSTimer *frameTimer;

- (void)_updateCurrentGraphic;

@end

#else

@interface PGAlertView(Private)

- (void)_updateCurrentGraphic;

@end

#endif

@interface PGCannotGoRightGraphic : PGAlertGraphic
@end
@interface PGCannotGoLeftGraphic : PGCannotGoRightGraphic
@end
@interface PGLoopedLeftGraphic : PGAlertGraphic
@end
@interface PGLoopedRightGraphic : PGLoopedLeftGraphic
@end

//	MARK: -
@implementation PGAlertView

- (void)pushGraphic:(PGAlertGraphic *)aGraphic window:(NSWindow *)window
{
	NSParameterAssert(aGraphic);
	NSUInteger const i = [_graphicStack indexOfObject:aGraphic];
	if(0 == i) {
		[self PG_cancelPreviousPerformRequestsWithSelector:@selector(popGraphicIdenticalTo:) object:_currentGraphic];
	} else {
		[_graphicStack insertObject:aGraphic atIndex:0];
		[self _updateCurrentGraphic];
	}
	NSTimeInterval const fadeOutDelay = [_currentGraphic fadeOutDelay];
	if(fadeOutDelay >= 0.01f) [self PG_performSelector:@selector(popGraphicIdenticalTo:) withObject:_currentGraphic fireDate:nil interval:fadeOutDelay options:PGCompareArgumentPointer];
	if(window && [[self window] respondsToSelector:@selector(displayOverWindow:)]) [(PGBezelPanel *)[self window] displayOverWindow:window];
}
- (void)popGraphic:(PGAlertGraphic *)aGraphic
{
	NSParameterAssert(aGraphic);
	NSUInteger const i = [_graphicStack indexOfObject:aGraphic];
	if(NSNotFound == i) return;
	[_graphicStack removeObjectAtIndex:i];
	[self _updateCurrentGraphic];
}
- (void)popGraphicIdenticalTo:(PGAlertGraphic *)aGraphic
{
	NSParameterAssert(aGraphic);
	NSUInteger const i = [_graphicStack indexOfObjectIdenticalTo:aGraphic];
	if(NSNotFound == i) return;
	[_graphicStack removeObjectAtIndex:i];
	[self _updateCurrentGraphic];
}
- (void)popGraphicsOfType:(PGAlertGraphicType)type
{
#if __has_feature(objc_arc)
	for(PGAlertGraphic *const graphic in [_graphicStack copy])
#else
	for(PGAlertGraphic *const graphic in [[_graphicStack copy] autorelease])
#endif
		if([graphic graphicType] == type)
			[_graphicStack removeObjectIdenticalTo:graphic];
	[self _updateCurrentGraphic];
}

//	MARK: -

- (void)animateOneFrame:(PGAlertView *)anAlertView
{
	NSParameterAssert(_currentGraphic);
	_frameCount = (_frameCount + 1) % _currentGraphic.frameCount;
	[_currentGraphic animateOneFrame:self];
}

//	MARK: - PGAlertView(Private)

- (void)_updateCurrentGraphic
{
	if(![_graphicStack count]) {
		if([_currentGraphic fadeOutDelay]) [(PGBezelPanel *)[self window] fadeOut];
		else [[self window] close];
		return;
	}
#if __has_feature(objc_arc)
	_currentGraphic = [_graphicStack objectAtIndex:0];
#else
	[_currentGraphic release];
	_currentGraphic = [[_graphicStack objectAtIndex:0] retain];
#endif
	[_frameTimer invalidate];
	_frameCount = 0;
	NSTimeInterval const frameDelay = _currentGraphic.frameDelay;
	_frameTimer = _currentGraphic.frameCount > 1 ? [self PG_performSelector:@selector(animateOneFrame:) withObject:self fireDate:nil interval:frameDelay options:PGRetainTarget | PGRepeatOnInterval] : nil;
	[self setNeedsDisplay:YES];
}

- (void)prepareForWindowClosing
{
	[_frameTimer invalidate];
	_frameTimer = nil;
	[_graphicStack removeAllObjects];
}

//	MARK: - NSView

- (id)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_graphicStack = [[NSMutableArray alloc] init];
	}
	return self;
}

- (BOOL)isOpaque
{
	return YES;
}
- (void)drawRect:(NSRect)aRect
{
	[_currentGraphic drawInView:self];
}

- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
	[[self window] PG_removeObserver:self name:NSWindowWillCloseNotification];
	if(aWindow) [aWindow PG_addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification];
	else [self prepareForWindowClosing];	//	[self windowWillClose:nil];	2021/07/21
}

//	MARK: - NSObject

- (void)dealloc
{
	[self PG_cancelPreviousPerformRequests];
	[self PG_removeObserver];
#if !__has_feature(objc_arc)
	[_graphicStack release];
	[_currentGraphic release];
#endif
	[_frameTimer invalidate];
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

//	MARK: - <NSWindowDelegate>

- (void)windowWillClose:(NSNotification *)aNotif
{
	[self prepareForWindowClosing];	//	2021/07/21
//	[_frameTimer invalidate];	//	2021/07/21
//	_frameTimer = nil;	//	2021/07/21
//	[_graphicStack removeAllObjects];	//	2021/07/21
}

//	MARK: - <PGBezelPanelContentView>

- (NSRect)bezelPanel:(PGBezelPanel *)sender frameForContentRect:(NSRect)aRect scale:(CGFloat)scaleFactor
{
	CGFloat const scaledPanelSize = scaleFactor * PGAlertViewSize;
	return PGIntegralRect(NSMakeRect(
		NSMinX(aRect) + PGMarginSize,
		NSMaxY(aRect) - scaledPanelSize - PGMarginSize,
		scaledPanelSize,
		scaledPanelSize
	));
}

@end

//	MARK: -
@implementation PGAlertGraphic

//	MARK: +PGAlertGraphic

+ (id)cannotGoRightGraphic
{
#if __has_feature(objc_arc)
	return [PGCannotGoRightGraphic new];
#else
	return [[[PGCannotGoRightGraphic alloc] init] autorelease];
#endif
}
+ (id)cannotGoLeftGraphic
{
#if __has_feature(objc_arc)
	return [PGCannotGoLeftGraphic new];
#else
	return [[[PGCannotGoLeftGraphic alloc] init] autorelease];
#endif
}
+ (id)loopedRightGraphic
{
#if __has_feature(objc_arc)
	return [PGLoopedRightGraphic new];
#else
	return [[[PGLoopedRightGraphic alloc] init] autorelease];
#endif
}
+ (id)loopedLeftGraphic
{
#if __has_feature(objc_arc)
	return [PGLoopedLeftGraphic new];
#else
	return [[[PGLoopedLeftGraphic alloc] init] autorelease];
#endif
}

//	MARK: - PGAlertGraphic

- (PGAlertGraphicType)graphicType
{
	return PGSingleImageGraphic;
}
- (NSTimeInterval)fadeOutDelay
{
	return 1.0f;
}
- (NSTimeInterval)frameDelay
{
	return 0.0f;
}
- (NSUInteger)frameCount
{
	return 1;
}

//	MARK: -

- (void)drawInView:(PGAlertView *)anAlertView
{
	NSInteger count, i;
	NSRect const *rects;
	[anAlertView getRectsBeingDrawn:&rects count:&count];
	[[NSColor PG_bezelBackgroundColor] set];
	CGFloat const f = PGAlertViewSize / 300.0f;
	for(i = count; i--;) {
		NSRectFill(NSIntersectionRect(rects[i], PGIntegralRect(NSMakeRect(  0.0f * f, 50.0f * f,  50.0f * f, 200.0f * f))));
		NSRectFill(NSIntersectionRect(rects[i], PGIntegralRect(NSMakeRect( 50.0f * f,  0.0f * f, 200.0f * f, 300.0f * f))));
		NSRectFill(NSIntersectionRect(rects[i], PGIntegralRect(NSMakeRect(250.0f * f, 50.0f * f,  50.0f * f, 200.0f * f))));
	}
	NSRect const corners[] = {
		PGIntegralRect(NSMakeRect(250.0f * f, 250.0f * f, 50.0f * f, 50.0f * f)),
		PGIntegralRect(NSMakeRect(  0.0f * f, 250.0f * f, 50.0f * f, 50.0f * f)),
		PGIntegralRect(NSMakeRect(  0.0f * f,   0.0f * f, 50.0f * f, 50.0f * f)),
		PGIntegralRect(NSMakeRect(250.0f * f,   0.0f * f, 50.0f * f, 50.0f * f))
	};
	NSPoint const centers[] = {
		PGIntegralPoint(NSMakePoint(250.0f * f, 250.0f * f)),
		PGIntegralPoint(NSMakePoint( 50.0f * f, 250.0f * f)),
		PGIntegralPoint(NSMakePoint( 50.0f * f,  50.0f * f)),
		PGIntegralPoint(NSMakePoint(250.0f * f,  50.0f * f))
	};
	for(i = numberof(corners); i--;) {
		NSRect const corner = corners[i];
		if(!PGIntersectsRectList(corner, rects, count)) continue;
		[[NSColor clearColor] set];
		NSRectFill(corners[i]);
		[[NSColor PG_bezelBackgroundColor] set];
		NSBezierPath *const path = [NSBezierPath bezierPath];
		[path moveToPoint:centers[i]];
		[path appendBezierPathWithArcWithCenter:centers[i] radius:50.0f * f startAngle:90.0f * i endAngle:90.0f * (i + 1)];
		[path closePath];
		[path fill];
	}

#if __has_feature(objc_arc)
	NSShadow *const shadow = [NSShadow new];
#else
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
#endif
	[shadow setShadowBlurRadius:4.0f];
	[shadow setShadowOffset:NSMakeSize(0.0f, -1.0f)];
	[shadow setShadowColor:[NSColor blackColor]];
	[shadow set];
}
- (void)flipHorizontally
{
#if __has_feature(objc_arc)
	NSAffineTransform *const flip = [NSAffineTransform new];
#else
	NSAffineTransform *const flip = [[[NSAffineTransform alloc] init] autorelease];
#endif
	[flip translateXBy:PGAlertViewSize yBy:0.0f];
	[flip scaleXBy:-1.0f yBy:1.0f];
	[flip concat];
}

//	MARK: -

- (void)animateOneFrame:(PGAlertView *)anAlertView {}

//	MARK: - <NSObject>

- (NSUInteger)hash
{
	return [[self class] hash];
}
- (BOOL)isEqual:(id)anObject
{
	return [anObject isMemberOfClass:[self class]];
}

@end

//	MARK: -
@implementation PGCannotGoRightGraphic

//	MARK: - PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];

	CGFloat const f = PGAlertViewSize / 300.0f;
	CGFloat const small = 5.0f * f;
	CGFloat const large = 10.0f * f;
	[[NSColor PG_bezelForegroundColor] set];

	NSBezierPath *const arrow = [NSBezierPath bezierPath];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(180.0f * f, 150.0f * f) radius:large startAngle:315.0f endAngle:45.0f];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(140.0f * f, 200.0f * f) radius:small startAngle:45.0f endAngle:90.0f];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(125.0f * f, 200.0f * f) radius:small startAngle:90.0f endAngle:180.0f];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(115.0f * f, 180.0f * f) radius:small startAngle:0.0f endAngle:270.0f clockwise:YES];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint( 75.0f * f, 170.0f * f) radius:small startAngle:90.0f endAngle:180.0f];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint( 75.0f * f, 130.0f * f) radius:small startAngle:180.0f endAngle:270.0f];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(115.0f * f, 120.0f * f) radius:small startAngle:90.0f endAngle:0.0f clockwise:YES];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(125.0f * f, 100.0f * f) radius:small startAngle:180.0f endAngle:270.0f];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(140.0f * f, 100.0f * f) radius:small startAngle:270.0f endAngle:315.0f];
	[arrow fill];

	NSBezierPath *const wall = [NSBezierPath bezierPath];
	[wall setLineWidth:20.0f * f];
	[wall setLineCapStyle:NSRoundLineCapStyle];
	[wall moveToPoint:NSMakePoint(210.0f * f, 220.0f * f)];
	[wall lineToPoint:NSMakePoint(210.0f * f,  80.0f * f)];
	[wall stroke];
}

@end

//	MARK: -
@implementation PGCannotGoLeftGraphic

//	MARK: - PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[self flipHorizontally];
	[super drawInView:anAlertView];
}

@end

//	MARK: -
@implementation PGLoopedLeftGraphic

//	MARK: - PGAlertGraphic

- (PGAlertGraphicType)graphicType
{
	return PGInterImageGraphic;
}
- (NSTimeInterval)fadeOutDelay
{
	return 1.0f;
}

//	MARK: -

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];

	[[NSColor PG_bezelForegroundColor] set];

	NSBezierPath *const s = [NSBezierPath bezierPath];
	CGFloat const f = PGAlertViewSize / 300.0f;
	[s appendBezierPathWithArcWithCenter:NSMakePoint(105.0f * f, 155.0f * f) radius:65.0f * f startAngle: 90.0f endAngle:270.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(150.0f * f,  85.0f * f) radius: 5.0f * f startAngle: 90.0f endAngle:  0.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(160.0f * f,  65.0f * f) radius: 5.0f * f startAngle:180.0f endAngle:270.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(165.0f * f,  65.0f * f) radius: 5.0f * f startAngle:270.0f endAngle:-45.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(200.0f * f, 105.0f * f) radius:10.0f * f startAngle:-45.0f endAngle: 45.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(165.0f * f, 145.0f * f) radius: 5.0f * f startAngle: 45.0f endAngle: 90.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(160.0f * f, 145.0f * f) radius: 5.0f * f startAngle: 90.0f endAngle:180.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(150.0f * f, 125.0f * f) radius: 5.0f * f startAngle:  0.0f endAngle:270.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(105.0f * f, 155.0f * f) radius:35.0f * f startAngle:270.0f endAngle: 90.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(195.0f * f, 155.0f * f) radius:35.0f * f startAngle: 90.0f endAngle:  0.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(245.0f * f, 155.0f * f) radius:15.0f * f startAngle:180.0f endAngle:  0.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(195.0f * f, 155.0f * f) radius:65.0f * f startAngle:  0.0f endAngle: 90.0f clockwise:NO];
	[s fill];
}

@end

//	MARK: -
@implementation PGLoopedRightGraphic

//	MARK: - PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[self flipHorizontally];
	[super drawInView:anAlertView];
}

@end

//	MARK: -
@implementation PGLoadingGraphic

//	MARK: +PGLoadingGraphic

+ (id)loadingGraphic
{
#if __has_feature(objc_arc)
	return [PGLoadingGraphic new];
#else
	return [[[PGLoadingGraphic alloc] init] autorelease];
#endif
}

//	MARK: - PGLoadingGraphic

- (void)setProgress:(CGFloat)progress
{
	_progress = MIN(MAX(progress, 0.0f), 1.0f);
}

//	MARK: - PGAlertGraphic

- (NSTimeInterval)fadeOutDelay
{
	return CGFLOAT_MAX;
}
- (NSTimeInterval)frameDelay
{
	return 1.0f / 12.0f;
}
- (NSUInteger)frameCount
{
	return 12;
}

//	MARK: -

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];
	CGFloat const f = PGAlertViewSize / 300.0f;
	if(_progress) {
		NSBezierPath *const progressPath = [NSBezierPath bezierPath];
		NSPoint const center = NSMakePoint(150.0f * f, 150.0f * f);
		[progressPath appendBezierPathWithArcWithCenter:center radius:110.0f * f startAngle:90.0f endAngle:90.0f - _progress * 360.0f clockwise:YES];
		[progressPath appendBezierPathWithArcWithCenter:center radius:55.0f * f startAngle:90.0f - _progress * 360.0f endAngle:90.0f clockwise:NO];
		[[NSColor PG_bezelForegroundColor] set];
		[progressPath fill];
	} else {
		[NSBezierPath PG_drawSpinnerInRect:NSMakeRect(40.0f * f, 40.0f * f, 220.0f * f, 220.0f * f) startAtPetal:[anAlertView frameCount]];
	}
}

//	MARK: -

- (void)animateOneFrame:(PGAlertView *)anAlertView
{
	CGFloat const f = PGAlertViewSize / 300.0f;
	[anAlertView setNeedsDisplayInRect:NSMakeRect( 25.0f * f, 50.0f * f,  25.0f * f, 200.0f * f)];
	[anAlertView setNeedsDisplayInRect:NSMakeRect( 50.0f * f, 25.0f * f, 200.0f * f, 250.0f * f)];
	[anAlertView setNeedsDisplayInRect:NSMakeRect(250.0f * f, 50.0f * f,  25.0f * f, 200.0f * f)];
}

//	MARK: - <NSObject>

- (NSUInteger)hash
{
	return (NSUInteger)self;
}
- (BOOL)isEqual:(id)anObject
{
	return anObject == self;
}

@end

//	MARK: -
@implementation PGBezierPathIconGraphic

//	MARK: +PGBezierPathIconGraphic

+ (id)graphicWithIconType:(AEIconType)type
{
#if __has_feature(objc_arc)
	return [[self alloc] initWithIconType:type];
#else
	return [[[self alloc] initWithIconType:type] autorelease];
#endif
}

//	MARK: - PGBezierPathIconGraphic

- (id)initWithIconType:(AEIconType)type
{
	if((self = [super init])) {
		_iconType = type;
	}
	return self;
}

//	MARK: - PGAlertGraphic

- (NSTimeInterval)fadeOutDelay
{
	return 1.0f;
}

//	MARK: -

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];
	NSRect const b = [anAlertView bounds];
	[[NSColor PG_bezelForegroundColor] set];
	[NSBezierPath PG_drawIcon:_iconType inRect:PGCenteredSizeInRect(NSMakeSize(PGAlertViewSize / 2.0f, PGAlertViewSize / 2.0f), b)];
}

//	MARK: - <NSObject>

- (NSUInteger)hash
{
	return [[self class] hash] ^ _iconType;
}
- (BOOL)isEqual:(id)anObject
{
	return [anObject isMemberOfClass:[self class]] && ((PGBezierPathIconGraphic *)anObject)->_iconType == _iconType;
}

@end
