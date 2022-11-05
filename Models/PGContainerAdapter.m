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
#import "PGContainerAdapter.h"

// Models
#import "PGDocument.h"
#import "PGNode.h"
#import "PGResourceIdentifier.h"

// Other Sources
#import "PGFoundationAdditions.h"

/*
static
NSUInteger
Pack2HalfUInts(NSUInteger upper, NSUInteger lower) // folderAndImageCount
{
	enum : NSUInteger { HALF_UINT_BIT_SHIFT_COUNT = sizeof(NSUInteger) * 8u / 2u };
	assert(upper < ((NSUInteger) 1u << HALF_UINT_BIT_SHIFT_COUNT));
	upper	<<=	HALF_UINT_BIT_SHIFT_COUNT;
	assert(lower < ((NSUInteger) 1u << HALF_UINT_BIT_SHIFT_COUNT));
	upper	|=	lower;
	return upper;
}
 */

static
uint64_t
Pack_ByteSize_FolderImageCounts(uint64_t byteSize, NSUInteger folders, NSUInteger images) // folderAndImageCount
{
	//	if more bits are needed, use alternate format:
	//	bits 63: flag: 0 = byte size, 1 = folder count
	//	bits 62-32: <byte size> or <folder count> (meaning depends on bit 63)
	//	bits 31-00: <image count>

	static_assert(sizeof(byteSize) >= sizeof(folders), "");
	static_assert(sizeof(byteSize) >= sizeof(images), "");
	enum : NSUInteger { BYTE_SIZE_BIT_COUNT = 36, FOLDER_BIT_COUNT = 10, IMAGE_BIT_COUNT = 18 };
	assert(byteSize < (1ull << BYTE_SIZE_BIT_COUNT));	//	36 bits: 64G = 68,719,476,736
	assert(folders  < (1ull << FOLDER_BIT_COUNT));		//	10 bits: 1k = 1024
	assert(images   < (1ull << IMAGE_BIT_COUNT));		//	18 bits: 256k = 262144
	if(byteSize >= (1ull << BYTE_SIZE_BIT_COUNT) ||
	   folders  >= (1ull << FOLDER_BIT_COUNT) ||
	   images   >= (1ull << IMAGE_BIT_COUNT))
		return 0;

	//	policy: bits 17-00: image count
	//	policy: bits 27-18: folder count
	//	policy: bits 63-28: byte size
	byteSize	<<=	FOLDER_BIT_COUNT + IMAGE_BIT_COUNT;
	uint64_t	tmp	=	folders;	//	on non-64-bit targets, this performs uint expansion
	static_assert(sizeof(tmp) == sizeof(byteSize), "");
	tmp			<<=	IMAGE_BIT_COUNT;
	byteSize	|=	tmp;
	byteSize	|=	images;
	return byteSize;
}

/*
extern	void	Unpack2HalfUInts(NSUInteger packed, NSUInteger* upper, NSUInteger* lower);

//	extern
void
Unpack2HalfUInts(NSUInteger packed, NSUInteger* upper, NSUInteger* lower)
{
	enum : NSUInteger { HALF_UINT_BIT_SHIFT_COUNT = sizeof(NSUInteger) * 8u / 2u };
	enum : NSUInteger { HALF_UINT_MASK = ((NSUInteger) 1u << HALF_UINT_BIT_SHIFT_COUNT) - (NSUInteger) 1u };
	*lower	=	packed & HALF_UINT_MASK;
	*upper	=	packed >> HALF_UINT_BIT_SHIFT_COUNT;
}
 */

extern	void	Unpack_ByteSize_FolderImageCounts(uint64_t packed, uint64_t* byteSize,
												  NSUInteger* folders, NSUInteger* images);

//	extern
void
Unpack_ByteSize_FolderImageCounts(uint64_t packed, uint64_t* byteSize,
								  NSUInteger* folders, NSUInteger* images)
{
	//	if more bits are needed, use alternate format:
	//	bits 63: flag: 0 = byte size, 1 = folder count
	//	bits 62-32: <byte size> or <folder count> (meaning depends on bit 63)
	//	bits 31-00: <image count>

	static_assert(sizeof(byteSize) >= sizeof(folders), "");
	static_assert(sizeof(byteSize) >= sizeof(images), "");
	enum : NSUInteger { BYTE_SIZE_BIT_COUNT = 36, FOLDER_BIT_COUNT = 10, IMAGE_BIT_COUNT = 18 };

	uint64_t	tmp	=	packed;
//	tmp	>>=	0;	not needed for bottom most bits
	tmp	&=	(1ull << IMAGE_BIT_COUNT)-1u;
	*images		=	(NSUInteger) tmp;

	tmp	=	packed;
	tmp	>>=	IMAGE_BIT_COUNT;
	tmp	&=	(1ull << FOLDER_BIT_COUNT)-1u;
	*folders	=	(NSUInteger) tmp;

	tmp	=	packed;
	tmp	>>=	FOLDER_BIT_COUNT + IMAGE_BIT_COUNT;
//	tmp	&=	(1ull << BYTE_SIZE_BIT_COUNT)-1u;	not needed for top most bits
	*byteSize	=	tmp;
}

#pragma mark -

NSString *const PGMaxDepthKey = @"PGMaxDepth";

@interface PGContainerAdapter(Private)

- (PGNode *)_nodeForSelectorOrSelfIfViewable:(SEL)sel forward:(BOOL)flag;

@end

@implementation PGContainerAdapter

#pragma mark -PGContainerAdapter

- (PGRecursionPolicy)descendantRecursionPolicy
{
	return [self recursionPolicy];
}

#pragma mark -

- (NSArray<PGNode*> *)sortedChildren
{
	if(!_sortedChildren) {
		PGSortOrder const order = [[self document] sortOrder];
		PGSortOrder const maskedUnsortedOrder = PGSortOrderMask & _unsortedOrder;
		if((PGSortOrderMask & order) == maskedUnsortedOrder || PGSortInnateOrder == maskedUnsortedOrder) {
			if((PGSortDescendingMask & order) == (PGSortDescendingMask & _unsortedOrder)) _sortedChildren = [_unsortedChildren retain];
			else _sortedChildren = [[[_unsortedChildren reverseObjectEnumerator] allObjects] retain];
		} else _sortedChildren = [[_unsortedChildren sortedArrayUsingSelector:@selector(compare:)] retain];
	}
	return [[_sortedChildren retain] autorelease];
}
- (NSArray<PGNode*> *)unsortedChildren
{
	return [[_unsortedChildren retain] autorelease];
}
- (void)setUnsortedChildren:(NSArray<PGNode*> *)anArray presortedOrder:(PGSortOrder)anOrder
{
	if(anArray == _unsortedChildren) return;
	NSMutableArray *const removedChildren = [[_unsortedChildren mutableCopy] autorelease];
	for(PGNode *const newChild in anArray) [removedChildren removeObjectIdenticalTo:newChild];
	if([removedChildren count]) {
		[[self document] noteNode:[self node] willRemoveNodes:removedChildren];
		[removedChildren makeObjectsPerformSelector:@selector(detachFromTree)];
	}
	[_unsortedChildren release];
	_unsortedChildren = [anArray copy];
	_unsortedOrder = anOrder;
	[_sortedChildren release];
	_sortedChildren = nil;
	[[[self node] menuItem] setSubmenu:_unsortedChildren.count ? [[[NSMenu alloc] init] autorelease] : nil];
	[[self document] noteSortedChildrenDidChange];

//NSLog(@">>> %@ >>>", self.node.identifier.displayName);
	_byteSize		=	0;
	_folderCount	=	_imageCount	=	0;
	for(PGNode *const child in anArray) {
//NSLog(@"\t%@: isContainer %u", child.identifier.displayName, child.resourceAdapter.isContainer);
        if(child.resourceAdapter.isContainer)    //    will this be TRUE for PDF files?
            ++_folderCount;
		else if(child.isViewable) {   //  child.resourceAdapter.canGenerateRealThumbnail
            ++_imageCount;

			_byteSize	+=	child.dataProvider.dataLength.unsignedLongValue;
		}
	}
//NSLog(@"<<< %@ <<<", self.node.identifier.displayName);
}
- (void)removeChild:(PGNode *)node
{
	NSMutableArray<PGNode*> *const unsortedChildren = [[_unsortedChildren mutableCopy] autorelease];
	[unsortedChildren removeObjectIdenticalTo:node];
	[self setUnsortedChildren:unsortedChildren presortedOrder:_unsortedOrder];
}

#pragma mark -

- (PGNode *)childForIdentifier:(PGResourceIdentifier *)anIdent
{
	for(PGNode *const child in _unsortedChildren) if(PGEqualObjects(anIdent, [child identifier])) return child;
	return nil;
}
- (NSUInteger)viewableIndexOfChild:(PGNode *)aNode
{
	NSUInteger index = [[self node] isViewable] ? 1 : 0;
	for(PGNode* const child in [self sortedChildren]) {
		if(child == aNode) return index + [[self parentAdapter] viewableIndexOfChild:[self node]];
		index += [[child resourceAdapter] viewableNodeCount];
	}
	return 0;
}
- (PGNode *)outwardSearchForward:(BOOL)forward fromChild:(PGNode *)start inclusive:(BOOL)inclusive withSelector:(SEL)sel context:(id)context
{
	NSArray *const children = [self sortedChildren];
	NSUInteger i = [children indexOfObjectIdenticalTo:start];
	if(NSNotFound == i) return nil;
	NSInteger const increment = forward ? 1 : -1;
	NSRange const range = NSMakeRange(0, [children count]);
	if(!inclusive) i += increment;
	for(; NSLocationInRange(i, range); i += increment) {
		PGResourceAdapter *const adapter = [[children objectAtIndex:i] resourceAdapter];
		IMP const search = [adapter methodForSelector:sel];
		if(!search) continue;
		PGNode* (* searchInvoker)(id,SEL,BOOL,id) = (PGNode* (*)(id,SEL,BOOL,id)) search;
		PGNode *const node = searchInvoker(adapter, sel, forward, context);
	//	PGNode *const node = search(adapter, sel, forward, context, nil);
		if(node) return node;
	}
	return [[self parentAdapter] outwardSearchForward:forward fromChild:[self node] inclusive:inclusive withSelector:sel context:context]; // TODO: I think this is a bug. Instead of passing up `inclusive`, we should always say YES for our parent nodes. The original `inclusive` parameter should only apply to the original node.
	// Or maybe it should always be NO. If we say yes, we go right back into the child we just came out of.
}
- (void)noteChildValueForCurrentSortOrderDidChange:(PGNode *)child
{
	if([_unsortedChildren indexOfObjectIdenticalTo:child] == NSNotFound) return;
	[_sortedChildren release];
	_sortedChildren = nil;
	[[self document] noteSortedChildrenDidChange];
}

#pragma mark -PGResourceAdapter

- (void)loadIfNecessary
{
	if([self shouldRecursivelyCreateChildren]) [super loadIfNecessary];
	else [[self node] loadFinishedForAdapter:self];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_unsortedChildren makeObjectsPerformSelector:@selector(detachFromTree)];
	[_sortedChildren release];
	[_unsortedChildren release];
	[super dealloc];
}

#pragma mark -<PGResourceAdapter>

- (PGContainerAdapter *)containerAdapter
{
	return self;
}
- (PGContainerAdapter *)rootContainerAdapter
{
	return [self parentAdapter] ? [[self parentAdapter] rootContainerAdapter] : self;
}

#pragma mark -

- (BOOL)hasNodesWithData
{
	if([self canGetData]) return YES;
	for(id const child in [self sortedChildren]) if([[child resourceAdapter] hasNodesWithData]) return YES;
	return NO;
}
- (BOOL)isContainer
{
	return YES;
}
- (BOOL)hasChildren
{
	return !!_unsortedChildren.count;
}
/* - (NSInteger)childCount // returns NSNotFound when isContainer = NO
{
	return _unsortedChildren.count;
}
- (NSUInteger)folderAndImageCount
{
	return Pack2HalfUInts(_folderCount, _imageCount);
} */
- (uint64_t)byteSizeAndFolderAndImageCount
{
	return Pack_ByteSize_FolderImageCounts(_byteSize, _folderCount, _imageCount);
}

- (BOOL)hasSavableChildren
{
	for(id const child in [self sortedChildren]) {
		PGResourceAdapter *childAdapter = [child resourceAdapter];
		if([childAdapter canSaveData] || [childAdapter hasSavableChildren]) return YES;
	}
	return NO;
}

#pragma mark -

- (NSUInteger)viewableNodeCount
{
	NSUInteger count = [[self node] isViewable] ? 1 : 0;
	for(id const child in [self sortedChildren]) count += [[child resourceAdapter] viewableNodeCount];
	return count;
}
- (BOOL)hasViewableNodeCountGreaterThan:(NSUInteger)anInt
{
	NSUInteger count = [[self node] isViewable] ? 1 : 0;
	if(count > anInt) return YES;
	for(PGNode *const child in _unsortedChildren) {
		PGResourceAdapter *const adapter = [child resourceAdapter];
		if([adapter hasViewableNodeCountGreaterThan:anInt - count]) return YES;
		if(![child isViewable]) continue;
		count++;
		if(count > anInt) return YES;
	}
	return NO;
}

#pragma mark -

- (void)addChildrenToMenu:(NSMenu *)menu
{
	for(PGNode *const child in [self sortedChildren]) [child addToMenu:menu flatten:NO];
}

#pragma mark -

- (PGNode *)nodeForIdentifier:(PGResourceIdentifier *)ident
{
	if(!ident) return nil;
	for(PGNode *const child in _unsortedChildren) {
		PGNode *const node = [[child resourceAdapter] nodeForIdentifier:ident];
		if(node) return node;
	}
	return [super nodeForIdentifier:ident];
}
- (PGNode *)sortedViewableNodeNext:(BOOL)flag includeChildren:(BOOL)children
{
	PGNode *const node = children && flag ? [self sortedViewableNodeFirst:YES stopAtNode:nil includeSelf:NO] : nil;
	return node ? node : [super sortedViewableNodeNext:flag includeChildren:children];
}
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag stopAtNode:(PGNode *)descendent includeSelf:(BOOL)includeSelf
{
	if(descendent == [self node]) return nil;
	if(flag) {
		PGNode *const child = [super sortedViewableNodeFirst:YES stopAtNode:descendent includeSelf:includeSelf];
		if(child) return child;
	}
	NSArray *const children = [self sortedChildren];
	for(PGNode *const child in flag ? (id)children : (id)[children reverseObjectEnumerator]) {
		PGNode *const node = [[child resourceAdapter] sortedViewableNodeFirst:flag stopAtNode:descendent includeSelf:YES];
		if(node) return node;
		if([descendent ancestorThatIsChildOfNode:[self node]] == child) return nil;
	}
	return flag ? nil : [super sortedViewableNodeFirst:NO stopAtNode:descendent includeSelf:includeSelf];
}
- (PGNode *)sortedFirstViewableNodeInFolderFirst:(BOOL)flag
{
	if(flag) return [self sortedViewableNodeFirst:YES];
	NSArray *const children = [self sortedChildren];
	for(PGNode *const child in [children reverseObjectEnumerator]) {
		PGNode *const node = [[child resourceAdapter] sortedFirstViewableNodeInFolderFirst:flag];
		if(node) return node;
	}
	for(PGNode *const child in children) if([child isViewable]) return child;
	return nil;
}
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag matchSearchTerms:(NSArray *)terms stopAtNode:(PGNode *)descendent
{
	if(descendent == [self node]) return nil;
	if(flag) {
		PGNode *const child = [super sortedViewableNodeFirst:YES matchSearchTerms:terms stopAtNode:descendent];
		if(child) return child;
	}
	NSArray *const children = [self sortedChildren];
	for(PGNode *const child in flag ? (id)children : (id)[children reverseObjectEnumerator]) {
		PGNode *const node = [[child resourceAdapter] sortedViewableNodeFirst:flag matchSearchTerms:terms stopAtNode:descendent];
		if(node) return node;
		if([descendent ancestorThatIsChildOfNode:[self node]] == child) return nil;
	}
	return flag ? nil : [super sortedViewableNodeFirst:NO matchSearchTerms:terms stopAtNode:descendent];
}

#pragma mark -<PGResourceAdapting>

- (void)noteSortOrderDidChange
{
	[_sortedChildren release];
	_sortedChildren = nil;
	for(PGNode *const child in _unsortedChildren)
		[child noteSortOrderDidChange];
}

@end
