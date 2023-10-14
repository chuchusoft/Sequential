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
#import "PGAppKitAdditions.h"
#import <Carbon/Carbon.h>

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

@implementation NSBezierPath(PGAppKitAdditions)

#pragma mark Class Methods

+ (NSBezierPath *)PG_bezierPathWithRoundRect:(NSRect)aRect cornerRadius:(CGFloat)radius
{
	NSBezierPath *const path = [self bezierPath];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(aRect) - radius, NSMaxY(aRect) - radius) radius:radius startAngle:0.0f endAngle:90.0f];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(aRect) + radius, NSMaxY(aRect) - radius) radius:radius startAngle:90.0f endAngle:180.0f];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(aRect) + radius, NSMinY(aRect) + radius) radius:radius startAngle:180.0f endAngle:270.0f];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(aRect) - radius, NSMinY(aRect) + radius) radius:radius startAngle:270.0f endAngle:0.0f];
	[path closePath];
	return path;
}
+ (void)PG_drawIcon:(AEIconType)type inRect:(NSRect)b
{
	NSBezierPath *const p = [self bezierPath];
	CGFloat const scale = MIN(NSWidth(b), NSHeight(b));
	switch(type) {
		case AEPlayIcon:
		{
			CGFloat const r = round(scale / 10.0f);
			[p appendBezierPathWithArcWithCenter:NSMakePoint(round(NSMaxX(b) - r), round(NSMidY(b))) radius:r startAngle:60.0f endAngle:-60.0f clockwise:YES];
			[p appendBezierPathWithArcWithCenter:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.1f + r), round(NSMinY(b) + NSHeight(b) * 0.05f + r * 1.0f)) radius:r startAngle:-60.0f endAngle:180.0f clockwise:YES];
			[p appendBezierPathWithArcWithCenter:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.1f + r), round(NSMinY(b) + NSHeight(b) * 0.95f - r * 1.0f)) radius:r startAngle:180.0f endAngle:60.0f clockwise:YES];
			[p fill];
			break;
		}
		case AEPauseIcon:
			[p setLineWidth:scale / 4.0f];
			[p setLineCapStyle:NSRoundLineCapStyle];
			[p moveToPoint:NSMakePoint(NSMinX(b) + NSWidth(b) * 0.25f, NSMinY(b) + NSHeight(b) * 0.85f)];
			[p lineToPoint:NSMakePoint(NSMinX(b) + NSWidth(b) * 0.25f, NSMinY(b) + NSHeight(b) * 0.15f)];
			[p moveToPoint:NSMakePoint(NSMinX(b) + NSWidth(b) * 0.75f, NSMinY(b) + NSHeight(b) * 0.85f)];
			[p lineToPoint:NSMakePoint(NSMinX(b) + NSWidth(b) * 0.75f, NSMinY(b) + NSHeight(b) * 0.15f)];
			[p stroke];
			break;
		case AEStopIcon:
			NSRectFillUsingOperation(NSIntegralRect(NSInsetRect(b, NSWidth(b) * 0.15f, NSHeight(b) * 0.15f)), NSCompositingOperationSourceOver);
			break;
		default: return;
	}
}
+ (void)PG_drawSpinnerInRect:(NSRect)r startAtPetal:(NSInteger)petal
{
	[NSBezierPath setDefaultLineWidth:MIN(NSWidth(r), NSHeight(r)) / 11.0f];
	[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
	NSUInteger i = 0;
//	const CGFloat PI = M_PI;
	const CGFloat PIx2 = M_PI * 2;
	for(; i < 12; i++) {
		[[[NSColor PG_bezelForegroundColor] colorWithAlphaComponent:petal < 0.0f ? 0.1f : ((petal + i) % 12) / -12.0f + 1.0f] set];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(NSMidX(r) + cosf(PIx2 * i / 12.0f) * NSWidth(r) / 4.0f, NSMidY(r) + sinf(PIx2 * i / 12.0f) * NSHeight(r) / 4.0f) toPoint:NSMakePoint(NSMidX(r) + cosf(PIx2 * i / 12.0f) * NSWidth(r) / 2.0f, NSMidY(r) + sinf(PIx2 * i / 12.0f) * NSHeight(r) / 2.0f)];
	}
	[NSBezierPath setDefaultLineWidth:1];
	[NSBezierPath setDefaultLineCapStyle:NSMiterLineJoinStyle];
}

#pragma mark Instance Methods

- (void)PG_fillUsingOperation:(NSCompositingOperation)op
{
	[NSGraphicsContext saveGraphicsState];
	[[NSGraphicsContext currentContext] setCompositingOperation:op];
	[self fill];
	[NSGraphicsContext restoreGraphicsState];
}

@end

@implementation NSColor(PGAppKitAdditions)

#pragma mark +NSColor(PGAppKitAdditions)

+ (NSColor *)PG_bezelBackgroundColor
{
	return [NSColor colorWithDeviceWhite:48.0f / 255.0f alpha:0.75f];
}
+ (NSColor *)PG_bezelForegroundColor
{
	return [NSColor colorWithDeviceWhite:0.95f alpha:0.9f];
}

#pragma mark -NSColor(PGAppKitAdditions)

- (NSColor *)PG_checkerboardPatternColor
{
	return [self PG_patternColorWithImage:[NSImage imageNamed:@"Checkerboard"] fraction:0.05f];
}
- (NSColor *)PG_patternColorWithImage:(NSImage *)image fraction:(CGFloat)fraction
{
	NSParameterAssert(image);
	NSSize const s = [image size];
	NSRect const r = (NSRect){NSZeroPoint, s};
	NSImage *const pattern = [[[NSImage alloc] initWithSize:s] autorelease];
	[pattern lockFocus];
		[self set];
		NSRectFill(r);
		[image drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceAtop fraction:fraction];
	[pattern unlockFocus];
	return [NSColor colorWithPatternImage:pattern];
}

@end

@implementation NSControl(PGAppKitAdditions)

- (void)PG_setAttributedStringValue:(NSAttributedString *)anObject
{
	NSMutableAttributedString *const str = [[anObject mutableCopy] autorelease];
	[str addAttributes:[[self attributedStringValue] attributesAtIndex:0 effectiveRange:NULL] range:NSMakeRange(0, [str length])];
	[self setAttributedStringValue:str];
}

@end

@implementation NSEvent(PGAppKitAdditions)

- (NSPoint)PG_locationInView:(NSView *)view
{
	NSParameterAssert([view window] == [self window]);
	NSPoint const p = [self locationInWindow];
	return view ? [view convertPoint:p fromView:nil] : p;
}

@end

@implementation NSImageRep(PGAppKitAdditions)

- (id)PG_thumbnailWithMaxSize:(NSSize)size orientation:(PGOrientation)orientation opaque:(BOOL)opaque
{
	if(!self) return nil;
	NSSize const originalSize = PGRotated90CCW & orientation ? NSMakeSize([self pixelsHigh], [self pixelsWide]) : NSMakeSize([self pixelsWide], [self pixelsHigh]);
	NSSize const s = PGIntegralSize(PGScaleSizeByFloat(originalSize, MIN(1.0f, MIN(size.width / originalSize.width, size.height / originalSize.height))));
	NSBitmapImageRep *const thumbRep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:s.width pixelsHigh:s.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
	if(!thumbRep) return nil;
	NSGraphicsContext *const context = [NSGraphicsContext graphicsContextWithBitmapImageRep:thumbRep];
	[NSGraphicsContext setCurrentContext:context];
	[context setImageInterpolation:NSImageInterpolationHigh];
	NSRect rect = NSMakeRect(0.0f, 0.0f, s.width, s.height);
	if(PGUpright != orientation) [[NSAffineTransform PG_transformWithRect:&rect orientation:orientation] concat];
	if(opaque) {
		[[NSColor whiteColor] set];
		NSRectFill(rect);
	}
	[self drawInRect:rect];
	[context flushGraphics];
	return thumbRep;
}

@end

@interface NSMenu(PGSnowLeopardOrLater)
- (void)removeAllItems;
@end

@implementation NSMenu(PGAppKitAdditions)

- (void)PG_removeAllItems
{
	if(PGIsSnowLeopardOrLater()) [self removeAllItems];
	else while([self numberOfItems]) [self removeItemAtIndex:0];
}

@end

@interface NSMenu(AEUndocumented)
- (id)_menuImpl;
@end
@protocol AECarbonMenuImpl
- (void)performActionWithHighlightingForItemAtIndex:(NSInteger)integer;
@end
@implementation NSMenuItem(PGAppKitAdditions)

- (void)PG_addAfterItem:(NSMenuItem *)anItem
{
	NSMenu *const menu = [anItem menu];
	NSAssert(menu, @"Can't add item after an item not in a menu.");
	[menu insertItem:self atIndex:[menu indexOfItem:anItem] + 1];
}
- (void)PG_removeFromMenu
{
	[[self menu] removeItem:self];
}
- (BOOL)PG_performAction
{
	NSMenu *const menu = [self menu];
	[menu update];
	if(![self isEnabled]) return NO;
	NSInteger const i = [menu indexOfItem:self];
	if(!PGIsSnowLeopardOrLater() && [menu respondsToSelector:@selector(_menuImpl)]) {
		id const menuImpl = [menu _menuImpl];
		if([menuImpl respondsToSelector:@selector(performActionWithHighlightingForItemAtIndex:)]) {
			[menuImpl performActionWithHighlightingForItemAtIndex:i];
			return YES;
		}
	}
	[menu performActionForItemAtIndex:i];
	return YES;
}

@end

@interface NSWorkspace(PGSnowLeopardOrLater)
- (BOOL)setDesktopImageURL:(NSURL *)URL forScreen:(NSScreen *)screen options:(NSUInteger)options error:(out NSError **)outError;
- (NSUInteger)desktopImageOptionsForScreen:(NSScreen *)screen;
@end

@implementation NSScreen(PGAppKitAdditions)

+ (NSScreen *)PG_mainScreen
{
	NSArray *const screens = [self screens];
	return [screens count] ? [screens objectAtIndex:0] : nil;
}
- (BOOL)PG_setDesktopImageURL:(NSURL *)URL
{
#if 1
	NSWorkspace *const ws = [NSWorkspace sharedWorkspace];
	return [ws setDesktopImageURL:URL
						forScreen:self
						  options:[ws desktopImageOptionsForScreen:self]
							error:NULL];
#else
	if(PGIsSnowLeopardOrLater()) return [[NSWorkspace sharedWorkspace] setDesktopImageURL:URL forScreen:self options:[[NSWorkspace sharedWorkspace] desktopImageOptionsForScreen:self] error:NULL];
	NSParameterAssert([URL isFileURL]);
	NSParameterAssert([NSScreen PG_mainScreen] == self);

	FSRef ref;
	if(FSPathMakeRef((UInt8 const *)[[URL path] fileSystemRepresentation], &ref, NULL) != noErr) return NO;
	AliasHandle aliasHandle = NULL;
	if(FSNewAliasMinimal(&ref, &aliasHandle) != noErr || !aliasHandle) return NO;

	// Now we create an AEDesc containing the alias to the image.
	SInt8 const handleState = HGetState((Handle)aliasHandle);
	HLock((Handle)aliasHandle);
	AEDesc descriptor = {typeNull, NULL};
	OSErr const descErr = AECreateDesc(typeAlias, *aliasHandle, GetHandleSize((Handle)aliasHandle), &descriptor);
	HSetState((Handle)aliasHandle, handleState);
	DisposeHandle((Handle)aliasHandle);
	if(noErr != descErr) return NO;

	OSType const sig = 'MACS'; // The app signature for the Finder.
	AppleEvent event;
	if(AEBuildAppleEvent(kAECoreSuite, kAESetData, typeApplSignature, &sig, sizeof(sig), kAutoGenerateReturnID, kAnyTransactionID, &event, NULL, "'----':'obj '{want:type(prop), form:prop, seld:type('dpic'), from:'null'()}, data:(@)", &descriptor) != noErr) return NO;

	// Finally we can go ahead and send the Apple Event using AESend.
	AppleEvent reply = {typeNull, NULL};
	OSErr const sendErr = AESend(&event, &reply, kAENoReply, kAENormalPriority, kAEDefaultTimeout, NULL, NULL);
	AEDisposeDesc(&event);
	return noErr == sendErr;
#endif
}

@end

@implementation NSView(PGAppKitAdditions)

- (void)PG_setEnabled:(BOOL)enabled recursive:(BOOL)recursive
{
	if([self respondsToSelector:@selector(setEnabled:)]) [(NSControl *)self setEnabled:enabled];
	if(recursive) for(NSView *const subview in [self subviews]) [subview PG_setEnabled:enabled recursive:YES];
}
- (BOOL)PG_isActive
{
	NSWindow *const w = [self window];
	return [w isKeyWindow] && [w firstResponder] == self;
}

@end

@implementation NSWindow(PGAppKitAdditions)

- (NSRect)PG_contentRect
{
#if __LP64__
	// TODO: Make sure this works correctly when the window is being dragged/resized.
	return [self contentRectForFrameRect:[self frame]];
#else
	HIRect rect;
	HIWindowGetBounds([self windowRef], kWindowContentRgn, kHICoordSpace72DPIGlobal, &rect); // Updated in realtime, unlike -frame. See http://web.archive.org/web/20100113062205/http://rentzsch.com/cocoa/nswindowFrameLies.
	NSRect const r = NSRectFromCGRect(rect);
	return NSMakeRect(NSMinX(r), (CGFloat)CGDisplayPixelsHigh(kCGDirectMainDisplay) - NSMaxY(r), NSWidth(r), NSHeight(r));
#endif
}
- (void)PG_setContentRect:(NSRect)aRect
{
	NSSize const min = [self minSize];
	NSSize const max = [self maxSize];
	NSRect r = [self frameRectForContentRect:aRect];
	r.size.width = MIN(MAX(min.width, NSWidth(r)), max.width);
	CGFloat const newHeight = MIN(MAX(min.height, NSHeight(r)), max.height);
	r.origin.y += NSHeight(r) - newHeight;
	r.size.height = newHeight;
	[self setFrame:r display:YES];
}

@end
