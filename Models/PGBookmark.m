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
#import "PGBookmark.h"

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGResourceIdentifier.h"
#import "PGSubscription.h"

// Other Sources
#import "PGFoundationAdditions.h"

NSString *const PGBookmarkDidUpdateNotification = @"PGBookmarkDidUpdate";

@interface PGBookmark ()

@property(nonatomic, strong) PGDisplayableIdentifier *documentIdentifier;
@property(nonatomic, strong) PGDisplayableIdentifier *fileIdentifier;
@property(nonatomic, assign) BOOL isValid;

@property(nonatomic, strong) PGSubscription *documentSubscription;
@property(nonatomic, strong) PGSubscription *fileSubscription;

@end

//	MARK: -
@implementation PGBookmark

+ (BOOL)supportsSecureCoding { return YES; }

- (id)initWithNode:(PGNode *)aNode
{
	return [self initWithDocumentIdentifier:[[aNode document] rootIdentifier] fileIdentifier:[aNode identifier] displayName:nil];
}
- (id)initWithDocumentIdentifier:(PGDisplayableIdentifier *)docIdent fileIdentifier:(PGDisplayableIdentifier *)fileIdent displayName:(NSString *)aString
{
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_documentIdentifier = docIdent;
#else
		_documentIdentifier = [docIdent retain];
#endif
		//	TODO: check whether removeObserver: should be called in -dealloc
		[_documentIdentifier PG_addObserver:self selector:@selector(identifierDidChange:) name:PGDisplayableIdentifierIconDidChangeNotification];
		//	TODO: check whether removeObserver: should be called in -dealloc
		[_documentIdentifier PG_addObserver:self selector:@selector(identifierDidChange:) name:PGDisplayableIdentifierDisplayNameDidChangeNotification];
#if __has_feature(objc_arc)
		_documentSubscription = [_documentIdentifier subscriptionWithDescendents:NO];
#else
		_documentSubscription = [[_documentIdentifier subscriptionWithDescendents:NO] retain];
#endif
		//	TODO: check whether removeObserver: should be called in -dealloc
		[_documentSubscription PG_addObserver:self selector:@selector(eventDidOccur:) name:PGSubscriptionEventDidOccurNotification];
#if __has_feature(objc_arc)
		_fileIdentifier = fileIdent;
#else
		_fileIdentifier = [fileIdent retain];
#endif
		//	TODO: check whether removeObserver: should be called in -dealloc
		[_fileIdentifier PG_addObserver:self selector:@selector(identifierDidChange:) name:PGDisplayableIdentifierIconDidChangeNotification];
		//	TODO: check whether removeObserver: should be called in -dealloc
		[_fileIdentifier PG_addObserver:self selector:@selector(identifierDidChange:) name:PGDisplayableIdentifierDisplayNameDidChangeNotification];
#if __has_feature(objc_arc)
		_fileSubscription = [_fileIdentifier subscriptionWithDescendents:NO];
#else
		_fileSubscription = [[_fileIdentifier subscriptionWithDescendents:NO] retain];
#endif
		//	TODO: check whether removeObserver: should be called in -dealloc
		[_fileSubscription PG_addObserver:self selector:@selector(eventDidOccur:) name:PGSubscriptionEventDidOccurNotification];
		if(aString) [_fileIdentifier setNaturalDisplayName:aString];
	}
	return self;
}

//	MARK: -

#if !__has_feature(objc_arc)
- (PGDisplayableIdentifier *)documentIdentifier
{
	return [[_documentIdentifier retain] autorelease];
}
- (PGDisplayableIdentifier *)fileIdentifier
{
	return [[_fileIdentifier retain] autorelease];
}
#endif
- (BOOL)isValid
{
#if __has_feature(objc_arc)
	if(!_documentIdentifier.hasTarget || !_fileIdentifier.hasTarget) return NO;
	if(!_documentIdentifier.isFileIdentifier || !_fileIdentifier.isFileIdentifier) return YES;
	return [_fileIdentifier.rootIdentifier.URL.path hasPrefix:_documentIdentifier.URL.path];
#else
	if(![_documentIdentifier hasTarget] || ![_fileIdentifier hasTarget]) return NO;
	if(![_documentIdentifier isFileIdentifier] || ![_fileIdentifier isFileIdentifier]) return YES;
	return [[[[_fileIdentifier rootIdentifier] URL] path] hasPrefix:[[_documentIdentifier URL] path]];
#endif
}

//	MARK: -

- (void)eventDidOccur:(NSNotification *)aNotif
{
	NSParameterAssert(aNotif);
	if([aNotif object] == _documentSubscription) [_documentIdentifier noteNaturalDisplayNameDidChange];
	else if([aNotif object] == _fileSubscription) [_fileIdentifier noteNaturalDisplayNameDidChange];
	[self PG_postNotificationName:PGBookmarkDidUpdateNotification];
}
- (void)identifierDidChange:(NSNotification *)aNotif
{
	[self PG_postNotificationName:PGBookmarkDidUpdateNotification];
}

//	MARK: - <NSCoding>

- (id)initWithCoder:(NSCoder *)aCoder
{
//	NSSet* classes = [NSSet setWithArray:@[PGDisplayableIdentifier.class, PGResourceIdentifier.class]];
	NSSet* classes = [NSSet setWithArray:@[NSData.class, PGDisplayableIdentifier.class, PGResourceIdentifier.class]];
	return [self initWithDocumentIdentifier:[aCoder decodeObjectOfClasses:classes forKey:@"DocumentIdentifier"]
//	return [self initWithDocumentIdentifier:[aCoder decodeObjectOfClass:[PGResourceIdentifier class] forKey:@"DocumentIdentifier"]
							 fileIdentifier:[aCoder decodeObjectOfClasses:classes forKey:@"FileIdentifier"]
								displayName:[aCoder decodeObjectOfClass:[NSString class] forKey:@"BackupDisplayName"]];
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_documentIdentifier forKey:@"DocumentIdentifier"];
	[aCoder encodeObject:_fileIdentifier forKey:@"FileIdentifier"];
	[aCoder encodeObject:[_fileIdentifier naturalDisplayName] forKey:@"BackupDisplayName"];
}

//	MARK: - <NSObject>

- (NSUInteger)hash
{
	return [[self class] hash] ^ [_documentIdentifier hash] ^ [_fileIdentifier hash];
}
- (BOOL)isEqual:(id)anObject
{
	return [anObject isMemberOfClass:[self class]] && PGEqualObjects([self documentIdentifier], [anObject documentIdentifier]) && PGEqualObjects([self fileIdentifier], [anObject fileIdentifier]);
}

//	MARK: - NSObject

- (void)dealloc
{
	[self PG_removeObserver];

#if !__has_feature(objc_arc)
	[_documentIdentifier release];
	[_documentSubscription release];
	[_fileIdentifier release];
	[_fileSubscription release];
	[super dealloc];
#endif
}

@end
