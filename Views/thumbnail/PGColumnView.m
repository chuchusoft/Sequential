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
#import "PGColumnView.h"

// Views
#import "PGClipView.h"
#include <tgmath.h>

// Other Sources
#import "PGGeometry.h"

#if __has_feature(objc_arc)

@interface PGColumnView ()
@property (nonatomic, strong) PGClipView *clipView;
@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) NSMutableArray<__kindof NSView *> *clipViews;
@property (nonatomic, strong) NSMutableArray *views;
@end

#endif

//	MARK: -
@implementation PGColumnView

- (NSUInteger)numberOfColumns
{
	return _views.count;
}
- (id)lastView
{
	return _views.lastObject;
}
- (void)setColumnWidth:(CGFloat)width
{
	_columnWidth = round(width);
	[self layout];
}

//	MARK: -

- (id)viewAtIndex:(NSUInteger)index
{
	return _views[index];
}

//	MARK: -

- (void)addColumnWithView:(NSView *)aView
{
	[self insertColumnWithView:aView atIndex:_views.count];
}
- (void)insertColumnWithView:(NSView *)aView atIndex:(NSUInteger)index
{
	NSParameterAssert(aView);
	NSParameterAssert([_views indexOfObjectIdenticalTo:aView] == NSNotFound);
#if __has_feature(objc_arc)
	PGClipView *const clip = [PGClipView new];
#else
	PGClipView *const clip = [[[PGClipView alloc] init] autorelease];
#endif
	[_clipViews insertObject:clip atIndex:index];
	[_views insertObject:aView atIndex:index];
	[_view addSubview:clip];
	clip.delegate = self;
	[clip setBackgroundColor:nil];
	[clip setShowsBorder:NO];
	clip.documentView = aView;
	[self layout];
	aView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	[aView setFrameSize:NSMakeSize(NSWidth(clip.bounds), NSHeight(aView.frame))];
	[self scrollToTopOfColumnWithView:aView];
}
- (void)removeColumnsAfterView:(NSView *)aView
{
	NSUInteger const i = aView ? [_views indexOfObject:aView] : 0;
	NSParameterAssert(NSNotFound != i);
	if(_views.count <= i + 1) return;
	while(_views.count > i + 1) {
		PGClipView *const clip = _clipViews.lastObject;
		[clip setDocumentView:nil];
		[clip removeFromSuperview];
		[_clipViews removeLastObject];
		[_views removeLastObject];
	}
	[self layout];
	return;
}

//	MARK: -

- (void)scrollToTopOfColumnWithView:(NSView *)aView
{
	[_clipViews[[_views indexOfObjectIdenticalTo:aView]]  scrollToEdge:PGMaxYEdgeMask animation:PGAllowAnimation];
}
- (void)scrollToLastColumnAnimate:(BOOL)flag
{
	[_clipView scrollToEdge:PGMaxXEdgeMask animation:flag ? PGPreferAnimation : PGNoAnimation];
}

//	MARK: -

- (void)layout
{
	NSRect const b = self.bounds;
	[_view setFrameSize:NSMakeSize(MAX(_columnWidth * [_views count], NSWidth(b)), NSHeight(b))];
	NSRect const vb = _view.bounds;
	NSUInteger i = 0;
	NSUInteger const count = _clipViews.count;
	for(; i < count; i++) ((NSView *)_clipViews[i]).frame = NSMakeRect(NSMinX(vb) + _columnWidth * i, NSMinY(vb), _columnWidth, NSHeight(vb));
	[self setNeedsDisplay:YES];
}

//	MARK: - NSView

- (instancetype)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_clipView = [[PGClipView alloc] initWithFrame:self.bounds];
		[_clipView setBackgroundColor:nil];
		[_clipView setShowsBorder:NO];
		_clipView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[self addSubview:_clipView];
		_view = [[NSView alloc] initWithFrame:NSZeroRect];
		_clipView.documentView = _view;
		_clipViews = [NSMutableArray new];
		_views = [NSMutableArray new];
		_columnWidth = 128.0f + 12.0f;
	}
	return self;
}
- (void)setFrameSize:(NSSize)aSize
{
	if(NSEqualSizes(self.frame.size, aSize)) return;
	[super setFrameSize:aSize];
	[self layout];
}

//	MARK: - NSObject

- (instancetype)init
{
	return [self initWithFrame:NSZeroRect];
}
#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_clipView release];
	[_view release];
	[_clipViews release];
	[_views release];
	[super dealloc];
}
#endif

//	MARK: - <PGClipViewDelegate>

- (BOOL)clipView:(PGClipView *)sender handleMouseEvent:(NSEvent *)anEvent first:(BOOL)flag
{
	NSUInteger const i = [_clipViews indexOfObjectIdenticalTo:sender];
	if(NSNotFound == i) return NO;
	[_views[i] mouseDown:anEvent];
	return YES;
}
- (PGRectEdgeMask)clipView:(PGClipView *)sender directionFor:(PGPageLocation)pageLocation
{
	return PGReadingDirectionAndLocationToRectEdgeMask(pageLocation, PGReadingDirectionLeftToRight);
}

@end
