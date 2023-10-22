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
#pragma clang diagnostic push
	//	recent XADMaster sources have EOF and sign comparison issues
	//	just disable the warnings
	#pragma clang diagnostic ignored "-Wnewline-eof"
	#pragma clang diagnostic ignored "-Wsign-compare"
	#import "PGArchiveAdapter.h"
#pragma clang diagnostic pop

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGResourceIdentifier.h"
#import "PGDataProvider.h"

// Controllers
#import "PGDocumentController.h"

// Other Sources
#import "PGFoundationAdditions.h"

@interface PGDataProvider(PGArchiveDataProvider)

- (XADArchive *)archive;
- (int)entry;

@end

@interface PGArchiveDataProvider : PGDataProvider
{
	@private
	XADArchive *_archive;
	int _entry;

	//	The use of @synchronized(_archive) causes contention
	//	between all threads attempting to use _archive; when
	//	the main thread is attempting to draw thumbnails, this
	//	contention blocks the main thread by preventing the
	//	access to the icon (typeCode and extension) and data
	//	size (dataByteSize) values; to avoid this contention,
	//	these small metadata values are cached.
	OSType _typeCode;
	NSString *_extension;
	uint64_t _dataByteSize;
}

- (id)initWithArchive:(XADArchive *)archive entry:(int)entry;

@end

@interface PGArchiveFolderDataProvider : PGDataProvider

@end

@interface PGArchiveAdapter(Private)

- (void)_threaded_setError:(NSError *)error forNode:(PGNode *)node;
- (void)_updateThumbnailsOfChildren;

@end

static
BOOL
PG_entryIsInvisibleForName(NSString* name) {
	return [name characterAtIndex:0] == '.' ||
			NSNotFound != [name rangeOfString:@"/."].location;
}

@interface XADArchive(PGAdditions)

//- (BOOL)PG_entryIsInvisibleForName:(NSString *)name;
- (NSString *)PG_commonRootPath;
- (OSType)PG_OSTypeForEntry:(int)entry;

@end

/* static
NSString*
StringAtDepth(NSInteger depth) {
	return [@"\t\t\t\t\t" substringToIndex:depth];
} */

#pragma mark -

@implementation PGArchiveAdapter

//	returns an array containing the child nodes which represent all objects
//	that are direct children of the given path
- (NSArray *)nodesUnderPath:(NSString *)path
			  parentAdapter:(PGContainerAdapter *)parent
		   remainingIndexes:(NSMutableIndexSet *)indexes
//					  depth:(NSInteger)depth	for debugging only
{
	NSParameterAssert(path);
	NSParameterAssert(parent);
	NSParameterAssert(_archive);
	NSMutableArray *const children = [NSMutableArray array];
	NSUInteger i = [indexes firstIndex];
	for(; NSNotFound != i; i = [indexes indexGreaterThanIndex:i]) {
		@autoreleasepool {	//	REQUIRED otherwise the heap blows up (try it on a 50000 entry zip file)
			NSString *const entryPath = [_archive nameOfEntry:(int) i];
			if(!entryPath)
				continue;

#if 1
			if(PG_entryIsInvisibleForName(entryPath))
				continue;
			if(path.length) {
				if(![entryPath hasPrefix:path])
					continue;
				
/*NSLog(@"%@comparing path[%lu] '%@' vs entryPath[%lu] '%@' --> %s",
	  StringAtDepth(depth),
	  path.length, [path substringFromIndex:194],
	  entryPath.length, [entryPath substringFromIndex:194],
	  path.length == entryPath.length ||
		  [entryPath characterAtIndex:path.length] != '/' ? "rej" : "acc");*/

				//	The entry in the archive for this parent-path
				//	should be removed to prevent the creation of
				//	duplicate nodes in the parent's node for this
				//	directory.
				//	Example: in archive /path/a.zip, the first entry
				//	is b/c.jpg and an entry for the directory b
				//	occurs later in the archive.
				//	When b/c.jpg is encountered, a node for 'b' is
				//	created and this fn is entered again (recursion)
				//	to get b's children. During this recursion for
				//	path 'b', the entry for the directory itself is
				//	removed from the indexes by this 'if' block, and
				//	no further processing of the entry for 'b' is done
				//	because its node will already exist (done by caller).
				//	If the b/c.jpg entry does not exist and in fact the
				//	directory has no child objects then this recursion
				//	to process b will only occur when b itself is
				//	encountered during its parent loop of the entries
				//	in the archive and the caller will remove b's entry
				//	from the indexes (it is never encountered during
				//	its recursion for b's children because there are no
				//	children).
				if(path.length == entryPath.length) {	//	special case
					[indexes removeIndex:i];
					continue;
				}

				//	when path is "/path/to/abc" and entryPath is "/path/to/abc.txt",
				//	abc.txt is NOT a node under path and must be ignored; the
				//	original code below does not test for this so it ended up
				//	processing ".txt" as a child node :(
				if([entryPath characterAtIndex:path.length] != '/')
					continue;
			}

			//	from here on, entryPath is definitely a node under path so it
			//	is now safe to remove index i from the index set (original
			//	code incorrectly removed entries first and then rejected them)
			[indexes removeIndex:i];
			NSString *const subpath = [path stringByAppendingPathComponent:
				[[entryPath substringFromIndex:path.length] PG_firstPathComponent]];
#else	//	original code:
			if([path length] && ![entryPath hasPrefix:path])
				continue;
			if([_archive PG_entryIsInvisibleForName:entryPath])
				continue;

			[indexes removeIndex:i];
			NSString *const subpath = [path stringByAppendingPathComponent:[[entryPath substringFromIndex:path.length] PG_firstPathComponent]];
			if(PGEqualObjects(path, entryPath))
				continue;
#endif

			BOOL const isEntrylessFolder = !PGEqualObjects(subpath, entryPath);
			BOOL const isFile = !isEntrylessFolder && ![_archive entryIsDirectory:(int) i];
//NSLog(@"%@\tsubpath '%@', isEntrylessFolder %u, isFile %u", StringAtDepth(depth),
//	  [subpath substringFromIndex:194], isEntrylessFolder, isFile);

			PGDisplayableIdentifier *const identifier =
				[[self.node.identifier subidentifierWithIndex:isEntrylessFolder ? NSNotFound : i] displayableIdentifier];
			[identifier setNaturalDisplayName:[subpath lastPathComponent]];
			PGNode *const node = [[[PGNode alloc] initWithParent:parent identifier:identifier] autorelease];
			if(isFile)
				[node setDataProvider:[[[PGArchiveDataProvider alloc] initWithArchive:_archive entry:(int) i] autorelease]];
			else {
				[node setDataProvider:[[[PGArchiveFolderDataProvider alloc] init] autorelease]];
				if(isEntrylessFolder) {
//NSLog(@"subpath '%@' entryPath '%@' isEntrylessFolder %u", subpath, entryPath, isEntrylessFolder);
//NSLog(@"isEntrylessFolder so adding index %lu backinto indexes", i);
					[indexes addIndex:i]; // We ended up taking care of a folder in its path instead.
				}
				PGContainerAdapter *const adapter = (PGContainerAdapter *)[node resourceAdapter];
//NSLog(@"%@\t>>> entering recursion to get children of subpath >>>", StringAtDepth(depth));
				[adapter setUnsortedChildren:[self nodesUnderPath:subpath
													parentAdapter:adapter
												 remainingIndexes:indexes]
				//											depth:depth+1]	for debugging only
							  presortedOrder:PGUnsorted];
//NSLog(@"%@\t<<< exiting recursion to get children of subpath <<<", StringAtDepth(depth));
			}
		//	[identifier setIcon:[[[node resourceAdapter] dataProvider] icon]];
			[identifier setIcon:[node.resourceAdapter.dataProvider icon]];
			if(node) {
//NSLog(@"%@\tpath '%@' is getting child @ subpath '%@'", StringAtDepth(depth),
//[path substringFromIndex:194], [subpath substringFromIndex:194]);
				[children addObject:node];
			}
		}	//	@autoreleasepool
	}	//	for
	return children;
}

/* for debugging only
- (NSArray *)nodesUnderPath:(NSString *)path
			  parentAdapter:(PGContainerAdapter *)parent
		   remainingIndexes:(NSMutableIndexSet *)indexes {
	return [self nodesUnderPath:path parentAdapter:parent remainingIndexes:indexes depth:0];
} */


#pragma mark -PGArchiveAdapter(Private)

- (void)_threaded_setError:(NSError *)error forNode:(PGNode *)node;
{
	// TODO: Figure this out...
//	[node performSelectorOnMainThread:@selector(setError:) withObject:error waitUntilDone:YES];
}
- (void)_updateThumbnailsOfChildren
{
	[[self document] noteNodeThumbnailDidChange:[self node] recursively:YES];
}

#pragma mark -PGContainerAdapter

- (PGRecursionPolicy)descendantRecursionPolicy
{
	return PGRecurseToAnyDepth;
}

#pragma mark -PGResourceAdapter

- (BOOL)canSaveData
{
	return YES;
}

#pragma mark -

- (void)load
{
	if(!_archive) {
		XADError error = XADNoError;
		PGDataProvider *const dataProvider = [self dataProvider];
		PGResourceIdentifier *const ident = [dataProvider identifier];
		if([dataProvider archive]) @synchronized([dataProvider archive]) {
			_archive = [[XADArchive alloc] initWithArchive:[dataProvider archive]
													 entry:[dataProvider entry]
												  delegate:self
													 error:&error];
		} else if([ident isFileIdentifier])
			_archive = [[XADArchive alloc] initWithFile:ident.URL.path
											   delegate:self
												  error:&error]; // -data will return data for file URLs, but it's worth using -[XADArchive initWithFile:...].
		else {
			NSData *const data = [self data];
			if(data)
				_archive = [[XADArchive alloc] initWithData:data
												   delegate:self
													  error:&error];
		}
		if(!_archive || error != XADNoError || [_archive isCorrupted])
			return [[self node] fallbackFromFailedAdapter:self]; // TODO: Return an appropriate error.
	}
	NSMutableIndexSet* indexSet = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _archive.numberOfEntries)];
	NSArray *const children = [self nodesUnderPath:[_archive PG_commonRootPath]
									 parentAdapter:self
								  remainingIndexes:indexSet];
	[self setUnsortedChildren:children presortedOrder:PGUnsorted];
	[[self node] loadFinishedForAdapter:self];
}

#pragma mark -NSObject

- (void)dealloc
{
	@synchronized(_archive) {
		[_archive release];
		_archive = nil;
	}
	[super dealloc];
}

#pragma mark -NSObject(XADArchiveDelegate)

- (void)archiveNeedsPassword:(XADArchive *)archive
{
	_needsPassword = YES;
	[self _threaded_setError:[NSError errorWithDomain:PGNodeErrorDomain code:PGPasswordError userInfo:nil] forNode:_currentSubnode];
}
-(NSStringEncoding)archive:(XADArchive *)archive encodingForData:(NSData *)data guess:(NSStringEncoding)guess confidence:(float)confidence
{
	return guess;
}

//#pragma mark -<PGNodeDataSource>
//
//- (NSDictionary *)fileAttributesForNode:(PGNode *)node
//{
//	NSUInteger const i = [[node identifier] index];
//	if(NSNotFound == i) return nil;
//	NSMutableDictionary *const attributes = [NSMutableDictionary dictionary];
//	[attributes PG_setObject:[[_archive attributesOfEntry:i] objectForKey:XADCreationDateKey] forKey:NSFileCreationDate];
//	if(![_archive entryIsDirectory:i]) [attributes setObject:[NSNumber numberWithUnsignedLongLong:[_archive representativeSizeOfEntry:i]] forKey:NSFileSize];
//	return attributes;
//}
//- (void)node:(PGNode *)sender willLoadWithInfo:(NSMutableDictionary *)info
//{
//	NSUInteger const i = [[sender identifier] index];
//	if(NSNotFound == i) return;
//	if([_archive entryIsArchive:i]) [info setObject:[NSNumber numberWithBool:YES] forKey:PGKnownToBeArchiveKey];
//	if(![info objectForKey:PGOSTypeKey]) [info PG_setObject:[_archive PG_OSTypeForEntry:i standardFormat:NO] forKey:PGOSTypeKey];
//	if(![info objectForKey:PGExtensionKey]) [info PG_setObject:[[_archive nameOfEntry:i] pathExtension] forKey:PGExtensionKey];
//}
//- (BOOL)node:(PGNode *)sender getData:(out NSData **)outData info:(NSDictionary *)info fast:(BOOL)flag
//{
//	NSUInteger const i = [[sender identifier] index];
//	if(NSNotFound == i || flag || [_archive entryIsDirectory:i]) {
//		if(outData) *outData = nil;
//		return YES;
//	}
//	NSData *data = nil;
//	@synchronized(_archive) {
//		NSString *const pass = [info objectForKey:PGPasswordKey];
//		if(pass) [_archive setPassword:pass];
//		BOOL const neededPassword = _needsPassword;
//		_needsPassword = NO;
//		_currentSubnode = sender;
//		[_archive clearLastError];
//		data = [_archive contentsOfEntry:i];
//		switch([_archive lastError]) {
//			case XADNoError:
//			case XADPasswordError: 
//				if(!_needsPassword) [self archiveNeedsPassword:_archive];
//				break;
//			default:
//				[self _threaded_setError:[NSError PG_errorWithDomain:PGNodeErrorDomain code:PGGenericError localizedDescription:[NSString stringWithFormat:NSLocalizedString(@"The error “%@” occurred while parsing the archive.", @"XADMaster error reporting. %@ is replaced with the XADMaster error."), [_archive describeLastError]] userInfo:nil] forNode:_currentSubnode];
//				break;
//		}
//		_currentSubnode = nil;
//		if(neededPassword && !_needsPassword) [[PGArchiveAdapter PG_performOn:self allowOnce:YES withStorage:PGArchiveAdapterList] performSelectorOnMainThread:@selector(_updateThumbnailsOfChildren) withObject:nil waitUntilDone:NO];
//	}
//	if(outData) *outData = data;
//	return YES;
//}

@end

#pragma mark -

@implementation PGDataProvider(PGArchiveDataProvider)

- (XADArchive *)archive
{
	return nil;
}
- (int)entry
{
	return 0;	//	2023/09/10 this should probably be -1 because 0 is a valid entry index
}

@end

#pragma mark -

@implementation PGArchiveDataProvider

- (id)initWithArchive:(XADArchive *)archive entry:(int)entry;
{
	if((self = [super init])) {
		NSParameterAssert(nil != archive);
		_archive = [archive retain];
		_entry = entry;

		_typeCode = [archive PG_OSTypeForEntry:entry];
		_extension = [[[[archive nameOfEntry:entry] pathExtension] lowercaseString] retain];
		{
			off_t const value = [archive representativeSizeOfEntry:entry];
			NSParameterAssert(value >= 0);	//	the following cast should be safe
			_dataByteSize = (uint64_t) value;	//	cast signed 64-bit int to unsigned 64-bit int
		}
	}
	return self;
}

#pragma mark PGDataProvider

- (NSData *)data
{
//NSLog(@"PGArchiveDataProvider -data for entry %d", _entry);
	@synchronized(_archive) {
		return [_archive contentsOfEntry:_entry]; // TODO: Handle password issues.
	}
	return nil;
}
- (uint64_t)dataByteSize
{
	return _dataByteSize;
/*	@synchronized(_archive) {
		off_t const value = [_archive representativeSizeOfEntry:_entry];
		NSParameterAssert(value >= 0);	//	the following cast should be safe
		return (uint64_t) value;	//	cast signed 64-bit int to unsigned 64-bit int
	}
	return 0;	*/
}
- (NSDate *)dateModified
{	//	2023/09/17 added to implement sorting by date modified in archives
	@synchronized(_archive) {
		return [[_archive attributesOfEntry:_entry] objectForKey:NSFileModificationDate];
	}
	return nil;
}
- (NSDate *)dateCreated
{
	@synchronized(_archive) {
		//	2023/09/18 bugfix: was using XADCreationDateKey instead of NSFileCreationDate
		return [[_archive attributesOfEntry:_entry] objectForKey:NSFileCreationDate];
	}
	return nil;
}

#pragma mark -

- (OSType)typeCode
{
	return _typeCode;
/*	@synchronized(_archive) {
		return [_archive PG_OSTypeForEntry:_entry];
	}
	return 0;	*/
}
- (NSString *)extension
{
	return _extension;
/*	@synchronized(_archive) {
		return [[[_archive nameOfEntry:_entry] pathExtension] lowercaseString];
	}
	return nil;	*/
}

#pragma mark -

- (BOOL)hasData
{
	//	2023/09/10 [PGDataProvider hasData] invokes [self data] which is
	//	time-expensive when dealing with zip archives (and creates objects
	//	that have no purpose and will just get reclaimed by the autorelease
	//	pool). However, assuming that this instance is created to model an
	//	archive entry, then it should have data so avoid the need to create
	//	a NSData instance and just return YES.
	//	TODO: is it always correct to return true? Are there times when it should be NO?
	return YES;
}

- (NSData *)fourCCData
{
	return nil; // Too slow.
}
/* - (NSNumber *)dataLength
{	2023/09/17 deprecated
	@synchronized(_archive) {
		return [NSNumber numberWithLongLong:[_archive representativeSizeOfEntry:_entry]];
	}
	return nil;
} */

#pragma mark PGDataProvider(PGArchiveDataProvider)

- (XADArchive *)archive
{
	return _archive;
}
- (int)entry
{
	return _entry;
}

#pragma mark PGDataProvider(PGResourceAdapterLoading)

- (NSArray *)adapterClassesForNode:(PGNode *)node
{
	@synchronized(_archive) {
		if([_archive entryIsArchive:_entry]) return [NSArray arrayWithObject:[PGArchiveAdapter class]];
	}
	return [super adapterClassesForNode:node];
}

#pragma mark NSObject

- (void)dealloc
{
	[_extension release];
	[_archive release];
	[super dealloc];
}

@end

#pragma mark -
@implementation PGArchiveFolderDataProvider

#pragma mark PGDataProvider

- (OSType)typeCode
{
	return 'fold';
}

#pragma mark -PGDataProvider(PGResourceAdapterLoading)

- (NSArray *)adapterClassesForNode:(PGNode *)node
{
	return [NSArray arrayWithObject:[PGContainerAdapter class]];
}

@end

#pragma mark -

@implementation XADArchive(PGAdditions)

#if 0
//	parameter 'name' is actually a filesystem object's path
- (BOOL)PG_entryIsInvisibleForName:(NSString *)name
{
	if([name hasPrefix:@"."]) return YES;
	if(NSNotFound != [name rangeOfString:@"/."].location) return YES;
	return NO;
}
#endif

- (NSString *)PG_commonRootPath
{
	NSInteger i;
	NSString *root = nil;
	for(i = 0; i < [self numberOfEntries]; i++) {
		NSString *entryName = [self nameOfEntry:(int) i];
		if(PG_entryIsInvisibleForName(entryName))//if([self PG_entryIsInvisibleForName:entryName])
			continue;
		if(![self entryIsDirectory:(int) i]) entryName = [entryName stringByDeletingLastPathComponent];
		else if([entryName hasSuffix:@"/"]) entryName = [entryName substringToIndex:[entryName length] - 1];
		if(!root) root = entryName;
		else while(!PGEqualObjects(root, entryName)) {
			if([root length] > [entryName length]) root = [root stringByDeletingLastPathComponent];
			else entryName = [entryName stringByDeletingLastPathComponent];
		}
	}
	return root ? root : @"";
}
- (OSType)PG_OSTypeForEntry:(int)entry
{
	return [self entryIsDirectory:entry] ? 'fold' : [[[self attributesOfEntry:entry] objectForKey:NSFileHFSTypeCode] unsignedIntValue];
}

@end
