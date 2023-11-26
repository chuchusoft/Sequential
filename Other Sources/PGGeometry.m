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
#import "PGGeometry.h"
#include <tgmath.h>

//	MARK: NSPoint

NSPoint PGIntegralPoint(NSPoint aPoint)
{
	return NSMakePoint(round(aPoint.x), round(aPoint.y));
}
NSPoint PGOffsetPointBySize(NSPoint aPoint, NSSize aSize)
{
	return NSMakePoint(aPoint.x + aSize.width, aPoint.y + aSize.height);
}
NSPoint PGOffsetPointByXY(NSPoint aPoint, CGFloat x, CGFloat y)
{
	return NSMakePoint(aPoint.x + x, aPoint.y + y);
}
NSSize PGPointDiff(NSPoint p1, NSPoint p2)
{
	return NSMakeSize(p1.x - p2.x, p1.y - p2.y);
}

//	MARK: - NSSize

NSSize PGScaleSizeByXY(NSSize size, CGFloat scaleX, CGFloat scaleY)
{
	return NSMakeSize(size.width * scaleX, size.height * scaleY);
}
NSSize PGScaleSizeByFloat(NSSize size, CGFloat scale)
{
	return PGScaleSizeByXY(size, scale, scale);
}
NSSize PGIntegralSize(NSSize s)
{
	return NSMakeSize(round(s.width), round(s.height));
}

//	MARK: - NSRect

NSRect PGCenteredSizeInRect(NSSize s, NSRect r)
{
	return NSMakeRect(NSMidX(r) - s.width / 2, NSMidY(r) - s.height / 2, s.width, s.height);
}
BOOL PGIntersectsRectList(NSRect rect, NSRect const *list, NSUInteger count)
{
	NSUInteger i = count;
	while(i--) if(NSIntersectsRect(rect, list[i])) return YES;
	return NO;
}
NSRect PGIntegralRect(NSRect r)
{
	return NSMakeRect(round(NSMinX(r)), round(NSMinY(r)), round(NSWidth(r)), round(NSHeight(r)));
}
void PGGetRectDifference(NSRect diff[4], NSUInteger *count, NSRect minuend, NSRect subtrahend)
{
	if(NSIsEmptyRect(subtrahend)) {
		diff[0] = minuend;
		*count = 1;
		return;
	}
	NSUInteger i = 0;
	diff[i] = NSMakeRect(NSMinX(minuend), NSMaxY(subtrahend), NSWidth(minuend), MAX(NSMaxY(minuend) - NSMaxY(subtrahend), 0.0f));
	if(!NSIsEmptyRect(diff[i])) i++;
	diff[i] = NSMakeRect(NSMinX(minuend), NSMinY(minuend), NSWidth(minuend), MAX(NSMinY(subtrahend) - NSMinY(minuend), 0.0f));
	if(!NSIsEmptyRect(diff[i])) i++;
	CGFloat const sidesMinY = MAX(NSMinY(minuend), NSMinY(subtrahend));
	CGFloat const sidesHeight = NSMaxY(subtrahend) - MAX(NSMinY(minuend), NSMinY(subtrahend));
	diff[i] = NSMakeRect(NSMinX(minuend), sidesMinY, MAX(NSMinX(subtrahend) - NSMinX(minuend), 0.0f), sidesHeight);
	if(!NSIsEmptyRect(diff[i])) i++;
	diff[i] = NSMakeRect(NSMaxX(subtrahend), sidesMinY, MAX(NSMaxX(minuend) - NSMaxX(subtrahend), 0.0f), sidesHeight);
	if(!NSIsEmptyRect(diff[i])) i++;
	*count = i;
}
NSRect PGScaleRect(NSRect r, CGFloat scaleX, CGFloat scaleY)
{
	return NSMakeRect(NSMinX(r) * scaleX, NSMinY(r) * scaleY, NSWidth(r) * scaleX, NSHeight(r) * scaleY);
}

//	MARK: - PGRectEdgeMask

NSSize PGRectEdgeMaskToSizeWithMagnitude(PGRectEdgeMask mask, CGFloat magnitude)
{
	NSCParameterAssert(!PGHasContradictoryRectEdges(mask));
	NSSize size = NSZeroSize;
	if(mask & PGMinXEdgeMask) size.width = -magnitude;
	else if(mask & PGMaxXEdgeMask) size.width = magnitude;
	if(mask & PGMinYEdgeMask) size.height = -magnitude;
	else if(mask & PGMaxYEdgeMask) size.height = magnitude;
	return size;
}
NSPoint PGRectEdgeMaskToPointWithMagnitude(PGRectEdgeMask mask, CGFloat magnitude)
{
	NSSize const s = PGRectEdgeMaskToSizeWithMagnitude(mask, magnitude);
	return NSMakePoint(s.width, s.height);
}
NSPoint PGPointOfPartOfRect(NSRect r, PGRectEdgeMask mask)
{
	NSPoint p;
	switch(PGHorzEdgesMask & mask) {
		case PGHorzEdgesMask:
		case PGNoEdges:      p.x = NSMidX(r); break;
		case PGMinXEdgeMask: p.x = NSMinX(r); break;
		case PGMaxXEdgeMask: p.x = NSMaxX(r); break;
	}
	switch(PGVertEdgesMask & mask) {
		case PGVertEdgesMask:
		case PGNoEdges:      p.y = NSMidY(r); break;
		case PGMinYEdgeMask: p.y = NSMinY(r); break;
		case PGMaxYEdgeMask: p.y = NSMaxY(r); break;
	}
	return p;
}
PGRectEdgeMask PGPointToRectEdgeMaskWithThreshhold(NSPoint p, CGFloat threshhold)
{
	CGFloat const t = fabs(threshhold);
	PGRectEdgeMask direction = PGNoEdges;
	if(p.x <= -t) direction |= PGMinXEdgeMask;
	else if(p.x >= t) direction |= PGMaxXEdgeMask;
	if(p.y <= -t) direction |= PGMinYEdgeMask;
	else if(p.y >= t) direction |= PGMaxYEdgeMask;
	return direction;
}
PGRectEdgeMask PGNonContradictoryRectEdges(PGRectEdgeMask mask)
{
	PGRectEdgeMask r = mask;
	if((r & PGHorzEdgesMask) == PGHorzEdgesMask) r &= ~PGHorzEdgesMask;
	if((r & PGVertEdgesMask) == PGVertEdgesMask) r &= ~PGVertEdgesMask;
	return r;
}
BOOL PGHasContradictoryRectEdges(PGRectEdgeMask mask)
{
	return PGNonContradictoryRectEdges(mask) != mask;
}

//	MARK: - PGPageLocation

PGRectEdgeMask PGReadingDirectionAndLocationToRectEdgeMask(PGPageLocation loc, PGReadingDirection dir)
{
	NSCParameterAssert(PGPreserveLocation != loc);
	BOOL const ltr = dir == PGReadingDirectionLeftToRight;
	switch(loc) {
		case PGPreserveLocation: break;
		case PGHomeLocation: return PGMaxYEdgeMask | (ltr ? PGMinXEdgeMask : PGMaxXEdgeMask);
		case PGEndLocation: return PGMinYEdgeMask | (ltr ? PGMaxXEdgeMask : PGMinXEdgeMask);
		case PGEndTopLocation: return PGMaxYEdgeMask | (ltr ? PGMaxXEdgeMask : PGMinXEdgeMask);
	}
	return PGNoEdges;
}

//	MARK: - PGOrientation

PGOrientation PGOrientationWithTIFFOrientation(NSUInteger orientation)
{
	switch(orientation) {
		case 2: return PGFlippedHorz;
		case 3: return PGUpsideDown;
		case 4: return PGFlippedVert;
		case 5: return PGRotated90CCW | PGFlippedHorz;
		case 6: return PGRotated90CW;
		case 7: return PGRotated90CCW | PGFlippedVert;
		case 8: return PGRotated90CCW;
		default: return PGUpright;
	}
}
PGOrientation PGAddOrientation(PGOrientation o1, PGOrientation o2)
{
	PGOrientation n1 = o1, n2 = o2;
	if(o1 & PGRotated90CCW && !(o2 & PGRotated90CCW)) n2 = ((o2 & PGFlippedHorz) >> 1) | ((o2 & PGFlippedVert) << 1);
	PGOrientation r = n1 ^ n2;
	if(o1 & PGRotated90CCW && o2 & PGRotated90CCW) r ^= PGUpsideDown;
	return r;
}
NSString *PGLocalizedStringWithOrientation(PGOrientation orientation)
{
	// TODO: Add these to the Localizable.strings files.
	switch(orientation) {
		case PGFlippedHorz: return NSLocalizedString(@"Flipped Horizontally", nil);
		case PGUpsideDown: return NSLocalizedString(@"Upside Down", nil);
		case PGFlippedVert: return NSLocalizedString(@"Flipped Vertically", nil);
		case PGRotated90CCW | PGFlippedHorz: return NSLocalizedString(@"Rotated CCW & Flipped Horizontally", nil);
		case PGRotated90CW: return NSLocalizedString(@"Rotated CW", nil);
		case PGRotated90CCW | PGFlippedVert: return NSLocalizedString(@"Rotated CCW & Flipped Vertically", nil);
		case PGRotated90CCW: return NSLocalizedString(@"Rotated CCW", nil);
		default: return NSLocalizedString(@"Upright", nil);
	}
}

//	MARK: - PGInset

PGInset const PGZeroInset = {0.0f, 0.0f, 0.0f, 0.0f};

PGInset PGMakeInset(CGFloat minX, CGFloat minY, CGFloat maxX, CGFloat maxY)
{
	return (PGInset){minX, minY, maxX, maxY};
}
PGInset PGScaleInset(PGInset i, CGFloat s)
{
	return PGMakeInset(i.minX * s, i.minY * s, i.maxX * s, i.maxY * s);
}
PGInset PGInvertInset(PGInset inset)
{
	return PGScaleInset(inset, -1);
}
NSPoint PGInsetPoint(NSPoint p, PGInset i)
{
	return NSMakePoint(p.x + i.minX, p.y + i.minY);
}
NSSize PGInsetSize(NSSize s, PGInset i)
{
	return NSMakeSize(MAX(0.0f, s.width - i.minX - i.maxX), MAX(0.0f, s.height - i.minY - i.maxY));
}
NSRect PGInsetRect(NSRect r, PGInset i)
{
	return (NSRect){PGInsetPoint(r.origin, i), PGInsetSize(r.size, i)};
}
PGInset PGAddInsets(PGInset a, PGInset b)
{
	return PGMakeInset(a.minX + b.minX, a.minY + b.minY, a.maxX + b.maxX, a.maxY + b.maxY);
}

//	MARK: - Animation

NSTimeInterval PGUptime(void)	//	name is incorrect but for how it's used, no problems should occur "PGNow()"
{
//	return (NSTimeInterval)UnsignedWideToUInt64(AbsoluteToNanoseconds(UpTime())) * 1e-9f;
	return NSDate.timeIntervalSinceReferenceDate;
}
CGFloat PGLagCounteractionSpeedup(NSTimeInterval *timeOfFrame, CGFloat desiredFramerate)
{
	NSCParameterAssert(timeOfFrame);
	NSTimeInterval const currentTime = PGUptime();
	CGFloat const speedup = (CGFloat)(*timeOfFrame ? (currentTime - *timeOfFrame) / desiredFramerate : 1.0f);
	*timeOfFrame = currentTime;
	return speedup;
}
