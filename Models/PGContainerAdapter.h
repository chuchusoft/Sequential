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
#import "PGResourceAdapter.h"

// Models
#import "PGPrefObject.h"
#import "PGNodeParenting.h"

extern NSString *const PGMaxDepthKey;

@interface PGContainerAdapter : PGResourceAdapter
{
	@private
	NSArray<PGNode*> *_sortedChildren;
	NSArray<PGNode*> *_unsortedChildren;
	PGSortOrder _unsortedOrder;
	uint64_t _byteSizeDirectChildren, _byteSizeAllChildren;
	NSUInteger _folderCount, _imageCount;
}

@property(readonly) PGRecursionPolicy descendantRecursionPolicy;

@property(readonly) NSArray<PGNode*> *sortedChildren;
@property(readonly) NSArray<PGNode*> *unsortedChildren;
- (void)setUnsortedChildren:(NSArray<PGNode*> *)anArray presortedOrder:(PGSortOrder)order;
- (void)removeChild:(PGNode *)child;

- (PGNode *)childForIdentifier:(PGResourceIdentifier *)anIdent;
- (NSUInteger)viewableIndexOfChild:(PGNode *)aNode;
- (PGNode *)outwardSearchForward:(BOOL)forward
					   fromChild:(PGNode *)start
					   inclusive:(BOOL)inclusive
					withSelector:(SEL)sel
						 context:(id)context;
/* The selector 'sel' should have one of the following forms:
- (PGNode *)selector;
- (PGNode *)selectorForward:(BOOL)flag;
- (PGNode *)selectorForward:(BOOL)flag withContext:(id)context;
- (PGNode *)selectorForward:(BOOL)flag withContext:(id)context ignored:(id)nil1; */

- (void)noteChildValueForCurrentSortOrderDidChange:(PGNode *)child;

- (uint64_t)byteSizeOfAllChildren;

@end

@interface PGContainerAdapter(PGResourceAdapterMethods) <PGNodeParenting>
@end
