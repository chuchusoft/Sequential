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
#import "PGResourceIdentifier.h"

// Models
#import "PGSubscription.h"

// Other Sources
#import "PGAttachments.h"
#import "PGFoundationAdditions.h"

NSString *const PGDisplayableIdentifierIconDidChangeNotification = @"PGDisplayableIdentifierIconDidChange";
NSString *const PGDisplayableIdentifierDisplayNameDidChangeNotification = @"PGDisplayableIdentifierDisplayNameDidChange";

@interface PGDisplayableIdentifier(Private)

- (id)_initWithIdentifier:(PGResourceIdentifier *)ident;

@end

//	intent: file:/// URLs
@interface PGAliasIdentifier : PGResourceIdentifier <NSSecureCoding>	//	NSCoding
{
@private
	NSData *_bookmarkedURL;
	NSURL *_cachedURL;
}

- (id)initWithURL:(NSURL *)URL; // Must be a file URL.
//- (void)clearCache;

@end

//	intent: non-file:/// URLs
@interface PGURLIdentifier : PGResourceIdentifier <NSSecureCoding>	//	NSCoding
{
	@private
	NSURL *_URL;
}

- (id)initWithURL:(NSURL *)URL; // Must not be a file URL.

@end

@interface PGIndexIdentifier : PGResourceIdentifier <NSSecureCoding>	//	NSCoding
{
	@private
	PGResourceIdentifier *_superidentifier;
	NSInteger _index;
}

- (id)initWithSuperidentifier:(PGResourceIdentifier *)identifier index:(NSInteger)index;

@end

@implementation PGResourceIdentifier

#pragma mark +PGResourceIdentifier

+ (BOOL) supportsSecureCoding { return YES; }

+ (id)resourceIdentifierWithURL:(NSURL *)URL
{
	return [[[(URL.isFileURL ? [PGAliasIdentifier class] : [PGURLIdentifier class]) alloc] initWithURL:URL] autorelease];
}
/* + (id)resourceIdentifierWithAliasData:(const uint8_t *)data length:(NSUInteger)length
{
	return [[[PGAliasIdentifier alloc] initWithAliasData:data length:length] autorelease];
} */

#pragma mark -PGResourceIdentifier

- (PGResourceIdentifier *)identifier
{
	return self;
}
- (PGDisplayableIdentifier *)displayableIdentifier
{
	return [[[PGDisplayableIdentifier alloc] _initWithIdentifier:self] autorelease];
}
- (PGResourceIdentifier *)superidentifier
{
	return nil;
}
- (PGResourceIdentifier *)rootIdentifier
{
	return [self superidentifier] ? [[self superidentifier] rootIdentifier] : self;
}
- (NSURL *)URL
{
	return [self URLByFollowingAliases:NO];
}
- (NSInteger)index
{
	return NSNotFound;
}
- (BOOL)hasTarget
{
	return NO;
}
- (BOOL)isFileIdentifier
{
	return NO;
}

#pragma mark -

- (PGResourceIdentifier *)subidentifierWithIndex:(NSInteger)index
{
	return [[[PGIndexIdentifier alloc] initWithSuperidentifier:self index:index] autorelease];
}

#pragma mark -

- (NSURL *)superURLByFollowingAliases:(BOOL)flag
{
	NSURL *const URL = [self URLByFollowingAliases:flag];
	return URL ? URL : [[self superidentifier] superURLByFollowingAliases:flag];
}
- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return nil;
}
- (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)flag
{
	return NO;
}

#pragma mark -

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag
{
	return [self isFileIdentifier] ? [PGSubscription subscriptionWithPath:[[self URL] path] descendents:flag] : nil;
}

#pragma mark -NSObject(NSKeyedArchiverObjectSubstitution)

- (Class)classForKeyedArchiver
{
	return [PGResourceIdentifier class];
}

#pragma mark -<NSSecureCoding>	//	NSCoding

- (id)initWithCoder:(NSCoder *)aCoder
{
	if([self class] == [PGResourceIdentifier class]) {
		[self release];
		return [[PGDisplayableIdentifier alloc] initWithCoder:aCoder];
	}
	return [self init];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	if([self class] != [PGResourceIdentifier class] && [self class] != [PGDisplayableIdentifier class])
		[aCoder encodeObject:NSStringFromClass([self class]) forKey:@"ClassName"];
}

#pragma mark -<NSObject>

- (NSUInteger)hash
{
	return [[PGResourceIdentifier class] hash] ^ (NSUInteger)[self index];
}
- (BOOL)isEqual:(id)obj
{
	if(![obj isKindOfClass:[PGResourceIdentifier class]]) return NO;
	if([self identifier] == [(PGResourceIdentifier *)obj identifier]) return YES;
	if([self index] != [(PGResourceIdentifier *)obj index]) return NO;
	@autoreleasepool {
		if(!PGEqualObjects([self superidentifier], [obj superidentifier])) return NO;
		return PGEqualObjects([self URL], [obj URL]);
	}
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@", [self URL]];
}

@end

@implementation PGDisplayableIdentifier

#pragma mark +PGResourceIdentifier

+ (id)resourceIdentifierWithURL:(NSURL *)URL
{
	return [[[self alloc] _initWithIdentifier:[super resourceIdentifierWithURL:URL]] autorelease];
}
/* + (id)resourceIdentifierWithAliasData:(const uint8_t *)data length:(NSUInteger)length
{
	return [[[self alloc] _initWithIdentifier:[super resourceIdentifierWithAliasData:data length:length]] autorelease];
} */

#pragma mark -PGDisplayableIdentifier

- (BOOL)postsNotifications
{
	return _postsNotifications;
}
- (void)setPostsNotifications:(BOOL)flag
{
	if(flag) _postsNotifications = YES;
}
- (NSImage *)icon
{
	return _icon ? [[_icon retain] autorelease] : [[self URL] PG_icon];
}
- (void)setIcon:(NSImage *)icon
{
	if(icon == _icon) return;
	[_icon release];
	_icon = [icon retain];
	if(_postsNotifications) [self PG_postNotificationName:PGDisplayableIdentifierIconDidChangeNotification];
}
- (NSString *)displayName
{
	return _customDisplayName ? [[_customDisplayName retain] autorelease] : [self naturalDisplayName];
}
- (NSString *)customDisplayName
{
	return [[_customDisplayName retain] autorelease];
}
- (void)setCustomDisplayName:(NSString *)aString
{
	NSString *const string = [aString length] ? aString : nil;
	if(PGEqualObjects(string, _customDisplayName)) return;
	[_customDisplayName release];
	_customDisplayName = [string copy];
	if(_postsNotifications) [self PG_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}
- (NSString *)naturalDisplayName
{
	if(_naturalDisplayName)
		return [[_naturalDisplayName retain] autorelease];

	NSURL *const URL = [self URL];
#if 1
	if(!URL)
		return [NSString string];

	NSError* error = nil;
	NSString* name = nil;
	if([URL getResourceValue:&name forKey:NSURLLocalizedNameKey error:&error] && !error && name)
		return name;

	NSString *const path = [URL path];
	name = PGEqualObjects(path, @"/") ? [URL absoluteString] : [path lastPathComponent];
	return [name PG_stringByReplacingOccurrencesOfCharactersInSet:NSCharacterSet.newlineCharacterSet
													   withString:[NSString string]];
#else
	NSString *name = @"";
	if(URL) {
		if(LSCopyDisplayNameForURL((CFURLRef)URL, (CFStringRef *)&name) == noErr && name)
			[name autorelease];
		else {
			NSString *const path = [URL path];
			name = PGEqualObjects(path, @"/") ? [URL absoluteString] : [path lastPathComponent];
		}
	}
	return [name PG_stringByReplacingOccurrencesOfCharactersInSet:[NSCharacterSet newlineCharacterSet] withString:@""];
#endif
}
- (void)setNaturalDisplayName:(NSString *)aString
{
	if(PGEqualObjects(aString, _naturalDisplayName)) return;
	[_naturalDisplayName release];
	_naturalDisplayName = [aString copy];
	[self noteNaturalDisplayNameDidChange];
}
#if 1
- (NSColor*)labelColor
{
	NSError* error = nil;
	NSColor* value = nil;
	if(![self.URL getResourceValue:&value forKey:NSURLLabelColorKey error:&error] || error)
		return nil;
	return value;
}
#else
//- (PGLabelColor)labelColor	2021/07/21 modernized
{
	FSRef ref;
	FSCatalogInfo catalogInfo;
	if(![self getRef:&ref byFollowingAliases:NO] || FSGetCatalogInfo(&ref, kFSCatInfoFinderInfo | kFSCatInfoNodeFlags, &catalogInfo, NULL, NULL, NULL) != noErr) return PGLabelNone;
	UInt16 finderFlags;
	if(catalogInfo.nodeFlags & kFSNodeIsDirectoryMask) finderFlags = ((FolderInfo *)&catalogInfo.finderInfo)->finderFlags;
	else finderFlags = ((FileInfo *)&catalogInfo.finderInfo)->finderFlags;
	return (finderFlags >> 1) & 0x07;
}
#endif

#pragma mark -

- (NSAttributedString *)attributedStringWithAncestory:(BOOL)flag
{
	NSMutableAttributedString *const result = [NSMutableAttributedString PG_attributedStringWithFileIcon:[self icon] name:[self displayName]];
	if(!flag) return result;
	NSURL *const URL = [self URL];
	if(!URL) return result;
	NSString *const parent = [URL isFileURL] ? [[URL path] stringByDeletingLastPathComponent] : [URL absoluteString];
	NSString *const parentName = [URL isFileURL] ? [parent lastPathComponent] : parent;
	if(![parentName length]) return result;
	[[result mutableString] appendString:[NSString stringWithFormat:@" %C ", (unichar)0x2014]];
	[result appendAttributedString:[NSAttributedString PG_attributedStringWithFileIcon:[URL isFileURL] ? [[parent PG_fileURL] PG_icon] : nil name:parentName]];
	return result;
}
- (void)noteNaturalDisplayNameDidChange
{
	if(_postsNotifications && !_customDisplayName) [self PG_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}

#pragma mark -PGDisplayableIdentifier(Private)

- (id)_initWithIdentifier:(PGResourceIdentifier *)ident
{
	if((self = [super init])) {
		_identifier = [[ident identifier] retain];
	}
	return self;
}

#pragma mark -PGResourceIdentifier

- (PGResourceIdentifier *)identifier
{
	return [_identifier identifier];
}
- (PGDisplayableIdentifier *)displayableIdentifier
{
	return self;
}
- (PGResourceIdentifier *)superidentifier
{
	return [_identifier superidentifier];
}
- (PGResourceIdentifier *)rootIdentifier
{
	return [_identifier rootIdentifier];
}
- (NSURL *)URL
{
	return [_identifier URL];
}
- (NSInteger)index
{
	return [_identifier index];
}
- (BOOL)hasTarget
{
	return [_identifier hasTarget];
}
- (BOOL)isFileIdentifier
{
	return [_identifier isFileIdentifier];
}

#pragma mark -

- (PGResourceIdentifier *)subidentifierWithIndex:(NSInteger)index
{
	return [_identifier subidentifierWithIndex:index];
}

#pragma mark -

- (NSURL *)superURLByFollowingAliases:(BOOL)flag
{
	return [_identifier superURLByFollowingAliases:flag];
}
- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return [_identifier URLByFollowingAliases:flag];
}
/* - (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)flag
{
	return [_identifier getRef:outRef byFollowingAliases:flag];
} */

#pragma mark -

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag
{
	return [_identifier subscriptionWithDescendents:flag];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_identifier release];
	[_icon release];
	[_naturalDisplayName release];
	[_customDisplayName release];
	[super dealloc];
}

#pragma mark -NSObject(AEAdditions)

- (void)PG_addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
{
	_postsNotifications = YES;
	[super PG_addObserver:observer selector:aSelector name:aName];
}

#pragma mark -<NSSecureCoding>	//	NSCoding

- (id)initWithCoder:(NSCoder *)aCoder
{
	Class class = NSClassFromString([aCoder decodeObjectOfClass:[NSString class] forKey:@"ClassName"]);
	if([PGResourceIdentifier class] == class || [PGDisplayableIdentifier class] == class)
		class = Nil;
	if((self = [self _initWithIdentifier:[[[class alloc] initWithCoder:aCoder] autorelease]])) {
		[self setIcon:[aCoder decodeObjectOfClass:[NSImage class] forKey:@"Icon"]];
		[self setCustomDisplayName:[aCoder decodeObjectOfClass:[NSString class] forKey:@"DisplayName"]];
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[_identifier encodeWithCoder:aCoder]; // For backward compatibility, we can't use encodeObject:forKey:, so encode it directly.
	[aCoder encodeObject:_icon forKey:@"Icon"];
	[aCoder encodeObject:_customDisplayName forKey:@"DisplayName"];
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %@ (\"%@\")>", [self class], self, _identifier, [self displayName]];
}

@end

#pragma mark -
@implementation PGAliasIdentifier

- (id)initWithURL:(NSURL *)URL
{
	NSParameterAssert([URL isFileURL]);
	if((self = [super init])) {
#if 1
		NSError* error = nil;
		_bookmarkedURL = [[URL bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
							// bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
						includingResourceValuesForKeys:nil
										 relativeToURL:nil
												 error:&error] retain];
#else
		if(!CFURLGetFSRef((CFURLRef)URL, &_ref) ||
		   FSNewAliasMinimal(&_ref, &_alias) != noErr) {
			[self release];
			return (PGAliasIdentifier *)[[PGURLIdentifier alloc] initWithURL:URL];
		}
		_hasValidRef = YES;
		[self cacheURL:URL];
#endif
	}
	return self;
}

#if 1

- (void)cacheURL:(NSURL *)URL
{
	if(!URL) return;
	[_cachedURL release];
	_cachedURL = [URL retain];
}

#else

- (id)initWithAliasData:(const uint8_t *)data length:(NSUInteger)length
{
	if((self = [super init])) {
		if(![self setAliasWithData:data length:length]) {
			[self release];
			return nil;
		}
	}
	return self;
}
- (BOOL)setAliasWithData:(const uint8_t *)data length:(NSUInteger)length
{
	if(!data || !length) return NO;
	_alias = (AliasHandle)NewHandle(length);
	if(!_alias) return NO;
	memcpy(*_alias, data, length);
	return YES;
}
- (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)follow validate:(BOOL)validate
{
	Boolean dontCare1, dontCare2;
	if(validate && _hasValidRef && !follow) _hasValidRef = FSIsFSRefValid(&_ref);
	if(!_hasValidRef && FSResolveAliasWithMountFlags(NULL, _alias, &_ref, &dontCare1, kResolveAliasFileNoUI) != noErr) return NO;
	_hasValidRef = YES;
	if(outRef) *outRef = _ref;
	return follow ? FSResolveAliasFileWithMountFlags(outRef, true, &dontCare1, &dontCare2, kResolveAliasFileNoUI) == noErr : YES;
}
- (void)cacheURL:(NSURL *)URL
{
	if(!URL) return;
	[_cachedURL release];
	_cachedURL = [URL retain];
	if(!PGCachedAliasIdentifiers) {
		PGCachedAliasIdentifiers = [[NSMutableArray alloc] init];
		[PGAliasIdentifier performSelector:@selector(clearCache) withObject:nil afterDelay:0.0f];
	}
	[PGCachedAliasIdentifiers addObject:self];
}

#endif

/* - (void)clearCache
{
	[_cachedURL release];
	_cachedURL = nil;
} */

#pragma mark -PGResourceIdentifier

- (BOOL)hasTarget
{
//	return [self getRef:NULL byFollowingAliases:NO validate:YES];
	NSError* error = nil;
	return [self.URL checkResourceIsReachableAndReturnError:&error];
}
- (BOOL)isFileIdentifier
{
	return YES;
}

#pragma mark -

- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
#if 1
	NSParameterAssert(_bookmarkedURL);
	if(!_bookmarkedURL)
		return nil;

	if(!flag && _cachedURL)
		return [[_cachedURL retain] autorelease];

	BOOL bookmarkDataIsStale = NO;
	NSError* error = nil;
	NSURL* url = [NSURL URLByResolvingBookmarkData:_bookmarkedURL
										   options:NSURLBookmarkResolutionWithoutUI
									 relativeToURL:nil
							   bookmarkDataIsStale:&bookmarkDataIsStale
											 error:&error];

	if(flag && url)
		url = [NSURL URLByResolvingAliasFileAtURL:url
										  options:NSURLBookmarkResolutionWithoutUI
											error:&error];

	if(!flag && url)
		[self cacheURL:url];

	return url;
#else
	if(!flag && _cachedURL)
		return [[_cachedURL retain] autorelease];

	FSRef ref;
	if(![self getRef:&ref byFollowingAliases:flag])
		return nil;

	NSURL *const URL = [(NSURL *)CFURLCreateFromFSRef(kCFAllocatorDefault, &ref) autorelease];
	if(!flag) [self cacheURL:URL];
	return URL;
#endif
}
/* - (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)flag
{
	return [self getRef:outRef byFollowingAliases:flag validate:YES];
} */

#pragma mark -NSObject

- (void)dealloc
{
	[_bookmarkedURL release];
	[_cachedURL release];

	[super dealloc];
}

#pragma mark -<NSSecureCoding>	//	NSCoding

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
#if 1
//NSLog(@"[aCoder allowedClasses] = %@", aCoder.allowedClasses);
		NSParameterAssert([aCoder.allowedClasses containsObject:NSData.class]);
		_bookmarkedURL = [[aCoder decodeDataObject] retain];
		if(!_bookmarkedURL)
			_bookmarkedURL	=	[NSData new];
#else
		NSUInteger length;
		uint8_t const *const data = [aCoder decodeBytesForKey:@"Alias" returnedLength:&length];
		if(![self setAliasWithData:data length:length]) {
			[self release];
			return nil;
		}
#endif
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
#if 1
	NSParameterAssert(_bookmarkedURL);
	[aCoder encodeDataObject:_bookmarkedURL];
#else
	if(_alias)
		[aCoder encodeBytes:(uint8_t const *)*_alias length:GetHandleSize((Handle)_alias) forKey:@"Alias"];
#endif
}

#pragma mark -<NSObject>

- (BOOL)isEqual:(id)obj
{
	if(obj == self) return YES;
	if(![obj isKindOfClass:[PGAliasIdentifier class]])
		return [super isEqual:obj];
#if 1
	return [self.identifier isEqual:((PGAliasIdentifier*)obj).identifier];
#else
	FSRef ourRef, theirRef;
	if(![self getRef:&ourRef byFollowingAliases:NO validate:NO] ||
	   ![obj getRef:&theirRef byFollowingAliases:NO validate:NO])
		return NO;
	return FSCompareFSRefs(&ourRef, &theirRef) == noErr;
#endif
}

@end

@implementation PGURLIdentifier

#pragma mark -PGURLIdentifier

- (id)initWithURL:(NSURL *)URL
{
	if((self = [super init])) {
		_URL = [URL retain];
	}
	return self;
}

#pragma mark -PGResourceIdentifier

- (BOOL)hasTarget
{
	return YES;
}
- (BOOL)isFileIdentifier
{
	return [_URL isFileURL];
}

#pragma mark -

- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return [[_URL retain] autorelease];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_URL release];
	[super dealloc];
}

#pragma mark -<NSSecureCoding>	//	NSCoding

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
		_URL = [[aCoder decodeObjectOfClass:[NSURL class] forKey:@"URL"] retain];
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_URL forKey:@"URL"];
}

@end

@implementation PGIndexIdentifier

#pragma mark -PGIndexIdentifier

- (id)initWithSuperidentifier:(PGResourceIdentifier *)identifier index:(NSInteger)index
{
	NSParameterAssert(identifier);
	if((self = [super init])) {
		_superidentifier = [identifier retain];
		_index = index;
	}
	return self;
}

#pragma mark -PGResourceIdentifier

- (PGResourceIdentifier *)superidentifier
{
	return [[_superidentifier retain] autorelease];
}
- (NSInteger)index
{
	return _index;
}
- (BOOL)hasTarget
{
	return NSNotFound != _index && [_superidentifier hasTarget];
}
- (BOOL)isFileIdentifier
{
	return [_superidentifier isFileIdentifier];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_superidentifier release];
	[super dealloc];
}

#pragma mark -<NSSecureCoding>	//	NSCoding

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
		//	2023/08/12 bugfix: NSKeyedUnarchiver requires the allowedClasses property of
		//	the NSCoder instance to contain the set of all classes that could be decoded
		NSSet* classes = [NSSet setWithArray:@[NSData.class, PGResourceIdentifier.class]];
		_superidentifier = [[aCoder decodeObjectOfClasses:classes forKey:@"Superidentifier"] retain];
		_index = [aCoder decodeIntegerForKey:@"Index"];
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_superidentifier forKey:@"Superidentifier"];
	[aCoder encodeInteger:_index forKey:@"Index"];
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@:%ld", [self superidentifier], (long)[self index]];
}

@end

@implementation NSURL(PGResourceIdentifierCreation)

- (PGResourceIdentifier *)PG_resourceIdentifier
{
	return [PGResourceIdentifier resourceIdentifierWithURL:self];
}
- (PGDisplayableIdentifier *)PG_displayableIdentifier
{
	return [[[PGDisplayableIdentifier alloc] _initWithIdentifier:[self PG_resourceIdentifier]] autorelease];
}

@end
