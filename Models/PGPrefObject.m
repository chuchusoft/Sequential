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
#import "PGPrefObject.h"
#import <tgmath.h>

// Other Sources
#import "PGFoundationAdditions.h"

NSString *const PGPrefObjectShowsInfoDidChangeNotification = @"PGPrefObjectShowsInfoDidChange";
NSString *const PGPrefObjectShowsThumbnailsDidChangeNotification = @"PGPrefObjectShowsThumbnailsDidChange";
NSString *const PGPrefObjectReadingDirectionDidChangeNotification = @"PGPrefObjectReadingDirectionDidChange";
NSString *const PGPrefObjectImageScaleDidChangeNotification = @"PGPrefObjectImageScaleDidChange";
NSString *const PGPrefObjectUpscalesToFitScreenDidChangeNotification = @"PGPrefObjectUpscalesToFitScreenDidChange";
NSString *const PGPrefObjectAnimatesImagesDidChangeNotification = @"PGPrefObjectAnimatesImagesDidChange";
NSString *const PGPrefObjectSortOrderDidChangeNotification = @"PGPrefObjectSortOrderDidChange";
NSString *const PGPrefObjectTimerIntervalDidChangeNotification = @"PGPrefObjectTimerIntervalDidChange";
NSString *const PGPrefObjectBaseOrientationDidChangeNotification = @"PGPrefObjectBaseOrientationDidChange";

NSString *const PGPrefObjectAnimateKey = @"PGPrefObjectAnimate";

static NSString *const PGShowsInfoKey = @"PGShowsInfo";
static NSString *const PGShowsThumbnailsKey = @"PGShowsThumbnails";
static NSString *const PGReadingDirectionRightToLeftKey = @"PGReadingDirectionRightToLeft";
static NSString *const PGImageScaleModeKey = @"PGImageScaleMode";
static NSString *const PGImageScaleFactorKey = @"PGImageScaleFactor";
static NSString *const PGAnimatesImagesKey = @"PGAnimatesImages";
static NSString *const PGSortOrderKey = @"PGSortOrder2";
static NSString *const PGTimerIntervalKey = @"PGTimerInterval";
static NSString *const PGBaseOrientationKey = @"PGBaseOrientation";

//static NSString *const PGSortOrderDeprecatedKey = @"PGSortOrder"; // Deprecated after 1.3.2.

@implementation PGPrefObject

//	MARK: +PGPrefObject

+ (id)globalPrefObject
{
	static PGPrefObject *obj = nil;
	if(!obj) obj = [[self alloc] init];
	return obj;
}
+ (NSArray *)imageScaleModes
{
	return @[@(PGConstantFactorScale), @(PGAutomaticScale), @(PGViewFitScale)];
}

//	MARK: +NSObject

+ (void)initialize
{
	if([PGPrefObject class] != self) return;
#if 1
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		PGShowsInfoKey: @YES,
		PGShowsThumbnailsKey: @YES,
		PGReadingDirectionRightToLeftKey: @NO,
		PGImageScaleModeKey: @( PGConstantFactorScale ),
		PGImageScaleFactorKey: @1.0f,
		PGAnimatesImagesKey: @YES,
		PGSortOrderKey: @( PGSortByName | PGSortRepeatMask ),
		PGTimerIntervalKey: @30.0f,
		PGBaseOrientationKey: @( PGUpright )
	}];
#else
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithBool:YES], PGShowsInfoKey,
		[NSNumber numberWithBool:YES], PGShowsThumbnailsKey,
		[NSNumber numberWithBool:NO], PGReadingDirectionRightToLeftKey,
		[NSNumber numberWithInteger:PGConstantFactorScale], PGImageScaleModeKey,
		[NSNumber numberWithDouble:1.0f], PGImageScaleFactorKey,
		[NSNumber numberWithBool:YES], PGAnimatesImagesKey,
		[NSNumber numberWithInteger:PGSortByName | PGSortRepeatMask], PGSortOrderKey,
		[NSNumber numberWithDouble:30.0f], PGTimerIntervalKey,
		[NSNumber numberWithUnsignedInteger:PGUpright], PGBaseOrientationKey,
		nil]];
#endif
}

//	MARK: - PGPrefObject

#if !__has_feature(objc_arc)
- (BOOL)showsInfo
{
	return _showsInfo;
}
#endif
- (void)setShowsInfo:(BOOL)flag
{
	if(!flag == !_showsInfo) return;
	_showsInfo = flag;
	[[NSUserDefaults standardUserDefaults] setObject:@(flag) forKey:PGShowsInfoKey];
	[self PG_postNotificationName:PGPrefObjectShowsInfoDidChangeNotification];
}
#if !__has_feature(objc_arc)
- (BOOL)showsThumbnails
{
	return _showsThumbnails;
}
#endif
- (void)setShowsThumbnails:(BOOL)flag
{
	if(!flag == !_showsThumbnails) return;
	_showsThumbnails = flag;
	[[NSUserDefaults standardUserDefaults] setObject:@(flag) forKey:PGShowsThumbnailsKey];
	[self PG_postNotificationName:PGPrefObjectShowsThumbnailsDidChangeNotification];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGReadingDirection)readingDirection
{
	return _readingDirection;
}
#endif
- (void)setReadingDirection:(PGReadingDirection)aDirection
{
	if(aDirection == _readingDirection) return;
	_readingDirection = aDirection;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:aDirection == PGReadingDirectionRightToLeft] forKey:PGReadingDirectionRightToLeftKey];
	[self PG_postNotificationName:PGPrefObjectReadingDirectionDidChangeNotification];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGImageScaleMode)imageScaleMode
{
	return _imageScaleMode;
}
#endif
- (void)setImageScaleMode:(PGImageScaleMode)aMode
{
	_imageScaleMode = aMode;
	_imageScaleFactor = 1;
	[[NSUserDefaults standardUserDefaults] setObject:@(aMode) forKey:PGImageScaleModeKey];
	[[NSUserDefaults standardUserDefaults] setObject:@1.0 forKey:PGImageScaleFactorKey];
	[self PG_postNotificationName:PGPrefObjectImageScaleDidChangeNotification userInfo:@{PGPrefObjectAnimateKey: @YES}];
}

#if !__has_feature(objc_arc)
- (CGFloat)imageScaleFactor
{
	return _imageScaleFactor;
}
#endif
- (void)setImageScaleFactor:(CGFloat)factor
{
	[self setImageScaleFactor:factor animate:YES];
}
- (void)setImageScaleFactor:(CGFloat)factor animate:(BOOL)flag
{
	NSParameterAssert(factor > 0.0f);
	CGFloat const newFactor = fabs(1.0f - factor) < 0.01f ? 1.0f : factor; // If it's close to 1, fudge it.
	_imageScaleFactor = newFactor;
	_imageScaleMode = PGConstantFactorScale;
	[[NSUserDefaults standardUserDefaults] setObject:@(newFactor) forKey:PGImageScaleFactorKey];
	[[NSUserDefaults standardUserDefaults] setObject:@(PGConstantFactorScale) forKey:PGImageScaleModeKey];
	[self PG_postNotificationName:PGPrefObjectImageScaleDidChangeNotification userInfo:@{PGPrefObjectAnimateKey: @(flag)}];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (BOOL)animatesImages
{
	return _animatesImages;
}
#endif
- (void)setAnimatesImages:(BOOL)flag
{
	if(!flag == !_animatesImages) return;
	_animatesImages = flag;
	[[NSUserDefaults standardUserDefaults] setObject:@(flag) forKey:PGAnimatesImagesKey];
	[self PG_postNotificationName:PGPrefObjectAnimatesImagesDidChangeNotification];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGSortOrder)sortOrder
{
	return _sortOrder;
}
#endif
- (void)setSortOrder:(PGSortOrder)anOrder
{
	if(anOrder == _sortOrder) return;
	_sortOrder = anOrder;
	[[NSUserDefaults standardUserDefaults] setObject:@(anOrder) forKey:PGSortOrderKey];
	[self PG_postNotificationName:PGPrefObjectSortOrderDidChangeNotification];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (NSTimeInterval)timerInterval
{
	return _timerInterval;
}
#endif
- (void)setTimerInterval:(NSTimeInterval)interval
{
	if(interval == _timerInterval) return;
	_timerInterval = interval;
	[[NSUserDefaults standardUserDefaults] setObject:@(interval) forKey:PGTimerIntervalKey];
	[self PG_postNotificationName:PGPrefObjectTimerIntervalDidChangeNotification];
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGOrientation)baseOrientation
{
	return _baseOrientation;
}
#endif
- (void)setBaseOrientation:(PGOrientation)anOrientation
{
	if(anOrientation == _baseOrientation) return;
	_baseOrientation = anOrientation;
	[[NSUserDefaults standardUserDefaults] setObject:@(anOrientation) forKey:PGBaseOrientationKey];
	[self PG_postNotificationName:PGPrefObjectBaseOrientationDidChangeNotification];
}

//	MARK: -

- (BOOL)isCurrentSortOrder:(PGSortOrder)order
{
	return (PGSortOrderMask & order) == (PGSortOrderMask & self.sortOrder);
}

//	MARK: - NSObject

- (instancetype)init
{
	if((self = [super init])) {
		NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
		_showsInfo = [[d objectForKey:PGShowsInfoKey] boolValue];
		_showsThumbnails = [[d objectForKey:PGShowsThumbnailsKey] boolValue];
		_readingDirection = [[d objectForKey:PGReadingDirectionRightToLeftKey] boolValue] ? PGReadingDirectionRightToLeft : PGReadingDirectionLeftToRight;
		NSNumber *const imageScaleMode = [d objectForKey:PGImageScaleModeKey];
		_imageScaleMode = [[[self class] imageScaleModes] containsObject:imageScaleMode] ? imageScaleMode.integerValue : PGConstantFactorScale;
		_imageScaleFactor = (CGFloat)[[d objectForKey:PGImageScaleFactorKey] doubleValue];
		_animatesImages = [[d objectForKey:PGAnimatesImagesKey] boolValue];
		_sortOrder = [[d objectForKey:PGSortOrderKey] integerValue];
		_timerInterval = [[d objectForKey:PGTimerIntervalKey] doubleValue];
		_baseOrientation = [[d objectForKey:PGBaseOrientationKey] unsignedIntegerValue];
	}
	return self;
}

@end
