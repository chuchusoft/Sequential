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
#import "PGFoundationAdditions.h"
#import <objc/runtime.h>

// Other Sources
#import "PGDebug.h"

NSString *const PGCFBundleHelpBookNameKey = @"CFBundleHelpBookName";

NSString *PGOSTypeToStringQuoted(OSType type, BOOL flag)
{
	return flag ? NSFileTypeForHFSTypeCode(type) : [(NSString *)UTCreateStringForOSType(type) autorelease];
}
OSType PGOSTypeFromString(NSString *str)
{
	if(!str) return 0;
	switch([str length]) {
		case 4: return UTGetOSTypeFromString((CFStringRef)str);
		case 6: return NSHFSTypeCodeFromFileType(str);
		default: return 0;
	}
}

@implementation NSAffineTransform(PGFoundationAdditions)

#pragma mark -NSAffineTransform(PGFoundationAdditions)

+ (id)PG_transformWithRect:(inout NSRectPointer)rectPtr orientation:(PGOrientation)orientation
{
	NSAffineTransform *const transform = [self transform];
	if(PGUpright == orientation) return transform;
	[transform translateXBy:NSMidX(*rectPtr) yBy:NSMidY(*rectPtr)];
	if(orientation & PGRotated90CCW) {
		[transform rotateByDegrees:90.0f];
		rectPtr->size = NSMakeSize(NSHeight(*rectPtr), NSWidth(*rectPtr)); // Swap.
	}
	[transform scaleXBy:(orientation & PGFlippedHorz ? -1.0f : 1.0f) yBy:orientation & PGFlippedVert ? -1.0f : 1.0f];
	[transform translateXBy:-NSMidX(*rectPtr) yBy:-NSMidY(*rectPtr)];
	return transform;
}
+ (id)PG_counterflipWithRect:(inout NSRectPointer)rectPtr
{
	return [[NSGraphicsContext currentContext] isFlipped] ? [self PG_transformWithRect:rectPtr orientation:PGFlippedVert] : [self transform];
}

@end

@implementation NSArray(PGFoundationAdditions)

#pragma mark +NSArray(PGFoundationAdditions)

+ (id)PG_arrayWithContentsOfArrays:(NSArray *)first, ...
{
	if(!first) return [self array];
	NSMutableArray *const result = [[first mutableCopy] autorelease];
	NSArray *array;
	va_list list;
	va_start(list, first);
	while((array = va_arg(list, NSArray *))) [result addObjectsFromArray:array];
	va_end(list);
	return result;
}

#pragma mark -NSArray(PGFoundationAdditions)

- (NSArray *)PG_arrayWithUniqueObjects
{
	NSMutableArray *const array = [[self mutableCopy] autorelease];
	NSUInteger i = 0, count;
	for(; i < (count = [array count]); i++) [array removeObject:[array objectAtIndex:i] inRange:NSMakeRange(i + 1, count - i - 1)];
	return array;
}
- (void)PG_addObjectObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
{
	for(id const obj in self) [obj PG_addObserver:observer selector:aSelector name:aName];
}
- (void)PG_removeObjectObserver:(id)observer name:(NSString *)aName
{
	for(id const obj in self) [obj PG_removeObserver:observer name:aName];
}

@end

@implementation NSDate(PGFoundationAdditions)

- (BOOL)PG_isAfter:(NSDate *)date
{
	return [self earlierDate:date] != self;
}
- (NSString *)PG_localizedStringWithDateStyle:(CFDateFormatterStyle)dateStyle timeStyle:(CFDateFormatterStyle)timeStyle
{
	static CFDateFormatterRef f = nil;
	if(!f || CFDateFormatterGetDateStyle(f) != dateStyle || CFDateFormatterGetTimeStyle(f) != timeStyle) {
		if(f) CFRelease(f);
		CFLocaleRef const locale = CFLocaleCopyCurrent();
		f = CFDateFormatterCreate(kCFAllocatorDefault, locale, dateStyle, timeStyle);
		CFRelease(locale);
	}
	return [(NSString *)CFDateFormatterCreateStringWithDate(kCFAllocatorDefault, f, (CFDateRef)self) autorelease];
}

@end

@implementation NSError(PGFoundationAdditions)

+ (id)PG_errorWithDomain:(NSString *)domain code:(NSInteger)code localizedDescription:(NSString *)desc userInfo:(NSDictionary *)dict
{
	NSMutableDictionary *const d = dict ? [[dict mutableCopy] autorelease] : [NSMutableDictionary dictionary];
	[d PG_setObject:desc forKey:NSLocalizedDescriptionKey];
	return [self errorWithDomain:domain code:code userInfo:d];
}

@end

@implementation NSMutableDictionary(PGFoundationAdditions)

- (void)PG_setObject:(id)obj forKey:(id)key
{
	if(obj) [self setObject:obj forKey:key];
}

@end

@implementation NSNumber(PGFoundationAdditions)

- (NSString *)PG_bytesAsLocalizedString
{
	static NSNumberFormatter *nf = nil;
	if(!nf) {
		nf = [[NSNumberFormatter alloc] init];
		[nf setFormatterBehavior:NSNumberFormatterBehavior10_4];
		[nf setNumberStyle:NSNumberFormatterDecimalStyle];
		[nf setUsesSignificantDigits:YES];
		[nf setMaximumSignificantDigits:3];
	}
	double b = [self doubleValue];
	NSUInteger magnitude = 0;
	for(; b >= 1000 && magnitude < 4; magnitude++) b /= 1000;
	NSString *unit = nil;
	switch(magnitude) {
		case 0: unit = NSLocalizedString(@"B" , @"Units (bytes, kilobytes, etc)."); break;
		case 1: unit = NSLocalizedString(@"KB", @"Units (bytes, kilobytes, etc)."); break;
		case 2: unit = NSLocalizedString(@"MB", @"Units (bytes, kilobytes, etc)."); break;
		case 3: unit = NSLocalizedString(@"GB", @"Units (bytes, kilobytes, etc)."); break;
		case 4: unit = NSLocalizedString(@"TB", @"Units (bytes, kilobytes, etc)."); break;
		default: PGAssertNotReached(@"Divided too far.");
	}
	return [NSString localizedStringWithFormat:@"%@ %@", [nf stringFromNumber:[NSNumber numberWithDouble:b]], unit];
}

@end

@implementation NSObject(PGFoundationAdditions)

#pragma mark Instance Methods

- (void)PG_postNotificationName:(NSString *)aName
{
	[self PG_postNotificationName:aName userInfo:nil];
}
- (void)PG_postNotificationName:(NSString *)aName userInfo:(NSDictionary *)aDict
{
	[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] postNotificationName:aName object:self userInfo:aDict];
}

#pragma mark -

- (void)PG_addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
{
	[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:observer selector:aSelector name:aName object:self];
}
- (void)PG_removeObserver
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)PG_removeObserver:(id)observer name:(NSString *)aName
{
	[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] removeObserver:observer name:aName object:self];
}

#pragma mark -

- (NSArray *)PG_asArray
{
	return [NSArray arrayWithObject:self];
}

#pragma mark -

+ (void *)PG_useInstance:(BOOL)instance implementationFromClass:(Class)class forSelector:(SEL)aSel
{
	if(!instance) self = objc_getMetaClass(class_getName(self));
	Method const newMethod = instance ? class_getInstanceMethod(class, aSel) : class_getClassMethod(class, aSel);
	if(!newMethod) return NULL;
	IMP const originalImplementation = class_getMethodImplementation(self, aSel); // Make sure the IMP we return is gotten using the normal method lookup mechanism.
	(void)class_replaceMethod(self, aSel, method_getImplementation(newMethod), method_getTypeEncoding(newMethod)); // If this specific class doesn't provide its own implementation of aSel--even if a superclass does--class_replaceMethod() adds the method without replacing anything and returns NULL. This behavior is good because it prevents our change from spreading to a superclass, but it means the return value is worthless.
	return originalImplementation;
}

#pragma mark NSMenuValidation Protocol

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	return [self respondsToSelector:[anItem action]];
}

@end

@implementation NSArray(AEArrayCreation)

- (NSArray *)PG_asArray
{
	return self;
}

@end

@interface NSProcessInfo(PGSnowLeopardOrLater)
- (void)enableSuddenTermination;
- (void)disableSuddenTermination;
@end

@implementation NSProcessInfo(PGFoundationAdditions)

- (void)PG_enableSuddenTermination
{
	if([self respondsToSelector:@selector(enableSuddenTermination)]) [self enableSuddenTermination];
}
- (void)PG_disableSuddenTermination
{
	if([self respondsToSelector:@selector(disableSuddenTermination)]) [self disableSuddenTermination];
}

@end

@implementation NSScanner(PGFoundationAdditions)

- (BOOL)PG_scanFromString:(NSString *)start toString:(NSString *)end intoString:(out NSString **)outString
{
	[self setScanLocation:0];
	[self scanUpToString:start intoString:NULL];
	if(![self scanString:start intoString:NULL]) return NO;
	return [self scanUpToString:end intoString:outString];
}

@end

@implementation NSString(PGFoundationAdditions)

#pragma mark -NSString(PGFoundationAdditions)

- (NSComparisonResult)PG_localizedCaseInsensitiveNumericCompare:(NSString *)aString
{
	static UniChar *str1 = NULL;
	static UniChar *str2 = NULL;
	static UniCharCount max1 = 0;
	static UniCharCount max2 = 0;
	UniCharCount const length1 = [self length], length2 = [aString length];
	if(!length1 && !length2) return NSOrderedSame;
	if(max1 < length1) {
		max1 = length1;
		str1 = str1 ? realloc(str1, max1 * sizeof(UniChar)) : malloc(max1 * sizeof(UniChar));
	}
	if(max2 < length2) {
		max2 = length2;
		str2 = str2 ? realloc(str2, max2 * sizeof(UniChar)) : malloc(max2 * sizeof(UniChar));
	}
	NSAssert(str1 && str2, @"Couldn't allocate.");
	[self getCharacters:str1];
	[aString getCharacters:str2];
	SInt32 result = NSOrderedSame;
	(void)UCCompareTextDefault(kUCCollateComposeInsensitiveMask | kUCCollateWidthInsensitiveMask | kUCCollateCaseInsensitiveMask | kUCCollateDigitsOverrideMask | kUCCollateDigitsAsNumberMask | kUCCollatePunctuationSignificantMask, str1, length1, str2, length2, NULL, &result);
	return (NSComparisonResult)result;
}
- (NSString *)PG_stringByReplacingOccurrencesOfCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replacement
{
	NSMutableString *const result = [NSMutableString string];
	NSScanner *const scanner = [NSScanner scannerWithString:self];
	[scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@""]];
	while(![scanner isAtEnd]) {
		NSString *substring = nil;
		if([scanner scanUpToCharactersFromSet:set intoString:&substring] && substring) [result appendString:substring];
		if([scanner scanCharactersFromSet:set intoString:NULL] && replacement) [result appendString:replacement];
	}
	return result;
}

#pragma mark -

- (NSString *)PG_firstPathComponent
{
	for(NSString *const component in [self pathComponents]) if(!PGEqualObjects(component, @"/")) return component;
	return @"";
}
- (NSURL *)PG_fileURL
{
	return [NSURL fileURLWithPath:self];
}
- (NSString *)PG_displayName
{
#if 1
	NSError* error = nil;
	NSString* name = nil;
	if(![[self PG_fileURL] getResourceValue:&name forKey:NSURLLocalizedNameKey error:&error] || nil != error || !name)
		return [NSFileManager.defaultManager displayNameAtPath:self];
	return name;
#else
	NSString *displayName = nil;
	if(LSCopyDisplayNameForURL((CFURLRef)[self PG_fileURL], (CFStringRef *)&displayName) == noErr && displayName)
		return [displayName autorelease];
	return [[NSFileManager defaultManager] displayNameAtPath:self];
#endif
}

#pragma mark -

- (NSArray *)PG_searchTerms
{
	NSArray *const components = [self componentsSeparatedByString:@" "];
	NSMutableArray *const terms = [NSMutableArray arrayWithCapacity:[components count]];
	for(NSString *const component in components) {
		if(![component length]) continue;
		NSScanner *const scanner = [NSScanner localizedScannerWithString:component];
		NSInteger index;
		if([scanner scanInteger:&index] && [scanner isAtEnd] && index != NSIntegerMax && index != NSIntegerMin) [terms addObject:[NSNumber numberWithInteger:index]];
		else [terms addObject:component];
	}
	return terms;
}
- (BOOL)PG_matchesSearchTerms:(NSArray *)terms
{
	NSScanner *const scanner = [NSScanner localizedScannerWithString:self];
	[scanner setCharactersToBeSkipped:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
	for(id const term in terms) {
		if([term isKindOfClass:[NSNumber class]]) {
			[scanner setScanLocation:0];
			BOOL foundNumber = NO;
			while(!foundNumber && ![scanner isAtEnd]) {
				NSInteger index;
				if(![scanner scanInteger:&index]) return NO;
				if([term integerValue] == index) foundNumber = YES;
			}
			if(!foundNumber) return NO;
		} else {
			if([self rangeOfString:term options:NSCaseInsensitiveSearch].location == NSNotFound) return NO;
		}
	}
	return YES;
}

@end

@implementation NSURL(PGFoundationAdditions)

#pragma mark Class Methods

+ (NSURL *)PG_URLWithString:(NSString *)aString
{
	NSMutableString *const URL = [NSMutableString string];
	NSScanner *const scanner = [NSScanner scannerWithString:aString];
	[scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"\n\r\t"]];
	NSString *scheme = nil;
	if(![scanner scanUpToString:@"://" intoString:&scheme]) return nil;
	if([scanner isAtEnd]) {
		[scanner setScanLocation:0];
		scheme = [scanner scanString:@"/" intoString:NULL] || [scanner scanString:@"~" intoString:NULL] ? @"file" : @"http";
		[scanner setScanLocation:0];
	} else {
		NSMutableCharacterSet *const schemeCharacters = [[[NSCharacterSet letterCharacterSet] mutableCopy] autorelease];
		[schemeCharacters addCharactersInString:@"+-."];
		if([scheme rangeOfCharacterFromSet:[schemeCharacters invertedSet]].location != NSNotFound) return nil;
		[scanner scanString:@"://" intoString:NULL];
	}
	[URL appendFormat:@"%@://", scheme];

	NSUInteger const schemeEnd = [scanner scanLocation];
	NSString *login = nil;
	[scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@/"] intoString:&login];
	if([scanner scanString:@"@" intoString:NULL]) [URL appendFormat:@"%@@", login];
	else [scanner setScanLocation:schemeEnd];

	NSString *host = @"";
	if(![scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@":/"] intoString:&host]) {
		if(!PGEqualObjects(scheme, @"file") || [scanner isAtEnd]) return nil;
	} else if(PGEqualObjects(host, @"~")) {
		host = NSHomeDirectory();
	} else if(!PGEqualObjects(host, @"localhost")) {
		NSCharacterSet *const subdomainDelimitingCharacters = [NSCharacterSet characterSetWithCharactersInString:@".-"];
		NSScanner *const hostScanner = [NSScanner scannerWithString:host];
		do {
			NSString *subdomain = nil;
			[hostScanner scanUpToCharactersFromSet:subdomainDelimitingCharacters intoString:&subdomain];
			if(![subdomain length] || [subdomain hasPrefix:@"-"] || [subdomain hasSuffix:@"-"]) return nil;
			if([subdomain rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) return nil;
		} while([hostScanner scanString:@"." intoString:NULL] || [hostScanner scanString:@"-" intoString:NULL]);
		if([host rangeOfString:@"."].location == NSNotFound) host = [NSString stringWithFormat:@"www.%@.com", host];
	}
	[URL appendString:host];

	if([scanner scanString:@":" intoString:NULL]) {
		if(PGEqualObjects(scheme, @"file")) return nil;
		NSInteger port;
		if(![scanner scanInteger:&port]) return nil;
		[URL appendFormat:@":%ld", (long)port];
	}

	NSMutableString *const path = [NSMutableString string];
	[scanner scanString:@"/" intoString:NULL];
	[path appendString:@"/"];
	if(PGEqualObjects(scheme, @"file")) {
		while(![scanner isAtEnd]) {
			NSString *pathSegment = nil;
			if([scanner scanUpToString:@"/" intoString:&pathSegment]) [path appendString:pathSegment];
			if([scanner scanString:@"/" intoString:NULL]) {
				if(![pathSegment length]) return nil;
				[path appendString:@"/"];
			}
		}
	} else {
		NSCharacterSet *const hexCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
		NSMutableData *const hexData = [NSMutableData data];
		while(YES) {
			NSString *pathPart;
			if([scanner scanUpToString:@"%" intoString:&pathPart]) {
				[hexData setLength:0];
				[path appendString:pathPart];
			}
			if(![scanner scanString:@"%" intoString:NULL]) break;
			NSUInteger const percentLoc = [scanner scanLocation];
			NSString *hex = nil;
			if(![scanner scanCharactersFromSet:hexCharacterSet intoString:&hex] || [hex length] < 2) {
				[hexData setLength:0];
				[scanner setScanLocation:percentLoc];
				[path appendString:@"%"];
				continue;
			}
			[scanner setScanLocation:percentLoc + 2];
			NSScanner *const hexScanner = [NSScanner scannerWithString:[hex substringToIndex:2]];
			unsigned character;
			if([hexScanner scanHexInt:&character]) {
				[hexData appendBytes:&character length:1];
				NSString *const hexEncodedString = [[[NSString alloc] initWithData:hexData encoding:NSUTF8StringEncoding] autorelease];
				if(hexEncodedString) {
					[path appendString:hexEncodedString];
					[hexData setLength:0];
				}
			}
		}
	}
#if 1
	//	- (nullable NSString *)stringByAddingPercentEscapesUsingEncoding:(NSStringEncoding)enc API_DEPRECATED("Use -stringByAddingPercentEncodingWithAllowedCharacters: instead, which always uses the recommended UTF-8 encoding, and which encodes for a specific URL component or subcomponent since each URL component or subcomponent has different rules for what characters are valid.");
	[URL appendString:path];
	return [self URLWithString:[URL stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];
#else
	return [self URLWithString:[URL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
#endif
}

#pragma mark Instance Methods

- (NSImage *)PG_icon
{
	if(![self isFileURL]) return [NSImage imageNamed:@"URL"];
	NSImage *const icon = [[NSWorkspace sharedWorkspace] iconForFile:[self path]];
//	[icon setDataRetained:YES];
	return icon;
}

@end

@implementation NSUserDefaults(PGFoundationAdditions)

#pragma mark Instance Methods

#if 1
- (id)PG_decodeObjectOfClass:(Class)class forKey:(NSString *)defaultName {
	NSData *const data = [self dataForKey:defaultName];
	if(!data)
		return nil;

	NSError* error = nil;
	id decodedObj = [NSKeyedUnarchiver unarchivedObjectOfClass:class fromData:data error:&error];
	if(nil == decodedObj)
		NSLog(@"in [NSUserDefaults PG_decodeObjectOfClass:forKey:%@, [NSKeyedUnarchiver unarchivedObjectOfClass:%@ fromData:%@] ==> error %@",
				defaultName, NSStringFromClass(class), [data description], [error description]);

	return decodedObj;
}
#else
- (id)PG_decodedObjectForKey:(NSString *)defaultName
{
	NSData *const data = [self dataForKey:defaultName];
	return (data ? [NSUnarchiver unarchiveObjectWithData:data] : nil);
}
#endif

- (void)PG_encodeObject:(id)value forKey:(NSString *)defaultName
{
//	[self setObject:value ? [NSArchiver archivedDataWithRootObject:value] : nil forKey:defaultName];
	if(!value)
		[self setObject:nil forKey:defaultName];
	else {
		NSError* error = nil;
		[self setObject:[NSKeyedArchiver archivedDataWithRootObject:value requiringSecureCoding:YES error:&error]
				 forKey:defaultName];
	}
}

@end
