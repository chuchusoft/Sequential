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

#if __has_feature(objc_arc)

@interface PGDisplayableIdentifier ()

- (instancetype)initWithIdentifier:(PGResourceIdentifier *)ident NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder;//NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#else

@interface PGDisplayableIdentifier(Private)

- (instancetype)initWithIdentifier:(PGResourceIdentifier *)ident NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

#endif

//	MARK: -

//	intent: file:/// URLs
@interface PGAliasIdentifier : PGResourceIdentifier
#if !__has_feature(objc_arc)
{
@private
	NSData *_bookmark;
	NSURL *_cachedURL;
}
#endif

- (instancetype)initWithData:(NSData *)data NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithURL:(NSURL *)URL; // Must be a file URL.
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
//- (void)clearCache;

@end

//	MARK: -

//	intent: non-file:/// URLs
@interface PGURLIdentifier : PGResourceIdentifier
#if !__has_feature(objc_arc)
{
	@private
	NSURL *_URL;
}
#endif

- (instancetype)initWithURL:(NSURL *)URL NS_DESIGNATED_INITIALIZER; // Must not be a file URL.
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

//	MARK: -

@interface PGIndexIdentifier : PGResourceIdentifier
#if !__has_feature(objc_arc)
{
	@private
	PGResourceIdentifier *_superidentifier;
	NSInteger _index;
}
#endif

- (instancetype)initWithSuperidentifier:(PGResourceIdentifier *)identifier index:(NSInteger)index NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

//	MARK: -
@implementation PGResourceIdentifier

//	MARK: +PGResourceIdentifier

+ (BOOL) supportsSecureCoding { return YES; }

+ (instancetype)resourceIdentifierWithURL:(NSURL *)URL
{
#if __has_feature(objc_arc)
	return [[(URL.isFileURL ? [PGAliasIdentifier class] : [PGURLIdentifier class]) alloc] initWithURL:URL];
#else
	return [[[(URL.isFileURL ? [PGAliasIdentifier class] : [PGURLIdentifier class]) alloc] initWithURL:URL] autorelease];
#endif
}
/* + (id)resourceIdentifierWithAliasData:(const uint8_t *)data length:(NSUInteger)length
{
	return [[[PGAliasIdentifier alloc] initWithAliasData:data length:length] autorelease];
} */

//	MARK: - PGResourceIdentifier

- (instancetype)init {
	return [super init];
}

- (PGResourceIdentifier *)identifier
{
	return self;
}
- (PGDisplayableIdentifier *)displayableIdentifier
{
#if __has_feature(objc_arc)
	return [[PGDisplayableIdentifier alloc] initWithIdentifier:self];
#else
	return [[[PGDisplayableIdentifier alloc] initWithIdentifier:self] autorelease];
#endif
}
- (PGResourceIdentifier *)superidentifier
{
	return nil;
}
- (PGResourceIdentifier *)rootIdentifier
{
	return self.superidentifier ? self.superidentifier.rootIdentifier : self;
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

//	MARK: -

- (PGResourceIdentifier *)subidentifierWithIndex:(NSInteger)index
{
#if __has_feature(objc_arc)
	return [[PGIndexIdentifier alloc] initWithSuperidentifier:self index:index];
#else
	return [[[PGIndexIdentifier alloc] initWithSuperidentifier:self index:index] autorelease];
#endif
}

//	MARK: -

- (NSURL *)superURLByFollowingAliases:(BOOL)flag
{
	NSURL *const URL = [self URLByFollowingAliases:flag];
	return URL ? URL : [self.superidentifier superURLByFollowingAliases:flag];
}
- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return nil;
}
- (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)flag
{
	return NO;
}

//	MARK: -

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag
{
	return self.isFileIdentifier ? [PGSubscription subscriptionWithPath:self.URL.path descendents:flag] : nil;
}

//	MARK: - NSObject(NSKeyedArchiverObjectSubstitution)

- (Class)classForKeyedArchiver
{
	return [PGResourceIdentifier class];
}

//	MARK: - <NSSecureCoding>	//	NSCoding

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
	if([self class] == [PGResourceIdentifier class]) {
#if __has_feature(objc_arc)
		self = nil;
#else
		[self release];
#endif
		return [[PGDisplayableIdentifier alloc] initWithCoder:aCoder];
	}
	return [super init];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	if([self class] != [PGResourceIdentifier class] && [self class] != [PGDisplayableIdentifier class])
		[aCoder encodeObject:NSStringFromClass([self class]) forKey:@"ClassName"];
}

//	MARK: - <NSObject>

- (NSUInteger)hash
{
	return [[PGResourceIdentifier class] hash] ^ (NSUInteger)self.index;
}
- (BOOL)isEqual:(id)obj
{
	if(![obj isKindOfClass:[PGResourceIdentifier class]]) return NO;
	if(self.identifier == ((PGResourceIdentifier *)obj).identifier) return YES;
	if(self.index != ((PGResourceIdentifier *)obj).index) return NO;
	@autoreleasepool {
		if(!PGEqualObjects(self.superidentifier, [obj superidentifier])) return NO;
		return PGEqualObjects(self.URL, [obj URL]);
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@", self.URL];
}

@end

//	MARK: -
@implementation PGDisplayableIdentifier

//	MARK: +PGResourceIdentifier

+ (id)resourceIdentifierWithURL:(NSURL *)URL
{
#if __has_feature(objc_arc)
	return [[PGDisplayableIdentifier alloc] initWithIdentifier:[super resourceIdentifierWithURL:URL]];
#else
	return [[[self alloc] initWithIdentifier:[super resourceIdentifierWithURL:URL]] autorelease];
#endif
}
/* + (id)resourceIdentifierWithAliasData:(const uint8_t *)data length:(NSUInteger)length
{
	return [[[self alloc] _initWithIdentifier:[super resourceIdentifierWithAliasData:data length:length]] autorelease];
} */

//	MARK: - PGDisplayableIdentifier

#if __has_feature(objc_arc)
@synthesize identifier = _identifier;
@synthesize postsNotifications = _postsNotifications;
@synthesize icon = _icon;
@synthesize customDisplayName = _customDisplayName;
@synthesize naturalDisplayName = _naturalDisplayName;
#endif

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
#if __has_feature(objc_arc)
	return _icon ? _icon : [self.URL PG_icon];
#else
	return _icon ? [[_icon retain] autorelease] : [[self URL] PG_icon];
#endif
}
- (void)setIcon:(NSImage *)icon
{
	if(icon == _icon) return;
#if __has_feature(objc_arc)
	_icon = icon;
#else
	[_icon release];
	_icon = [icon retain];
#endif
	if(_postsNotifications)
		[self PG_postNotificationName:PGDisplayableIdentifierIconDidChangeNotification];
}
- (NSString *)displayName
{
#if __has_feature(objc_arc)
	return _customDisplayName ? _customDisplayName : self.naturalDisplayName;
#else
	return _customDisplayName ? [[_customDisplayName retain] autorelease] : [self naturalDisplayName];
#endif
}
- (NSString *)customDisplayName
{
#if __has_feature(objc_arc)
	return _customDisplayName;
#else
	return [[_customDisplayName retain] autorelease];
#endif
}
- (void)setCustomDisplayName:(NSString *)aString
{
	NSString *const string = aString.length ? aString : nil;
	if(PGEqualObjects(string, _customDisplayName)) return;
#if !__has_feature(objc_arc)
	[_customDisplayName release];
#endif
	_customDisplayName = [string copy];
	if(_postsNotifications) [self PG_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}
- (NSString *)naturalDisplayName
{
	if(_naturalDisplayName)
#if __has_feature(objc_arc)
		return _naturalDisplayName;
#else
		return [[_naturalDisplayName retain] autorelease];
#endif

	NSURL *const URL = self.URL;
#if 1
	if(!URL)
		return [NSString string];

	NSError* error = nil;
	NSString* name = nil;
	if([URL getResourceValue:&name forKey:NSURLLocalizedNameKey error:&error] && !error && name)
		return name;

	NSString *const path = URL.path;
	name = PGEqualObjects(path, @"/") ? URL.absoluteString : path.lastPathComponent;
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
#if !__has_feature(objc_arc)
	[_naturalDisplayName release];
#endif
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

//	MARK: -

- (NSAttributedString *)attributedStringWithAncestory:(BOOL)flag
{
	NSMutableAttributedString *const result = [NSMutableAttributedString PG_attributedStringWithFileIcon:self.icon name:self.displayName];
	if(!flag) return result;
	NSURL *const URL = self.URL;
	if(!URL) return result;
	NSString *const parent = URL.fileURL ? URL.path.stringByDeletingLastPathComponent : URL.absoluteString;
	NSString *const parentName = URL.fileURL ? parent.lastPathComponent : parent;
	if(!parentName.length) return result;
	[result.mutableString appendString:[NSString stringWithFormat:@" %C ", (unichar)0x2014]];
	[result appendAttributedString:[NSAttributedString PG_attributedStringWithFileIcon:URL.fileURL ? [[parent PG_fileURL] PG_icon] : nil name:parentName]];
	return result;
}
- (void)noteNaturalDisplayNameDidChange
{
	if(_postsNotifications && !_customDisplayName) [self PG_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}

//	MARK: - PGDisplayableIdentifier(Private)

- (instancetype)initWithIdentifier:(PGResourceIdentifier *)ident
{
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_identifier = ident.identifier;
#else
		_identifier = [ident.identifier retain];
#endif
	}
	return self;
}

//	MARK: - PGResourceIdentifier

- (PGResourceIdentifier *)identifier
{
	return _identifier.identifier;
}
- (PGDisplayableIdentifier *)displayableIdentifier
{
	return self;
}
- (PGResourceIdentifier *)superidentifier
{
	return _identifier.superidentifier;
}
- (PGResourceIdentifier *)rootIdentifier
{
	return _identifier.rootIdentifier;
}
- (NSURL *)URL
{
	return _identifier.URL;
}
- (NSInteger)index
{
	return _identifier.index;
}
- (BOOL)hasTarget
{
	return _identifier.hasTarget;
}
- (BOOL)isFileIdentifier
{
	return _identifier.isFileIdentifier;
}

//	MARK: -

- (PGResourceIdentifier *)subidentifierWithIndex:(NSInteger)index
{
	return [_identifier subidentifierWithIndex:index];
}

//	MARK: -

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

//	MARK: -

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag
{
	return [_identifier subscriptionWithDescendents:flag];
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_identifier release];
	[_icon release];
	[_naturalDisplayName release];
	[_customDisplayName release];
	[super dealloc];
}
#endif

//	MARK: - NSObject(AEAdditions)

- (void)PG_addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
{
	_postsNotifications = YES;
	[super PG_addObserver:observer selector:aSelector name:aName];
}

//	MARK: - <NSSecureCoding>	//	NSCoding

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
	Class class = NSClassFromString([aCoder decodeObjectOfClass:[NSString class] forKey:@"ClassName"]);
	if([PGResourceIdentifier class] == class || [PGDisplayableIdentifier class] == class)
		class = Nil;
#if __has_feature(objc_arc)
	if((self = [self initWithIdentifier:[[class alloc] initWithCoder:aCoder]])) {
		self.icon = [aCoder decodeObjectOfClass:[NSImage class] forKey:@"Icon"];
		self.customDisplayName = [aCoder decodeObjectOfClass:[NSString class] forKey:@"DisplayName"];
	}
#else
	if((self = [self initWithIdentifier:[[[class alloc] initWithCoder:aCoder] autorelease]])) {
		[self setIcon:[aCoder decodeObjectOfClass:[NSImage class] forKey:@"Icon"]];
		[self setCustomDisplayName:[aCoder decodeObjectOfClass:[NSString class] forKey:@"DisplayName"]];
	}
#endif
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[_identifier encodeWithCoder:aCoder]; // For backward compatibility, we can't use encodeObject:forKey:, so encode it directly.
	[aCoder encodeObject:_icon forKey:@"Icon"];
	[aCoder encodeObject:_customDisplayName forKey:@"DisplayName"];
}

//	MARK: - <NSObject>

- (BOOL)isEqual:(id)object {
	return [_identifier isEqual:object];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %@ (\"%@\")>", [self class], self, _identifier, self.displayName];
}

@end

//	MARK: -

#if __has_feature(objc_arc)

@interface PGAliasIdentifier ()

@property (nonatomic, strong) NSData *bookmark;
@property (nonatomic, strong) NSURL *cachedURL;

@end

#endif

//	MARK: -
@implementation PGAliasIdentifier

- (instancetype)initWithData:(NSData *)bookmarkData {	//	NS_DESIGNATED_INITIALIZER
	if(nil == bookmarkData) {
#if !__has_feature(objc_arc)
		[self release];
#endif
		self = nil;
		return self;
	}

	if((self = [super init])) {
#if __has_feature(objc_arc)
		_bookmark = bookmarkData;
#else
		_bookmark = [bookmarkData retain];
#endif
	}

	return self;
}

- (instancetype)initWithURL:(NSURL *)URL
{
	NSParameterAssert([URL isFileURL]);

	NSError* error = nil;
	if((self = [self initWithData:[URL bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
									// bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
								includingResourceValuesForKeys:nil
												 relativeToURL:nil
														 error:&error]])) {
#if __has_feature(objc_arc)
		_cachedURL = URL;
#else
		_cachedURL = [URL retain];
#endif
	}
	return self;
}

- (void)cacheURL:(NSURL *)URL
{
	BOOL const urlDidChange = (nil != _cachedURL || nil != URL) && ![_cachedURL isEqual:URL];
#if __has_feature(objc_arc)
	_cachedURL = URL;
#else
	[_cachedURL release];
	_cachedURL = URL ? [URL retain] : nil;
#endif
	if(urlDidChange)
		[self PG_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}

/* - (void)clearCache
{
	[_cachedURL release];
	_cachedURL = nil;
} */

//	MARK: - PGResourceIdentifier

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

//	MARK: -

- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
#if 1
	NSParameterAssert(_bookmark);
	if(!_bookmark)
		return nil;

	if(!flag && _cachedURL)
	#if __has_feature(objc_arc)
		return _cachedURL;
	#else
		return [[_cachedURL retain] autorelease];
	#endif

	BOOL bookmarkDataIsStale = NO;
	NSError* error = nil;
	//	when the target is offline (eg, on a server that is not mounted),
	//	the bookmark's resolution can be very slow; so use
	//	NSURLBookmarkResolutionWithoutMounting to not mount a server that
	//	may not be available/online; similarly for the url if it's an
	//	alias (flag = YES means "try to resolve any alias files")
	//	NB: the entry in the Recent Items sub-menu will not be displayed
	//	if it refers to a file server that isn't mounted because AppKit
	//	will remove it from the entries in the Recent Items sub-menu.
	NSURL* url = [NSURL URLByResolvingBookmarkData:_bookmark
										   options:(NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting)
									 relativeToURL:nil
							   bookmarkDataIsStale:&bookmarkDataIsStale
											 error:&error];

	if(flag && url)
		url = [NSURL URLByResolvingAliasFileAtURL:url
										  options:(NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting)
											error:&error];

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

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_bookmark release];
	[_cachedURL release];

	[super dealloc];
}
#endif

//	MARK: - <NSSecureCoding>	//	NSCoding

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
//NSLog(@"[aCoder allowedClasses] = %@", aCoder.allowedClasses);
		NSParameterAssert([aCoder.allowedClasses containsObject:NSData.class]);
#if __has_feature(objc_arc)
		_bookmark = [aCoder decodeDataObject];
#else
		_bookmark = [[aCoder decodeDataObject] retain];
#endif
		if(!_bookmark)
			_bookmark	=	[NSData new];
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];

	NSParameterAssert(_bookmark);
	[aCoder encodeDataObject:_bookmark];
}

//	MARK: - <NSObject>

- (BOOL)isEqual:(id)obj
{
	if(obj == self) return YES;
	if(![obj isKindOfClass:[PGAliasIdentifier class]])
		return [super isEqual:obj];
#if 1
	NSURL *const selfURL = [self URLByFollowingAliases:YES];
	NSURL *const objURL = [obj URLByFollowingAliases:YES];
	return [selfURL isEqual:objURL];
#else
	FSRef ourRef, theirRef;
	if(![self getRef:&ourRef byFollowingAliases:NO validate:NO] ||
	   ![obj getRef:&theirRef byFollowingAliases:NO validate:NO])
		return NO;
	return FSCompareFSRefs(&ourRef, &theirRef) == noErr;
#endif
}

@end

//	MARK: -

#if __has_feature(objc_arc)

@interface PGURLIdentifier ()

@property (nonatomic, strong) NSURL *URL;

- (instancetype)initWithURL:(NSURL *)URL; // Must not be a file URL.

@end

#endif

//	MARK: -
@implementation PGURLIdentifier

#if __has_feature(objc_arc)
@synthesize URL = _URL;
#endif

- (instancetype)initWithURL:(NSURL *)URL
{
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_URL = URL;
#else
		_URL = [URL retain];
#endif
	}
	return self;
}

//	MARK: - PGResourceIdentifier

- (BOOL)hasTarget
{
	return YES;
}
- (BOOL)isFileIdentifier
{
	return _URL.fileURL;
}

//	MARK: -

- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
#if __has_feature(objc_arc)
	return _URL;
#else
	return [[_URL retain] autorelease];
#endif
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_URL release];
	[super dealloc];
}
#endif

//	MARK: - <NSSecureCoding>	//	NSCoding

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
#if __has_feature(objc_arc)
		_URL = [aCoder decodeObjectOfClass:[NSURL class] forKey:@"URL"];
#else
		_URL = [[aCoder decodeObjectOfClass:[NSURL class] forKey:@"URL"] retain];
#endif
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_URL forKey:@"URL"];
}

@end

//	MARK: -

#if __has_feature(objc_arc)

@interface PGIndexIdentifier ()

@property (nonatomic, strong) PGResourceIdentifier *superidentifier;
@property (nonatomic, assign) NSInteger index;

- (instancetype)initWithSuperidentifier:(PGResourceIdentifier *)identifier index:(NSInteger)index;

@end

#endif

//	MARK: -
@implementation PGIndexIdentifier

#if __has_feature(objc_arc)
@synthesize superidentifier = _superidentifier;
@synthesize index = _index;
#endif

- (instancetype)initWithSuperidentifier:(PGResourceIdentifier *)identifier index:(NSInteger)index
{
	NSParameterAssert(identifier);
	if((self = [super init])) {
#if __has_feature(objc_arc)
		_superidentifier = identifier;
#else
		_superidentifier = [identifier retain];
#endif
		_index = index;
	}
	return self;
}

//	MARK: - PGResourceIdentifier

- (PGResourceIdentifier *)superidentifier
{
#if __has_feature(objc_arc)
	return _superidentifier;
#else
	return [[_superidentifier retain] autorelease];
#endif
}
- (NSInteger)index
{
	return _index;
}
- (BOOL)hasTarget
{
	return NSNotFound != _index && _superidentifier.hasTarget;
}
- (BOOL)isFileIdentifier
{
	return _superidentifier.isFileIdentifier;
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_superidentifier release];
	[super dealloc];
}
#endif

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@:%ld", self.superidentifier, (long)self.index];
}

//	MARK: - <NSSecureCoding>	//	NSCoding

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
		//	2023/08/12 bugfix: NSKeyedUnarchiver requires the allowedClasses property of
		//	the NSCoder instance to contain the set of all classes that could be decoded
		NSSet* classes = [NSSet setWithArray:@[NSData.class, PGResourceIdentifier.class]];
#if __has_feature(objc_arc)
		_superidentifier = [aCoder decodeObjectOfClasses:classes forKey:@"Superidentifier"];
#else
		_superidentifier = [[aCoder decodeObjectOfClasses:classes forKey:@"Superidentifier"] retain];
#endif
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

@end

//	MARK: -
@implementation NSURL(PGResourceIdentifierCreation)

- (PGResourceIdentifier *)PG_resourceIdentifier
{
	return [PGResourceIdentifier resourceIdentifierWithURL:self];
}
- (PGDisplayableIdentifier *)PG_displayableIdentifier
{
#if __has_feature(objc_arc)
	return [[PGDisplayableIdentifier alloc] initWithIdentifier:self.PG_resourceIdentifier];
#else
	return [[[PGDisplayableIdentifier alloc] initWithIdentifier:[self PG_resourceIdentifier]] autorelease];
#endif
}

@end
