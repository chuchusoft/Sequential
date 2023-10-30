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

//
//  PGResourceDataProvider.m
//  Created 2023/10/22.
//
#import "PGResourceDataProvider.h"

// Models
#import "PGResourceIdentifier.h"

// Other Sources
#import "PGFoundationAdditions.h"

@implementation PGResourceDataProvider

- (id)initWithResourceIdentifier:(PGResourceIdentifier *)ident displayableName:(NSString *)name
{
	if((self = [super init])) {
		_identifier = [ident retain];
		_displayableName = [name copy];
	}
	return self;
}
/* - (id)valueForLSAttributeName:(CFStringRef)name
{
	FSRef ref;
	if(![_identifier getRef:&ref byFollowingAliases:NO]) return nil;
	id val = nil;
	if(noErr != LSCopyItemAttribute(&ref, kLSRolesViewer, name, (CFTypeRef *)&val)) return nil;
	return [val autorelease];
} */

- (id)valueForResourceKey:(NSURLResourceKey)key {
	NSError* error = nil;
	id value = nil;
	if(![_identifier.URL getResourceValue:&value forKey:key error:&error] || error)
		return nil;
	return value;
}

- (id)valueForFMAttributeName:(NSString *)name
{
	return [_identifier isFileIdentifier] ? [[[NSFileManager defaultManager] attributesOfItemAtPath:[[_identifier URL] path] error:NULL] objectForKey:name] : nil;
}

#pragma mark -PGDataProvider

- (PGResourceIdentifier *)identifier
{
	return [[_identifier retain] autorelease];
}
- (NSString *)displayableName
{
//	return _displayableName ? _displayableName : [self valueForLSAttributeName:kLSItemDisplayName];
	return _displayableName ? _displayableName : [self valueForResourceKey:NSURLLocalizedNameKey];
}
- (NSData *)data
{
	return [[[NSData alloc] initWithContentsOfURL:[_identifier URL]
										  options:NSDataReadingMapped | NSDataReadingUncached
											error:NULL] autorelease];
}
- (uint64_t)dataByteSize
{
	return (uint64_t) [[self valueForFMAttributeName:NSFileSize] unsignedLongValue];
}

#pragma mark -

- (NSString *)UTIType
{
//	return [self valueForLSAttributeName:kLSItemContentType];
	return [self valueForResourceKey:NSURLTypeIdentifierKey];
}
/* - (NSString *)MIMEType
{
	return [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)[self UTIType], kUTTagClassMIMEType) autorelease];
}
- (OSType)typeCode
{
	return PGOSTypeFromString([self valueForLSAttributeName:kLSItemFileType]);
} */
- (NSString *)extension
{
//	return [[self valueForLSAttributeName:kLSItemExtension] lowercaseString];
	return _identifier.URL.pathExtension;
}

#pragma mark -

- (NSDate *)dateModified
{
	return [self valueForFMAttributeName:NSFileModificationDate];
}
- (NSDate *)dateCreated
{
	return [self valueForFMAttributeName:NSFileCreationDate];
}

#pragma mark -

- (BOOL)hasData
{
	return PGEqualObjects([self valueForFMAttributeName:NSFileType], NSFileTypeRegular);
}
/* - (NSNumber *)dataLength
{	2023/09/17 deprecated
	return [self valueForFMAttributeName:NSFileSize];
} */
- (NSImage *)icon
{
	return [[NSWorkspace sharedWorkspace] iconForFile:[[_identifier URL] path]];
}
- (NSString *)kindString
{
	NSString* uniformTypeIdentifier = [self UTIType];
	NSParameterAssert(uniformTypeIdentifier);
	CFStringRef desc = UTTypeCopyDescription((CFStringRef) uniformTypeIdentifier);
	NSParameterAssert(desc);
	return [(NSString *)desc autorelease];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_identifier release];
	[_displayableName release];
	[super dealloc];
}

@end
