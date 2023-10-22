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
// Models
#import "PGNode.h"
#import "PGDataProvider.h"
#import "PGActivity.h"

extern NSString *const PGPasswordKey;

enum {
	PGRecurseToMaxDepth = 0,
	PGRecurseToAnyDepth = 1,
	PGRecurseNoFurther = 2,
};
typedef NSInteger PGRecursionPolicy;

@protocol PGResourceAdapterImageGeneratorCompletion <NSObject>	//	2023/10/21

@required
- (void)generationDidCompleteInOperation:(NSOperation *)operation;

@end

@interface PGResourceAdapter : NSObject <PGActivityOwner, PGResourceAdapting, PGResourceAdapterImageGeneratorCompletion>
{
	@private
	PGNode *_node;
	PGDataProvider *_dataProvider;
	PGActivity *_activity;
	NSError *_error;

	NSImage *_realThumbnail;
	NSOperation *_generateImageOperation;	//	2023/10/21 generates full image and/or thumbnail if neither exist
}

+ (NSDictionary *)typesDictionary;
+ (NSArray *)supportedFileTypes;
+ (NSArray *)supportedMIMETypes;

- (id)initWithNode:(PGNode *)node dataProvider:(PGDataProvider *)dataProvider;
@property(readonly) PGNode *node;
@property(readonly) id dataProvider;

@property(readonly) PGContainerAdapter *containerAdapter;
@property(readonly) PGContainerAdapter *rootContainerAdapter;
@property(readonly) NSUInteger depth;
@property(readonly) PGRecursionPolicy recursionPolicy;
@property(readonly) BOOL shouldRecursivelyCreateChildren;

@property(readonly) NSData *data;
@property(readonly) uint64_t dataByteSize;	//	2023/09/17
@property(readonly) BOOL canGetData;
@property(readonly) BOOL hasNodesWithData;

@property(readonly) BOOL isContainer;
@property(readonly) BOOL hasChildren;

//	the byte size, folder and image counts returned are for the *direct* children
//	of the object that this adapter represents; children which are more than 1
//	level deep are *not* included; use .byteSizeOfAllChildren for the byte size
//	of all children at all levels
@property(readonly) uint64_t byteSizeAndFolderAndImageCount; // returns ULONG_MAX when isContainer = NO
@property(readonly) uint64_t byteSizeOfAllChildren; // returns ULONG_MAX when isContainer = NO

@property(readonly) BOOL isSortedFirstViewableNodeOfFolder;
@property(readonly) BOOL hasRealThumbnail;
@property(readonly, getter = isResolutionIndependent) BOOL resolutionIndependent;
@property(readonly) BOOL canSaveData;
@property(readonly) BOOL hasSavableChildren;

@property(readonly) NSUInteger viewableNodeIndex;
@property(readonly) NSUInteger viewableNodeCount;
- (BOOL)hasViewableNodeCountGreaterThan:(NSUInteger)anInt;

@property(retain) NSError *error;
- (BOOL)adapterIsViewable;
- (void)loadIfNecessary;
- (void)load; // Sent by -loadIfNecessary, never call it directly. -[node loadFinishedForAdapter:] OR -[node fallbackFromFailedAdapter:] must be sent sometime hereafter.
- (void)read; // Sent by -[PGNode readIfNecessary], never call it directly. -readFinishedWithImageRep: must be sent sometime hereafter.

- (NSImage *)thumbnail;
- (NSImage *)fastThumbnail;
- (NSImage *)realThumbnail;
- (BOOL)canGenerateRealThumbnail;
- (void)invalidateThumbnail;

@property(readonly) NSDictionary *imageProperties;
- (PGOrientation)orientationWithBase:(BOOL)flag;
- (void)clearCache;
- (void)addChildrenToMenu:(NSMenu *)menu;

- (PGNode *)nodeForIdentifier:(PGResourceIdentifier *)ident;
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag;
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag stopAtNode:(PGNode *)descendent includeSelf:(BOOL)includeSelf;
- (PGNode *)sortedViewableNodeNext:(BOOL)flag;
- (PGNode *)sortedViewableNodeNext:(BOOL)flag includeChildren:(BOOL)children;
- (PGNode *)sortedViewableNodeNext:(BOOL)flag afterRemovalOfChildren:(NSArray *)removedChildren fromNode:(PGNode *)changedNode; // Returns a node that will still exist after the change.
- (PGNode *)sortedFirstViewableNodeInFolderNext:(BOOL)forward inclusive:(BOOL)inclusive;
- (PGNode *)sortedFirstViewableNodeInFolderFirst:(BOOL)flag;
- (PGNode *)sortedViewableNodeInFolderFirst:(BOOL)flag;
- (PGNode *)sortedViewableNodeNext:(BOOL)flag matchSearchTerms:(NSArray *)terms;
- (PGNode *)sortedViewableNodeFirst:(BOOL)flag matchSearchTerms:(NSArray *)terms stopAtNode:(PGNode *)descendent;

@property(readonly) BOOL nodeIsFirstOfFolder; // 2022/11/04 added
@property(readonly) BOOL nodeIsLastOfFolder; // 2022/11/04 added

- (void)noteResourceDidChange;

@end

//	private API for use by sub-classes only; clients of PGResourceAdapter
//	should not call these; they are used to send the results of the image
//	generation to the PGResourceAdapter instance for later use when
//	-drawRect: is invoked
@interface PGResourceAdapter (PrivateMethodsForSubclassUse)

- (void)_startGeneratingImages;
- (void)_setThumbnailImageInOperation:(NSOperation *)operation
							 imageRep:(NSImageRep *)rep
						thumbnailSize:(NSSize)size
						  orientation:(PGOrientation)orientation
							   opaque:(BOOL)opaque
		  setParentContainerThumbnail:(BOOL)setParentContainerThumbnail;

@end

//	sub-classes of PGResourceAdapter must implement this protocol:
@protocol PGResourceAdapterImageGeneration <NSObject>	//	2023/10/21

@required
//	invoked on a page in a PDF container:
- (void)generateImagesInOperation:(NSOperation *)operation thumbnailSize:(NSSize)thumbnailSize;

@optional
//	invoked on a PDF container; searches for the page with index 0 and invokes its
//	_startGeneratingImages method:
- (void)generateThumbnailForContainer;

@end

@interface PGDataProvider(PGResourceAdapterLoading)

- (NSArray *)adapterClassesForNode:(PGNode *)node;
- (NSArray *)adaptersForNode:(PGNode *)node;
//- (NSUInteger)matchPriorityForTypeDictionary:(NSDictionary *)dict;

@end
