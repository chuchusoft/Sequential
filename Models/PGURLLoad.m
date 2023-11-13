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
#import "PGURLLoad.h"

// Other Sources
#import "PGFoundationAdditions.h"

#define PGMaxSimultaneousConnections 4

static NSString *PGUserAgent = nil;
static NSUInteger PGSimultaneousConnections = 0;

@interface PGActivity(PGURLLoadStarting)

- (BOOL)PG_startNextURLLoad;

@end

#if __has_feature(objc_arc)

@interface PGURLLoad()

@property(nonatomic, assign) BOOL loaded;
@property(nonatomic, weak) NSObject<PGURLLoadDelegate> *delegate;
@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic, strong) NSURLRequest *request;
@property(nonatomic, strong) NSURLResponse *response;
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, strong) PGActivity *activity;

- (BOOL)_start;
- (void)_stop;

@end

#else

@interface PGURLLoad(Private)

- (BOOL)_start;
- (void)_stop;

@end

#endif

@implementation PGURLLoad

//	MARK: +PGURLLoad

+ (NSString *)userAgent
{
#if __has_feature(objc_arc)
	return PGUserAgent;
#else
	return [[PGUserAgent retain] autorelease];
#endif
}
+ (void)setUserAgent:(NSString *)aString
{
	if(aString == PGUserAgent) return;
#if !__has_feature(objc_arc)
	[PGUserAgent release];
#endif
	PGUserAgent = [aString copy];
}

//	MARK: - PGURLLoad

- (id)initWithRequest:(NSURLRequest *)aRequest parent:(id<PGActivityOwner>)parent delegate:(NSObject<PGURLLoadDelegate> *)delegate
{
	if((self = [super init])) {
		_delegate = delegate;
		_loaded = NO;
		_request = [aRequest copy];
		_data = [[NSMutableData alloc] init];
		_activity = [[PGActivity alloc] initWithOwner:self];
		[_activity setParentActivity:[parent activity]];
		[[PGActivity applicationActivity] PG_startNextURLLoad];
	}
	return self;
}

//	MARK: -

- (NSObject<PGURLLoadDelegate> *)delegate
{
	return _delegate;
}
- (NSURLRequest *)request
{
#if __has_feature(objc_arc)
	return _request;
#else
	return [[_request retain] autorelease];
#endif
}
- (NSURLResponse *)response
{
#if __has_feature(objc_arc)
	return _response;
#else
	return [[_response retain] autorelease];
#endif
}
- (NSMutableData *)data
{
#if __has_feature(objc_arc)
	return _data;
#else
	return [[_data retain] autorelease];
#endif
}

//	MARK: -

- (void)cancelAndNotify:(BOOL)notify
{
	if([self loaded]) return;
	[self _stop];
#if !__has_feature(objc_arc)
	[_data release];
#endif
	_data = nil;
	if(notify) [[self delegate] loadDidCancel:self];
}
- (BOOL)loaded
{
	return _loaded;
}

//	MARK: - PGURLLoad(Private)

- (BOOL)_start
{
#if 1
	//	TODO: 2021/07/21 need to re-write using NSURLSession
	return NO;
#else
	if(_connection || [self loaded]) return NO;
	NSMutableURLRequest *const request = [[_request mutableCopy] autorelease];
	if([[self class] userAgent]) [request setValue:[[self class] userAgent] forHTTPHeaderField:@"User-Agent"];
	_connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
	[_connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:(NSString *)kCFRunLoopCommonModes];
	[_connection start];
	PGSimultaneousConnections++;
	return YES;
#endif
}
- (void)_stop
{
	if(!_connection) return;
	[_connection cancel];
#if !__has_feature(objc_arc)
	[_connection release];
#endif
	_connection = nil;
	PGSimultaneousConnections--;
	[_activity invalidate];
	[[PGActivity applicationActivity] PG_startNextURLLoad];
}

//	MARK: - NSObject

- (void)dealloc
{
	[self _stop];
#if !__has_feature(objc_arc)
	[_request release];
	[_response release];
	[_data release];
	[_activity release];	//	bugfix: was not being -release'd
	[super dealloc];
#endif
}

//	MARK: - NSObject(NSURLConnectionDelegate)

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	NSParameterAssert(connection == _connection);
#if !__has_feature(objc_arc)
	[_response autorelease];
#endif
	_response = [response copy];
	[[self delegate] loadDidReceiveResponse:self];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	NSParameterAssert(connection == _connection);
	[_data appendData:data];
	[[self delegate] loadLoadingDidProgress:self];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	NSParameterAssert(connection == _connection);
	[self _stop];
#if !__has_feature(objc_arc)
	[_data release];
#endif
	_data = nil;
	[[self delegate] loadDidFail:self];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	NSParameterAssert(connection == _connection);
	_loaded = YES;
	[self _stop];
	[[self delegate] loadDidSucceed:self];
}

//	MARK: - <PGActivityOwner>

#if !__has_feature(objc_arc)
@synthesize activity = _activity;
#endif

- (NSString *)descriptionForActivity:(PGActivity *)activity
{
	return [[_request URL] absoluteString];
}
- (CGFloat)progressForActivity:(PGActivity *)activity
{
	if([self loaded]) return 1.0f;
	if(!_response) return 0.0f;
	long long const expectedLength = [_response expectedContentLength];
	if(NSURLResponseUnknownLength == expectedLength) return 0.0f;
	return (CGFloat)[_data length] / (CGFloat)expectedLength;
}
- (void)cancelActivity:(PGActivity *)activity
{
	[self cancelAndNotify:YES];
}

@end

@implementation NSObject(PGURLLoadDelegate)

- (void)loadLoadingDidProgress:(PGURLLoad *)sender {}
- (void)loadDidReceiveResponse:(PGURLLoad *)sender {}
- (void)loadDidSucceed:(PGURLLoad *)sender {}
- (void)loadDidFail:(PGURLLoad *)sender {}
- (void)loadDidCancel:(PGURLLoad *)sender {}

@end

@implementation PGActivity(PGURLLoadStarting)

- (BOOL)PG_startNextURLLoad
{
	if(PGSimultaneousConnections >= PGMaxSimultaneousConnections) return YES;
	for(PGActivity *const activity in [self childActivities:NO]) {
		if([[activity owner] isKindOfClass:[PGURLLoad class]] && [(PGURLLoad *)[activity owner] _start]) return YES;
		if([activity PG_startNextURLLoad]) return YES;
	}
	return NO;
}

@end
