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
// Views
@class PGAlertGraphic;

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGBezelPanel.h"

typedef NS_ENUM(NSUInteger, PGAlertGraphicType) {
	PGSingleImageGraphic,
	PGInterImageGraphic
};

@interface PGAlertView : NSView<NSWindowDelegate, PGBezelPanelContentView>
#if !__has_feature(objc_arc)
{
	@private
	NSMutableArray *_graphicStack;
	PGAlertGraphic *_currentGraphic;
	NSUInteger _frameCount;
	NSTimer *_frameTimer;
}
#endif

@property(readonly) PGAlertGraphic *currentGraphic;
@property(readonly) NSUInteger frameCount;

- (void)pushGraphic:(PGAlertGraphic *)aGraphic window:(NSWindow *)window;
- (void)popGraphic:(PGAlertGraphic *)aGraphic;
- (void)popGraphicIdenticalTo:(PGAlertGraphic *)aGraphic;
- (void)popGraphicsOfType:(PGAlertGraphicType)type;

- (void)animateOneFrame:(PGAlertView *)anAlertView;

@end

@interface PGAlertGraphic : NSObject

+ (id)cannotGoRightGraphic;
+ (id)cannotGoLeftGraphic;
+ (id)loopedRightGraphic;
+ (id)loopedLeftGraphic;

@property(readonly) PGAlertGraphicType graphicType;
@property(readonly) NSTimeInterval fadeOutDelay;
@property(readonly) NSTimeInterval frameDelay;
@property(readonly) NSUInteger frameCount;

- (void)drawInView:(PGAlertView *)anAlertView;
- (void)flipHorizontally;

- (void)animateOneFrame:(PGAlertView *)anAlertView;

@end

@interface PGLoadingGraphic : PGAlertGraphic
{
	@private
	CGFloat _progress;
}

+ (instancetype)loadingGraphic;

@property(assign, nonatomic) CGFloat progress;

@end

@interface PGBezierPathIconGraphic : PGAlertGraphic
{
	@private
	AEIconType _iconType;
}

+ (instancetype)graphicWithIconType:(AEIconType)type;
- (instancetype)initWithIconType:(AEIconType)type NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end
