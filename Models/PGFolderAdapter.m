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
#import "PGFolderAdapter.h"
#import <sys/event.h>

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGResourceIdentifier.h"
#import "PGDataProvider.h"

// Other Sources
#import "PGFoundationAdditions.h"

static NSArray *PGIgnoredPaths = nil;

@implementation PGFolderAdapter

#pragma mark +NSObject

+ (void)initialize
{
	if([PGFolderAdapter class] != self) return;
	PGIgnoredPaths = [[NSArray alloc] initWithObjects:@"/net", @"/etc", @"/home", @"/tmp", @"/var", @"/mach_kernel.ctfsys", @"/mach.sym", nil];
}

#pragma mark -PGFolderAdapter

static
BOOL
IsPackage(NSURL* URL) {
#if 1
	id value = nil;
	NSError* error = nil;
	BOOL b = [URL getResourceValue:&value forKey:NSURLIsPackageKey error:&error];
	return b ? ![value isEqual:@NO] : YES;
//	return [URL getResourceValue:&value forKey:NSURLIsPackageKey error:&error] && ![value isEqual:@NO];
#else
	LSItemInfoRecord info;
	return LSCopyItemInfoForURL((CFURLRef)URL, kLSRequestBasicFlagsOnly, &info) == noErr &&
			0 != (info.flags & kLSItemInfoIsPackage);
#endif
}

static
bool
IsVisibleInFinder(NSURL* pageURL) {
#if 1
	id value = nil;
	NSError* error = nil;
	BOOL b = [pageURL getResourceValue:&value forKey:NSURLIsHiddenKey error:&error];
	return b ? [value isEqual:@NO] : NO;
//	return [pageURL getResourceValue:&value forKey:NSURLIsHiddenKey error:&error] && [value isEqual:NO];
#else
	LSItemInfoRecord info;
	return LSCopyItemInfoForURL((CFURLRef)pageURL, kLSRequestBasicFlagsOnly, &info) == noErr &&
			0 != (info.flags & kLSItemInfoIsInvisible);
#endif
}

- (void)createChildren
{
	NSURL *const URL = [[(PGDataProvider *)[self dataProvider] identifier] URLByFollowingAliases:YES];
#if 1	//	2021/07/21
	if (IsPackage(URL))
		return;
#else
	LSItemInfoRecord info;
	if(LSCopyItemInfoForURL((CFURLRef)URL, kLSRequestBasicFlagsOnly, &info) != noErr || info.flags & kLSItemInfoIsPackage) return;
#endif

	[[self document] setProcessingNodes:YES];
	NSMutableArray *const oldPages = [[[self unsortedChildren] mutableCopy] autorelease];
	NSMutableArray *const newPages = [NSMutableArray array];
	NSString *const path = [URL path];
	for(NSString *const pathComponent in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL]) {
		NSString *const pagePath = [path stringByAppendingPathComponent:pathComponent];
		if([PGIgnoredPaths containsObject:pagePath]) continue;
		NSURL *const pageURL = [pagePath PG_fileURL];
#if 1	//	2021/07/21
		if (!IsVisibleInFinder(pageURL))
			continue;
#else
		if(LSCopyItemInfoForURL((CFURLRef)pageURL, kLSRequestBasicFlagsOnly, &info) != noErr || info.flags & kLSItemInfoIsInvisible) continue;
#endif
		PGDisplayableIdentifier *const pageIdent = [pageURL PG_displayableIdentifier];
		PGNode *node = [self childForIdentifier:pageIdent];
		if(node) {
			[oldPages removeObjectIdenticalTo:node];
			[node noteFileEventDidOccurDirect:NO];
		} else {
			node = [[[PGNode alloc] initWithParent:self identifier:pageIdent] autorelease];
			[node setDataProvider:[PGDataProvider providerWithResourceIdentifier:pageIdent]];
		}
		if(node) [newPages addObject:node];
	}
	[self setUnsortedChildren:newPages presortedOrder:PGUnsorted];
	[[self document] setProcessingNodes:NO];
}

#pragma mark -PGResourceAdapter

- (void)load
{
	[self createChildren];
	[[self node] loadFinishedForAdapter:self];
}

#pragma mark -<PGResourceAdapting>

- (void)noteFileEventDidOccurDirect:(BOOL)flag
{
	if(![[(PGDataProvider *)[self dataProvider] identifier] hasTarget]) [[self node] removeFromDocument];
	else if(flag) [self createChildren];
}

@end
