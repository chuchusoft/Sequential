/* Copyright © 2010, The Sequential Project
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
#import "PGActivity.h"

static PGActivity *PGApplicationActivity;

#if __has_feature(objc_arc)

@interface PGActivity()

@property(atomic, weak) NSObject<PGActivityOwner> *owner;
//@property(atomic, weak) PGActivity *parentActivity;
@property(nonatomic, strong) NSMutableArray *childActivities;
@property(nonatomic, strong) NSString *activityDescription;
@property(nonatomic, assign) CGFloat progress;
@property(nonatomic, assign) BOOL isActive;

- (void)_addChildActivity:(PGActivity *)activity;
- (void)_removeChildActivity:(PGActivity *)activity;
- (void)_prioritizeChildActivity:(PGActivity *)activity;

@end

#else

@interface PGActivity(Private)

- (void)_addChildActivity:(PGActivity *)activity;
- (void)_removeChildActivity:(PGActivity *)activity;
- (void)_prioritizeChildActivity:(PGActivity *)activity;

@end

#endif

@implementation PGActivity

//	MARK: +PGActivity

+ (id)applicationActivity
{
	return PGApplicationActivity;
}

//	MARK: +NSObject

+ (void)initialize
{
	if(!PGApplicationActivity) PGApplicationActivity = [self new];
}

//	MARK: - PGActivity

- (instancetype)initWithOwner:(NSObject<PGActivityOwner> *)owner
{
	if((self = [self init])) {
		_owner = owner;
	}
	return self;
}
#if !__has_feature(objc_arc)
- (NSObject<PGActivityOwner> *)owner
{
	@synchronized(self) {
		return _owner;
	}
	return nil;
}
#endif

#if __has_feature(objc_arc)
@synthesize parentActivity = _parentActivity;
#endif

- (PGActivity *)parentActivity
{
	@synchronized(self) {
		return _parentActivity;
	}
	return nil;
}
- (void)setParentActivity:(PGActivity *)activity
{
	@synchronized(self) {
		if(activity == _parentActivity) return;
		[_parentActivity _removeChildActivity:self];
		_parentActivity = activity;
		[_parentActivity _addChildActivity:self];
	}
}
- (NSString *)activityDescription
{
	NSString *const desc = [self.owner descriptionForActivity:self];
	return desc ? desc : @"";
}
- (CGFloat)progress
{
	NSObject<PGActivityOwner> *const owner = self.owner;
	return owner ? [owner progressForActivity:self] : -1.0f;
}
- (BOOL)isActive
{
	if(self.progress >= 0.0f) return YES;
	@synchronized(self) {
		for(PGActivity *const child in _childActivities) if(child.isActive) return YES;
	}
	return NO;
}
- (NSArray *)childActivities:(BOOL)activeOnly
{
	NSMutableArray *activeChildren = nil;
	@synchronized(self) {
		if(activeOnly) {
			activeChildren = [NSMutableArray arrayWithCapacity:_childActivities.count];
			for(PGActivity *const child in _childActivities) if(child.isActive) [activeChildren addObject:child];
		} else
#if __has_feature(objc_arc)
			activeChildren = [_childActivities copy];
#else
			activeChildren = [[_childActivities copy] autorelease];
#endif
	}
	return activeChildren;
}

//	MARK: -

- (IBAction)cancel:(id)sender
{
	@synchronized(self) {
		[self setParentActivity:nil];
#if __has_feature(objc_arc)
		[[_childActivities copy] makeObjectsPerformSelector:@selector(cancel:) withObject:sender];
#else
		[[[_childActivities copy] autorelease] makeObjectsPerformSelector:@selector(cancel:) withObject:sender];
#endif
	}
	[self.owner cancelActivity:self];
}
- (IBAction)prioritize:(id)sender
{
	@synchronized(self) {
#if __has_feature(objc_arc)
		[self.parentActivity _prioritizeChildActivity:self];
#else
		[_parentActivity _prioritizeChildActivity:self];
#endif
	}
}
- (void)invalidate
{
	@synchronized(self) {
		_owner = nil;
		[self setParentActivity:nil];
	}
}

//	MARK: - PGActivity(Private)

- (void)_addChildActivity:(PGActivity *)activity
{
	@synchronized(self) {
		NSUInteger const i = [_childActivities indexOfObjectIdenticalTo:activity];
		NSParameterAssert(NSNotFound == i);
		[_childActivities addObject:activity];
	}
}
- (void)_removeChildActivity:(PGActivity *)activity
{
	@synchronized(self) {
		[_childActivities removeObjectIdenticalTo:activity];
	}
}
- (void)_prioritizeChildActivity:(PGActivity *)activity
{
	@synchronized(self) {
		NSUInteger const i = [_childActivities indexOfObjectIdenticalTo:activity];
		NSParameterAssert(NSNotFound != i);
		[_childActivities removeObjectAtIndex:i];
		[_childActivities insertObject:activity atIndex:0];
#if __has_feature(objc_arc)
		[self.parentActivity _prioritizeChildActivity:self];
#else
		[_parentActivity _prioritizeChildActivity:self];
#endif
	}
}

//	MARK: - NSObject

- (instancetype)init
{
	if((self = [super init])) {
		_childActivities = [NSMutableArray new];
	}
	return self;
}
- (void)dealloc
{
#if __has_feature(objc_arc)
	[_childActivities makeObjectsPerformSelector:@selector(setParentActivity:) withObject:nil];
#else
	[[[_childActivities copy] autorelease] makeObjectsPerformSelector:@selector(setParentActivity:) withObject:nil];
	[_childActivities release];
	[super dealloc];
#endif
}

@end

@implementation NSObject(PGActivityOwner)

- (CGFloat)progressForActivity:(PGActivity *)activity
{
	return -1.0f;
}
- (void)cancelActivity:(PGActivity *)activity {}

@end
