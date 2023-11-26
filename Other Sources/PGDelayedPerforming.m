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
#import "PGDelayedPerforming.h"

// Other Sources
#import "PGFoundationAdditions.h"

#if __has_feature(objc_arc)

//	Because this file involves selectors and optional -retain's, it's
//	best to compile this file with ARC disabled because ARC cannot
//	work out whether a selector will return a retained object and the
//	optional -retain can only be implemented under ARC by splitting
//	PGTimerContextObject into 2 concrete subclasses: one which retains
//	the target and one which does not retain it. All in all, it's not
//	worth trying to make this code work under ARC - just build it under
//	manual memory management (MMR).
#error THIS FILE SHOULD NOT BE COMPILED UNDER ARC. Use Compiler Flags = -fno-objc-arc

//	key = id [non-retained], value = NSMutableArray<NSTimer*>* [retained]
static CFMutableDictionaryRef PGTimers_NonretainedKey_RetainedValue = NULL;

@protocol PGTimerContext <NSObject>
@optional
- (BOOL)matchesSelector:(SEL)aSel object:(id)anObject;
- (void)invoke;
- (id)target;
@end

@interface PGTimerContextObject : NSObject<PGTimerContext>
@property (nonatomic, assign) SEL selector;
@property (nonatomic, strong) id argument;
@property (nonatomic, assign) PGDelayedPerformingOptions options;

- (id)initWithSelector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts;
@end

@interface PGTimerContextObjectTargetUnretained : PGTimerContextObject
@property (nonatomic, weak)	id target;

- (id)initWithTarget:(id)target selector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts;
@end

@interface PGTimerContextObjectTargetRetained : PGTimerContextObject
@property (nonatomic, strong) id target;

- (id)initWithTarget:(id)target selector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts;
@end

#else

//	MARK: -
static NSMutableDictionary *PGTimersByNonretainedObjectValue;

@interface PGTimerContextObject : NSObject
{
	@private
	id _target;
	SEL _selector;
	id _argument;
	PGDelayedPerformingOptions _options;
}

- (instancetype)initWithTarget:(id)target selector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)matchesSelector:(SEL)aSel object:(id)anObject;
- (void)invoke;
- (id)target;

@end

#endif

//	MARK: -
@implementation NSObject(PGDelayedPerforming)

static void PGTimerCallback(CFRunLoopTimerRef timer, PGTimerContextObject *context)
{
	if(!CFRunLoopTimerIsValid(timer)) {
#if __has_feature(objc_arc)
		NSMutableArray *const timers = (NSMutableArray *) CFDictionaryGetValue(PGTimers_NonretainedKey_RetainedValue,
																			(__bridge const void *)[context target]);
		[timers removeObjectIdenticalTo:(__bridge NSTimer *)timer];
#else
		[PGTimersByNonretainedObjectValue[context.target] removeObjectIdenticalTo:(NSTimer *)timer];
#endif
	}
	[context invoke];
}

- (NSTimer *)PG_performSelector:(SEL)aSel withObject:(id)anArgument fireDate:(NSDate *)date interval:(NSTimeInterval)interval options:(PGDelayedPerformingOptions)opts
{
	return [self PG_performSelector:aSel
						 withObject:anArgument
						   fireDate:date
						   interval:interval
							options:opts
							   mode:NSRunLoopCommonModes];
}

- (NSTimer *)PG_performSelector:(SEL)aSel withObject:(id)anArgument fireDate:(NSDate *)date interval:(NSTimeInterval)interval options:(PGDelayedPerformingOptions)opts mode:(NSString *)mode
{
	NSParameterAssert(interval >= 0.0f);
#if __has_feature(objc_arc)
	PGTimerContextObject *tco = (opts & PGRetainTarget) ?
		[[PGTimerContextObjectTargetRetained alloc] initWithTarget:self selector:aSel object:anArgument options:opts] :
		[[PGTimerContextObjectTargetUnretained alloc] initWithTarget:self selector:aSel object:anArgument options:opts];
#endif
	CFRunLoopTimerContext context = {
		0,
		//	NB: because the retain field is set to CFRetain, CFRunLoopTimerCreate() will call CFRetain
		//	with the PGTimerContextObject instance which will increment its retain count, which means
		//	that there is a strong reference to the instance so it will not be released when this
		//	thread's autorelease pool is drained
#if __has_feature(objc_arc)
		(__bridge void *)tco,
#else
		[[[PGTimerContextObject alloc] initWithTarget:self selector:aSel object:anArgument options:opts] autorelease],
#endif
		CFRetain,
		CFRelease,
		CFCopyDescription,
	};
	CFTimeInterval const repeatInterval = PGRepeatOnInterval & opts ? interval : 0.0f;
#if __has_feature(objc_arc)
	tco = nil;	//	tell ARC compiler that tco's lifetime ends here

	NSTimer *const timer = (NSTimer *)CFBridgingRelease(CFRunLoopTimerCreate(kCFAllocatorDefault,
		CFDateGetAbsoluteTime((CFDateRef)(date ? date : [NSDate dateWithTimeIntervalSinceNow:interval])),
		repeatInterval, kNilOptions, 0, (CFRunLoopTimerCallBack)PGTimerCallback, &context));
#else
	NSTimer *const timer = [(NSTimer *)CFRunLoopTimerCreate(kCFAllocatorDefault, CFDateGetAbsoluteTime((CFDateRef)(date ? date : [NSDate dateWithTimeIntervalSinceNow:interval])), repeatInterval, kNilOptions, 0, (CFRunLoopTimerCallBack)PGTimerCallback, &context) autorelease];
#endif
	[NSRunLoop.currentRunLoop addTimer:timer forMode:mode];

	//	to support cancellation, keep track of the timer instance
#if __has_feature(objc_arc)
	if(!PGTimers_NonretainedKey_RetainedValue)
		PGTimers_NonretainedKey_RetainedValue = CFDictionaryCreateMutable(kCFAllocatorDefault,
													0, NULL, &kCFTypeDictionaryValueCallBacks);

	const void *key = (__bridge const void *)self;
	NSMutableArray *timers = CFDictionaryGetValue(PGTimers_NonretainedKey_RetainedValue, key);
	if(!timers) {
		timers = [NSMutableArray array];
		CFDictionaryAddValue(PGTimers_NonretainedKey_RetainedValue, key, (__bridge void*) timers);
	}
#else
	if(!PGTimersByNonretainedObjectValue)
		PGTimersByNonretainedObjectValue = (NSMutableDictionary *)CFDictionaryCreateMutable(
											kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);

	NSMutableArray *timers = PGTimersByNonretainedObjectValue[self];
	if(!timers) {
		timers = [NSMutableArray array];
		CFDictionaryAddValue((CFMutableDictionaryRef)PGTimersByNonretainedObjectValue, self, timers);
	}
#endif
	[timers addObject:timer];
	return timer;
}
- (void)PG_cancelPreviousPerformRequests
{
#if __has_feature(objc_arc)
	NSMutableArray *const timers = (NSMutableArray *) CFDictionaryGetValue(PGTimers_NonretainedKey_RetainedValue,
																			(__bridge const void *)self);
	[timers makeObjectsPerformSelector:@selector(invalidate)];
	CFDictionaryRemoveValue(PGTimers_NonretainedKey_RetainedValue, (__bridge const void *)self);
#else
	[PGTimersByNonretainedObjectValue[self] makeObjectsPerformSelector:@selector(invalidate)];
	[PGTimersByNonretainedObjectValue removeObjectForKey:self];
#endif
}
- (void)PG_cancelPreviousPerformRequestsWithSelector:(SEL)aSel object:(id)anArgument
{
#if __has_feature(objc_arc)
	NSMutableArray *const timers = (NSMutableArray *) CFDictionaryGetValue(PGTimers_NonretainedKey_RetainedValue,
																			(__bridge const void *)self);
	for(NSTimer *const timer in [timers copy]) {
		if([timer isValid]) {
			CFRunLoopTimerContext context;
			CFRunLoopTimerGetContext((CFRunLoopTimerRef)timer, &context);
			if(![(__bridge PGTimerContextObject *)context.info matchesSelector:aSel object:anArgument])
				continue;
			[timer invalidate];
		}
		[timers removeObjectIdenticalTo:timer];
	}
#else
	NSMutableArray *const timers = PGTimersByNonretainedObjectValue[self];
	for(NSTimer *const timer in [[timers copy] autorelease]) {
		if(timer.valid) {
			CFRunLoopTimerContext context;
			CFRunLoopTimerGetContext((CFRunLoopTimerRef)timer, &context);
			if(![(PGTimerContextObject *)context.info matchesSelector:aSel object:anArgument]) continue;
			[timer invalidate];
		}
		[timers removeObjectIdenticalTo:timer];
	}
#endif
}

@end

//	MARK: -
@implementation PGTimerContextObject

#if __has_feature(objc_arc)
- (id)initWithSelector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts
#else
- (instancetype)initWithTarget:(id)target selector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts
#endif
{
	if((self = [super init])) {
#if !__has_feature(objc_arc)
		_target = target;
#endif
		_selector = aSel;
#if __has_feature(objc_arc)
		_argument = anArgument;
#else
		_argument = [anArgument retain];
#endif
		_options = opts;
#if !__has_feature(objc_arc)
		if(PGRetainTarget & _options) [_target retain];
#endif
	}
	return self;
}
- (BOOL)matchesSelector:(SEL)aSel object:(id)anArgument
{
	if(aSel != _selector) return NO;
	if(anArgument != _argument && (PGCompareArgumentPointer & _options || !PGEqualObjects(anArgument, _argument))) return NO;
	return YES;
}

#if !__has_feature(objc_arc)
- (void)invoke
{
	[_target performSelector:_selector withObject:_argument];
}
- (id)target
{
	return _target;
}

//	MARK: - NSObject

- (void)dealloc
{
	if(PGRetainTarget & _options) [_target release];
	[_argument release];
	[super dealloc];
}
#endif

@end


//	MARK: -

#if __has_feature(objc_arc)

@implementation PGTimerContextObjectTargetUnretained

- (id)initWithTarget:(id)target selector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts
{
	if((self = [super initWithSelector:aSel object:anArgument options:opts])) {
		_target = target;
	}
	return self;
}
- (void)invoke
{
	//	this generates a warning from the compiler under ARC:
	//	"PerformSelector may cause a leak because its selector is unknown"
	[self.target performSelector:self.selector withObject:self.argument];
}
- (id)target
{
	return _target;
}

@end

@implementation PGTimerContextObjectTargetRetained

- (id)initWithTarget:(id)target selector:(SEL)aSel object:(id)anArgument options:(PGDelayedPerformingOptions)opts
{
	if((self = [super initWithSelector:aSel object:anArgument options:opts])) {
		_target = target;
	}
	return self;
}
- (void)invoke
{
	//	this generates a warning from the compiler under ARC:
	//	"PerformSelector may cause a leak because its selector is unknown"
	[self.target performSelector:self.selector withObject:self.argument];
}
- (id)target
{
	return _target;
}

@end

#endif
