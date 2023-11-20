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
#import "PGImageView.h"
#import <tgmath.h>

// Views
@class PGClipView;

// Other Sources
#import "PGDebug.h"
#import "PGDelayedPerforming.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

#define PGAnimateSizeChanges true
#define PGDebugDrawingModes false

#if __has_feature(objc_arc)

static __strong NSImage *PGRoundedCornerImages[4];
static NSSize PGRoundedCornerSizes[4];

@interface PGImageView ()

@property (nonatomic, assign) NSSize size;
@property (nonatomic, assign) NSSize immediateSize;
@property (nonatomic, assign) NSTimeInterval lastSizeAnimationTime;
@property (nonatomic, strong) NSTimer *sizeTransitionTimer;

@property (nonatomic, assign) NSUInteger pauseCount;

@property (nonatomic, assign) NSUInteger imageRepHash;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, assign) BOOL isPDF;
@property (nonatomic, assign) NSUInteger numberOfFrames;
//@property (nonatomic, assign) CGLayerRef _cacheLayer;		2023/10/16 removed; -setUsesCaching: is now a no-op
@property (nonatomic, assign) BOOL awaitingUpdate;

- (void)_runAnimationTimer;
- (void)_animate;
- (void)_invalidateCache;
- (void)_cache;
//	2023/10/16 replaced with -_drawImageWithFrame:
//- (void)_drawImageWithFrame:(NSRect)aRect compositeCopy:(BOOL)compositeCopy rects:(NSRect const *)rects count:(NSUInteger)count;
- (void)_drawImageWithFrame:(NSRect)aRect;
@property(readonly) BOOL _shouldDrawRoundedCorners;
- (BOOL)_needsToDrawRoundedCornersForImageRect:(NSRect)r rects:(NSRect const *)rects count:(NSUInteger)count;
- (void)_getRoundedCornerRects:(NSRectArray)rects forRect:(NSRect)r;
- (NSAffineTransform *)_transformWithRotationInDegrees:(CGFloat)val;
- (BOOL)_setSize:(NSSize)size;
- (void)_sizeTransitionOneFrame;
- (void)_updateFrameSize;
- (void)_update;
@end

#else

static NSImage *PGRoundedCornerImages[4];
static NSSize PGRoundedCornerSizes[4];

@interface PGImageView(Private)

@property(readonly) BOOL _imageIsOpaque;
- (void)_runAnimationTimer;
- (void)_animate;
- (void)_invalidateCache;
- (void)_cache;
//	2023/10/16 replaced with -_drawImageWithFrame:
//- (void)_drawImageWithFrame:(NSRect)aRect compositeCopy:(BOOL)compositeCopy rects:(NSRect const *)rects count:(NSUInteger)count;
- (void)_drawImageWithFrame:(NSRect)aRect;
@property(readonly) BOOL _shouldDrawRoundedCorners;
- (BOOL)_needsToDrawRoundedCornersForImageRect:(NSRect)r rects:(NSRect const *)rects count:(NSUInteger)count;
- (void)_getRoundedCornerRects:(NSRectArray)rects forRect:(NSRect)r;
- (NSAffineTransform *)_transformWithRotationInDegrees:(CGFloat)val;
- (BOOL)_setSize:(NSSize)size;
- (void)_sizeTransitionOneFrame;
- (void)_updateFrameSize;
- (void)_update;

@end

#endif

//	MARK: -
@implementation PGImageView

//	MARK: +PGImageView

+ (NSArray *)pasteboardTypes
{
	return [NSArray arrayWithObjects:NSPasteboardTypeTIFF, nil];
}

//	MARK: +NSObject

+ (void)initialize
{
	if([PGImageView class] != self) return;
	[self exposeBinding:@"animates"];
	[self exposeBinding:@"antialiasWhenUpscaling"];
	[self exposeBinding:@"usesRoundedCorners"];

#if __has_feature(objc_arc)
	PGRoundedCornerImages[PGMinXMinYCorner] = [NSImage imageNamed:@"Corner-Bottom-Left"];
	PGRoundedCornerImages[PGMaxXMinYCorner] = [NSImage imageNamed:@"Corner-Bottom-Right"];
	PGRoundedCornerImages[PGMinXMaxYCorner] = [NSImage imageNamed:@"Corner-Top-Left"];
	PGRoundedCornerImages[PGMaxXMaxYCorner] = [NSImage imageNamed:@"Corner-Top-Right"];
#else
	PGRoundedCornerImages[PGMinXMinYCorner] = [[NSImage imageNamed:@"Corner-Bottom-Left"] retain];
	PGRoundedCornerImages[PGMaxXMinYCorner] = [[NSImage imageNamed:@"Corner-Bottom-Right"] retain];
	PGRoundedCornerImages[PGMinXMaxYCorner] = [[NSImage imageNamed:@"Corner-Top-Left"] retain];
	PGRoundedCornerImages[PGMaxXMaxYCorner] = [[NSImage imageNamed:@"Corner-Top-Right"] retain];
#endif
	PGRoundedCornerSizes[PGMinXMinYCorner] = [PGRoundedCornerImages[PGMinXMinYCorner] size];
	PGRoundedCornerSizes[PGMaxXMinYCorner] = [PGRoundedCornerImages[PGMaxXMinYCorner] size];
	PGRoundedCornerSizes[PGMinXMaxYCorner] = [PGRoundedCornerImages[PGMinXMaxYCorner] size];
	PGRoundedCornerSizes[PGMaxXMaxYCorner] = [PGRoundedCornerImages[PGMaxXMaxYCorner] size];
}

//	MARK: - PGImageView

- (NSSize)size
{
	return _sizeTransitionTimer ? _size : _immediateSize;
}
- (NSSize)originalSize
{
	return PGRotated90CCW & _orientation ? NSMakeSize([_rep pixelsHigh], [_rep pixelsWide]) : NSMakeSize([_rep pixelsWide], [_rep pixelsHigh]);
}
- (CGFloat)averageScaleFactor
{
	NSSize const s = [self size];
	NSSize const o = [self originalSize];
	return (s.width / o.width + s.height / o.height) / 2.0f;
}
- (void)setRotationInDegrees:(CGFloat)val
{
	if(val == _rotationInDegrees) return;
	_rotationInDegrees = remainderf(val, 360.0f);
	[self _updateFrameSize];
	[self setNeedsDisplay:YES];
}
- (void)setAntialiasWhenUpscaling:(BOOL)flag
{
	if(flag == _antialiasWhenUpscaling) return;
	_antialiasWhenUpscaling = flag;
	[self _invalidateCache];
	[self setNeedsDisplay:YES];
}
- (NSImageInterpolation)interpolation
{
//NSLog(@"_sizeTransitionTimer %@  self.inLiveResize %u  self.canAnimateRep %u  self animates %u  %s",
//_sizeTransitionTimer, self.inLiveResize, self.canAnimateRep, self.animates,
//_sizeTransitionTimer || [self inLiveResize] || ([self canAnimateRep] && [self animates]) ? "NSImageInterpolationNone" : "...");
	if(_sizeTransitionTimer || [self inLiveResize] || ([self canAnimateRep] && [self animates])) return NSImageInterpolationNone;
	if([self antialiasWhenUpscaling]) return NSImageInterpolationHigh;
	NSSize const imageSize = NSMakeSize([_rep pixelsWide], [_rep pixelsHigh]), viewSize = [self size];

//NSLog(@"imageSize.width %5.2f  viewSize.width %5.2f  imageSize.height %5.2f  viewSize.height %5.2f  result %s",
//imageSize.width, viewSize.width, imageSize.height, viewSize.height,
//imageSize.width < viewSize.width && imageSize.height < viewSize.height ? "NSImageInterpolationNone" : "NSImageInterpolationHigh");
	return imageSize.width < viewSize.width && imageSize.height < viewSize.height ? NSImageInterpolationNone : NSImageInterpolationHigh;
}
- (void)setUsesRoundedCorners:(BOOL)flag
{
	if(flag == _usesRoundedCorners) return;
	_usesRoundedCorners = flag;
	[self _invalidateCache];
	[self setNeedsDisplay:YES];
}
- (void)setUsesCaching:(BOOL)flag
{
	if(flag == _usesCaching) return;
	_usesCaching = flag;

	//	2023/10/16 since caching is no longer done, do nothing
//	if(flag) [self setNeedsDisplay:YES];
//	else [self _invalidateCache];
}

//	MARK: -

- (BOOL)canAnimateRep
{
	return _numberOfFrames > 1;
}
- (void)setAnimates:(BOOL)flag
{
	if(flag == _animates) return;
	_animates = flag;
	if(flag) [self _invalidateCache];
	else if([self antialiasWhenUpscaling]) [self setNeedsDisplay:YES];
	[self _runAnimationTimer];
}
- (BOOL)isPaused
{
	return !_pauseCount;
}
- (void)setPaused:(BOOL)flag
{
	if(flag) ++_pauseCount;
	else {
		NSParameterAssert(_pauseCount);
		--_pauseCount;
	}
	[self _runAnimationTimer];
}

//	MARK: -

- (void)setImageRep:(NSImageRep *)rep orientation:(PGOrientation)orientation size:(NSSize)size
{
	[self _invalidateCache];
	[self setNeedsDisplay:YES];

	//	rep equality is not sufficient: this method is called with the same rep but different
	//	parameters such as orientation or size or a different page in the *same* rep (when
	//	rep is a NSPDFImageRep). To handle the case of same-rep-but-different-page, the rep's
	//	hash is compared, where the hash includes the current page's index
	NSUInteger imageRepHash = rep.hash;
	if([rep isKindOfClass:NSPDFImageRep.class])
		imageRepHash ^= ((NSPDFImageRep *)rep).currentPage;
//NSLog(@"rep %p   imageRepHash 0x%lX", rep, imageRepHash);
	if(orientation == _orientation && rep == _rep && imageRepHash == _imageRepHash &&
		!_sizeTransitionTimer && NSEqualSizes(size, _immediateSize))
		return;

	_orientation = orientation;
	[_image setSize:NSMakeSize([rep pixelsWide], [rep pixelsHigh])];
	if(rep != _rep) {
		[_image removeRepresentation:_rep];
#if !__has_feature(objc_arc)
		[_rep release];
#endif
		_rep = nil;

		[self setSize:size allowAnimation:NO];
#if __has_feature(objc_arc)
		_rep = rep;
#else
		_rep = [rep retain];
#endif
		[_image addRepresentation:_rep];

		[_image recache];
		_imageRepHash = imageRepHash;

		_isPDF = [_rep isKindOfClass:[NSPDFImageRep class]];
		_numberOfFrames = [_rep isKindOfClass:[NSBitmapImageRep class]] ?
			[[(NSBitmapImageRep *)_rep valueForProperty:NSImageFrameCount] unsignedIntegerValue] : 1;

		[self _runAnimationTimer];
	} else {
		[self setSize:size allowAnimation:NO];

		if(imageRepHash != _imageRepHash) {
			[_image recache];
			_imageRepHash = imageRepHash;
		}
	}
}
- (void)setSize:(NSSize)size allowAnimation:(BOOL)flag
{
	if(!PGAnimateSizeChanges || !flag) {
		_size = size;
		return [self stopAnimatedSizeTransition];
	}
	if(NSEqualSizes(size, [self size])) return;
	_size = size;
	if(!_sizeTransitionTimer)
#if __has_feature(objc_arc)
		_sizeTransitionTimer = [self PG_performSelector:@selector(_sizeTransitionOneFrame)
											 withObject:nil
											   fireDate:nil
											   interval:PGAnimationFramerate
												options:PGRepeatOnInterval];
#else
		_sizeTransitionTimer = [[self PG_performSelector:@selector(_sizeTransitionOneFrame)
											  withObject:nil
												fireDate:nil
												interval:PGAnimationFramerate
												 options:PGRepeatOnInterval] retain];
#endif
}
- (void)stopAnimatedSizeTransition
{
	[_sizeTransitionTimer invalidate];
#if !__has_feature(objc_arc)
	[_sizeTransitionTimer release];
#endif
	_sizeTransitionTimer = nil;
	_lastSizeAnimationTime = 0.0f;
	[self _setSize:_size];
	[self setNeedsDisplay:YES];
}
- (NSPoint)rotateByDegrees:(CGFloat)val adjustingPoint:(NSPoint)aPoint
{
	NSRect const b1 = [self bounds];
	NSPoint const p = PGOffsetPointByXY(aPoint, -NSMidX(b1), -NSMidY(b1)); // Our bounds are going to change to fit the rotated image. Any point we want to remain constant relative to the image, we have to make relative to the bounds' center, since that's where the image is drawn.
	[self setRotationInDegrees:[self rotationInDegrees] + val];
	NSRect const b2 = [self bounds];
	return [[self _transformWithRotationInDegrees:val] transformPoint:PGOffsetPointByXY(p, NSMidX(b2), NSMidY(b2))];
}

//	MARK: -

- (BOOL)writeToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
	if(![types containsObject:NSPasteboardTypeTIFF]) return NO;
	if(!_rep || ![_rep respondsToSelector:@selector(TIFFRepresentation)]) return NO;
	if(pboard) {
		[pboard addTypes:[NSArray arrayWithObject:NSPasteboardTypeTIFF] owner:nil];
		[pboard setData:[(NSBitmapImageRep *)_rep TIFFRepresentation] forType:NSPasteboardTypeTIFF];
	}
	return YES;
}

//	MARK: -

- (void)appDidHide:(NSNotification *)aNotif
{
	self.paused = YES;
}
- (void)appDidUnhide:(NSNotification *)aNotif
{
	self.paused = NO;
}

//	MARK: - PGImageView(Private)

- (BOOL)_imageIsOpaque
{
	return _isPDF || [_rep isOpaque];
}
- (void)_runAnimationTimer
{
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(_animate) object:nil];
	if([self canAnimateRep] && _animates && !_pauseCount) [self PG_performSelector:@selector(_animate) withObject:nil fireDate:nil interval:[[(NSBitmapImageRep *)_rep valueForProperty:NSImageCurrentFrameDuration] doubleValue] options:kNilOptions];
}
- (void)_animate
{
	NSUInteger const i = [[(NSBitmapImageRep *)_rep valueForProperty:NSImageCurrentFrame] unsignedIntegerValue] + 1;
	[(NSBitmapImageRep *)_rep setProperty:NSImageCurrentFrame withValue:[NSNumber numberWithUnsignedInteger:i % _numberOfFrames]];
	[self setNeedsDisplay:YES];
	[self _runAnimationTimer];
}
- (void)_invalidateCache
{
//	CGLayerRelease(_cacheLayer);	2023/10/16 removed
//	_cacheLayer = NULL;
}
- (void)_cache
{
	if(//_cacheLayer ||	2023/10/16 removed
		!_rep || ([self canAnimateRep] && [self animates]) || ![self usesCaching] || [self inLiveResize] || _sizeTransitionTimer) return;
	NSString *const runLoopMode = [[NSRunLoop currentRunLoop] currentMode];
	if(!runLoopMode || PGEqualObjects(runLoopMode, NSEventTrackingRunLoopMode)) {
		if(!_awaitingUpdate) [self performSelector:@selector(_update) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
		_awaitingUpdate = YES;
		return;
	}
/*	2023/10/16 removed
#if 1
	NSGraphicsContext *const oldContext = [NSGraphicsContext currentContext];
	CGLayerRef const layer = CGLayerCreateWithContext(oldContext.CGContext,
									NSSizeToCGSize(_immediateSize), NULL);
#else
	CGContextRef const windowContext = [[[self window] graphicsContext] CGContext];
	NSParameterAssert(windowContext);
	CGLayerRef const layer = CGLayerCreateWithContext(windowContext, NSSizeToCGSize(_immediateSize), NULL);
	NSGraphicsContext *const oldContext = [NSGraphicsContext currentContext];
#endif
	NSGraphicsContext *const layerContext = [NSGraphicsContext graphicsContextWithCGContext:CGLayerGetContext(layer) flipped:[self isFlipped]];
	[NSGraphicsContext setCurrentContext:layerContext];
	NSRect const b = (NSRect){NSZeroPoint, _immediateSize};
	[self _drawImageWithFrame:b compositeCopy:YES rects:NULL count:0];
	[layerContext flushGraphics];
	[NSGraphicsContext setCurrentContext:oldContext];
	_cacheLayer = layer;	*/
}
/*	2023/10/16 replaced by -_drawImageWithFrame:
- (void)_drawImageWithFrame:(NSRect)aRect compositeCopy:(BOOL)compositeCopy rects:(NSRect const *)rects count:(NSUInteger)count
{
	BOOL const roundedCorners = [self _needsToDrawRoundedCornersForImageRect:aRect rects:rects count:count];
	BOOL const useTransparencyLayer = roundedCorners && !compositeCopy;
	CGContextRef const context = [[NSGraphicsContext currentContext] CGContext];
	if(useTransparencyLayer) CGContextBeginTransparencyLayer(context, NULL);

	if(_isPDF) {
		[[NSColor whiteColor] set];
		if(rects) NSRectFillList(rects, count);
		else NSRectFill(aRect);
	}
//	NSSize const actualSize = NSMakeSize([_rep pixelsWide], [_rep pixelsHigh]);
//	NSSize const s = NSMakeSize(actualSize.width / _immediateSize.width, actualSize.height / _immediateSize.height);

	NSRect r = aRect;
	NSAffineTransform *transform = nil;
	if(PGUpright != _orientation) {
		transform = [NSAffineTransform PG_transformWithRect:&r orientation:_orientation];
		[transform concat];
	}
	NSCompositingOperation const op = !_isPDF && (compositeCopy || [_rep isOpaque]) ? NSCompositingOperationCopy : NSCompositingOperationSourceOver;
	NSDictionary *const hints = @{NSImageHintInterpolation: [NSNumber numberWithUnsignedLong:[self interpolation]]};
	if(rects && PGUpright == _orientation) {
		NSInteger i = count;
		while(i--)
			[_image drawInRect:rects[i]
					  fromRect:NSMakeRect(NSMinX(rects[i]) * s.width, NSMinY(rects[i]) * s.height, NSWidth(rects[i]) * s.width, NSHeight(rects[i]) * s.height)
					 operation:op
					  fraction:1.0f
				respectFlipped:YES
						 hints:hints];
	} else
		[_image drawInRect:r
				  fromRect:NSZeroRect
				 operation:op
				  fraction:1.0f
			respectFlipped:YES
					 hints:hints];
	if(roundedCorners) {
		NSUInteger i;
		NSRect corners[4];
		[self _getRoundedCornerRects:corners forRect:r];
		for(i = 0; i < 4; i++)
			[PGRoundedCornerImages[i] drawAtPoint:corners[i].origin
										 fromRect:NSZeroRect
										operation:NSCompositingOperationDestinationOut
										 fraction:1];
	}

	if(transform) {
		[transform invert];
		[transform concat];
	}

	if(useTransparencyLayer) CGContextEndTransparencyLayer(context);
}
 */
- (void)_drawImageWithFrame:(NSRect)aRect
{
	BOOL const roundedCorners = [self _needsToDrawRoundedCornersForImageRect:aRect rects:NULL count:0];
	BOOL const useTransparencyLayer = roundedCorners;
	CGContextRef const context = useTransparencyLayer ? [[NSGraphicsContext currentContext] CGContext] : NULL;
	if(useTransparencyLayer)
		CGContextBeginTransparencyLayer(context, NULL);

	if(_isPDF) {
		[[NSColor whiteColor] set];
		NSRectFill(aRect);
	}

	NSRect r = aRect;
	NSAffineTransform *transform = nil;
	if(PGUpright != _orientation) {
		transform = [NSAffineTransform PG_transformWithRect:&r orientation:_orientation];
		[transform concat];
	}
	NSCompositingOperation const op = (!_isPDF && [_rep isOpaque]) ?
										NSCompositingOperationCopy : NSCompositingOperationSourceOver;
	NSDictionary *const hints = @{NSImageHintInterpolation: [NSNumber numberWithUnsignedLong:[self interpolation]]};
	[_image drawInRect:r
			  fromRect:NSZeroRect
			 operation:op
			  fraction:1.0f
		respectFlipped:YES
				 hints:hints];

	if(roundedCorners) {
		NSUInteger i;
		NSRect corners[4];
		[self _getRoundedCornerRects:corners forRect:r];
		for(i = 0; i < 4; i++)
			[PGRoundedCornerImages[i] drawAtPoint:corners[i].origin
										 fromRect:NSZeroRect
										operation:NSCompositingOperationDestinationOut
										 fraction:1.0f];
	}

	if(transform) {
		[transform invert];
		[transform concat];
	}

	if(useTransparencyLayer)
		CGContextEndTransparencyLayer(context);
}
- (BOOL)_shouldDrawRoundedCorners
{
	return _usesRoundedCorners && _immediateSize.width > 64.0f && _immediateSize.height > 64.0f;
}
- (BOOL)_needsToDrawRoundedCornersForImageRect:(NSRect)r rects:(NSRect const *)rects count:(NSUInteger)count
{
	if(!self._shouldDrawRoundedCorners) return NO;
	if(!rects) return YES;
	NSRect corners[4];
	[self _getRoundedCornerRects:corners forRect:r];
	NSUInteger i, j;
	for(i = 0; i < count; i++) for(j = 0; j < 4; j++) if(NSIntersectsRect(rects[i], corners[j])) return YES;
	return NO;
}
- (void)_getRoundedCornerRects:(NSRectArray)rects forRect:(NSRect)r
{
	NSParameterAssert(rects);
	rects[PGMinXMinYCorner] = NSMakeRect(NSMinX(r), NSMinY(r), PGRoundedCornerSizes[PGMinXMinYCorner].width, PGRoundedCornerSizes[PGMinXMinYCorner].height);
	rects[PGMaxXMinYCorner] = NSMakeRect(NSMaxX(r) - PGRoundedCornerSizes[PGMaxXMinYCorner].width, NSMinY(r), PGRoundedCornerSizes[PGMaxXMinYCorner].width, PGRoundedCornerSizes[PGMaxXMinYCorner].height);
	rects[PGMinXMaxYCorner] = NSMakeRect(NSMinX(r), NSMaxY(r) - PGRoundedCornerSizes[PGMinXMaxYCorner].height, PGRoundedCornerSizes[PGMinXMaxYCorner].width, PGRoundedCornerSizes[PGMinXMaxYCorner].height);
	rects[PGMaxXMaxYCorner] = NSMakeRect(NSMaxX(r) - PGRoundedCornerSizes[PGMaxXMaxYCorner].width, NSMaxY(r) - PGRoundedCornerSizes[PGMaxXMaxYCorner].height, PGRoundedCornerSizes[PGMaxXMaxYCorner].width, PGRoundedCornerSizes[PGMaxXMaxYCorner].height);
}
- (NSAffineTransform *)_transformWithRotationInDegrees:(CGFloat)val
{
	NSRect const b = [self bounds];
	NSAffineTransform *const t = [NSAffineTransform transform];
	[t translateXBy:NSMidX(b) yBy:NSMidY(b)];
	[t rotateByDegrees:val];
	[t translateXBy:-NSMidX(b) yBy:-NSMidY(b)];
	return t;
}
- (BOOL)_setSize:(NSSize)size
{
	if(NSEqualSizes(size, _immediateSize)) return NO;
	_immediateSize = size;
	[self _updateFrameSize];
	return YES;
}
- (void)_sizeTransitionOneFrame
{
	NSSize const r = NSMakeSize(_size.width - _immediateSize.width, _size.height - _immediateSize.height);
	CGFloat const dist = hypotf(r.width, r.height);
	CGFloat const factor = MIN(1.0f, MAX(0.33f, 20.0f / dist) * PGLagCounteractionSpeedup(&_lastSizeAnimationTime, PGAnimationFramerate));
	if(dist < 1.0f || ![self _setSize:NSMakeSize(_immediateSize.width + r.width * factor, _immediateSize.height + r.height * factor)]) [self stopAnimatedSizeTransition];
}
- (void)_updateFrameSize
{
	NSSize s = _immediateSize;
	CGFloat const r = [self rotationInDegrees] / 180.0f * (CGFloat)M_PI;
	if(r) s = NSMakeSize(ceil(fabs(cosf(r)) * s.width + fabs(sinf(r)) * s.height), ceil(fabs(cosf(r)) * s.height + fabs(sinf(r)) * s.width));
	if(NSEqualSizes(s, [self frame].size)) return;
	[super setFrameSize:s];
	[self _invalidateCache];
}
- (void)_update
{
	_awaitingUpdate = NO;
	[self setNeedsDisplay:YES];
}

//	MARK: - NSView

- (id)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_image = [[NSImage alloc] init];
		//	2023/10/16 with the removal of caching, the cache mode is now set in -setImageRep:orientation:size:
	//	[_image setCacheMode:NSImageCacheNever]; // We do our own caching.
		_usesCaching = YES;
		_antialiasWhenUpscaling = YES;
		_usesRoundedCorners = YES;
		[NSApp PG_addObserver:self selector:@selector(appDidHide:) name:NSApplicationDidHideNotification];
		[NSApp PG_addObserver:self selector:@selector(appDidUnhide:) name:NSApplicationDidUnhideNotification];
	}
	return self;
}

- (BOOL)wantsDefaultClipping
{
	return NO;	//	return !!_cacheLayer;	2023/10/16 removed
}
- (BOOL)isOpaque
{
	return self._imageIsOpaque && !self._shouldDrawRoundedCorners && ![self rotationInDegrees];
}
- (void)drawRect:(NSRect)aRect
{
	if(!_rep) return;
	NSRect const b = [self bounds];
	NSRect const imageRect = NSMakeRect(
		round(NSMidX(b) - _immediateSize.width / 2.0f),
		round(NSMidY(b) - _immediateSize.height / 2.0f),
		_immediateSize.width, _immediateSize.height);
	CGFloat const deg = [self rotationInDegrees];
	if(deg) {
		[NSGraphicsContext saveGraphicsState];
		[[self _transformWithRotationInDegrees:deg] concat];
	}

	//	2023/10/16 with no caching, a simpler drawing function is now used;
	//	the image is drawn as directly as possible to produce the best possible
	//	visual quality. Caching was removed because:
	//	* for PDFs, a lower resolution image was rendered on high-DPI displays,
	//	* for non-PDFs, it has no visual or performance benefits (AppKit is now
	//		optimised well for high-DPI screens and performance).
	[self _drawImageWithFrame:imageRect];
/*	//	2023/10/16 removed caching
	[self _cache];
	if(_cacheLayer)
		CGContextDrawLayerAtPoint(NSGraphicsContext.currentContext.CGContext,
							NSPointToCGPoint(imageRect.origin), _cacheLayer);
	else {
		NSInteger count = 0;
		NSRect const *rects = NULL;
		if(!deg) [self getRectsBeingDrawn:&rects count:&count];
		[self _drawImageWithFrame:imageRect compositeCopy:NO rects:rects count:count];
	}	*/
#if PGDebugDrawingModes
	//	2023/10/16 removed
//	[(_cacheLayer ? [NSColor redColor] : [NSColor greenColor]) set];
//	NSFrameRect(NSInsetRect(imageRect, 0.5f, 0.5f)); // Outer-most frame: Cached

	[([self isOpaque] ? [NSColor redColor] : [NSColor greenColor]) set];
	NSFrameRect(NSInsetRect(imageRect, 2.5f, 2.5f)); // Next-inner frame: View opaque

	[([self _imageIsOpaque] ? [NSColor redColor] : [NSColor greenColor]) set];
	NSFrameRect(NSInsetRect(imageRect, 4.5f, 4.5f)); // Next-inner frame: Image opaque

	[(deg ? [NSColor greenColor] : [NSColor redColor]) set];
	NSFrameRect(NSInsetRect(imageRect, 6.5f, 6.5f)); // Next-inner frame: Rotated

	//	Currently, the only implementation of "make a full screen window" is to make
	//	a borderless window whose size is the same as the monitor is should lie on;
	//	no code exists to use the system's method of creating a fullscreen window;
	//	when it is possible to do that, this code will need to be changed; search
	//	for NSWindowStyleMaskBorderless to find the code that will need modifying.
	[(NSWindowStyleMaskBorderless == self.window.styleMask ? [NSColor redColor] : [NSColor greenColor]) set];
	NSFrameRect(NSInsetRect(imageRect, 8.5f, 8.5f)); // Inner-most frame: fullscreen
#endif
	if(deg) [NSGraphicsContext restoreGraphicsState];
}
- (void)setFrameSize:(NSSize)aSize
{
	PGAssertNotReached(@"-[PGImageView setFrameSize:] should not be invoked directly. Use -setSize: instead.");
}
- (void)viewWillStartLiveResize
{
	[super viewWillStartLiveResize];
	[self _invalidateCache];
}
- (void)viewDidEndLiveResize
{
	[super viewDidEndLiveResize];
	[self setNeedsDisplay:YES];
}
- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
	[super viewWillMoveToWindow:aWindow];
	[self _invalidateCache];
}

//	MARK: - NSView(PGClipViewAdditions)

- (BOOL)PG_acceptsClicksInClipView:(PGClipView *)sender
{
	return NO;
}
- (BOOL)PG_scalesContentWithFrameSizeInClipView:(PGClipView *)sender
{
	return YES;
}

//	MARK: - NSObject

- (id)init
{
	return [self initWithFrame:NSZeroRect];
}
- (void)dealloc
{
	[self PG_cancelPreviousPerformRequests];
	[self PG_removeObserver];
	[self stopAnimatedSizeTransition];
	[self unbind:@"animates"];
	[self unbind:@"antialiasWhenUpscaling"];
	[self unbind:@"usesRoundedCorners"];
	[self setImageRep:nil orientation:PGUpright size:NSZeroSize];
	NSParameterAssert(!_rep);
	[self _invalidateCache];
	[self setAnimates:NO];
#if !__has_feature(objc_arc)
	[_image release];
	[super dealloc];
#endif
}

@end
