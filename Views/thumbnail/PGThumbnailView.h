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
// Other Sources
#import "PGGeometryTypes.h"

@protocol PGThumbnailViewDataSource;
@protocol PGThumbnailViewDelegate;

@interface PGThumbnailView : NSView
#if !__has_feature(objc_arc)
{
	@private
	IBOutlet NSObject<PGThumbnailViewDataSource> * dataSource;
	IBOutlet NSObject<PGThumbnailViewDelegate> * delegate;
	IBOutlet id representedObject;
	PGOrientation _thumbnailOrientation;
	NSArray *_items;
	NSMutableSet *_selection;
	id _selectionAnchor;
}
#endif

#if __has_feature(objc_arc)
@property (nonatomic, weak) IBOutlet NSObject<PGThumbnailViewDataSource> *dataSource;
@property (nonatomic, weak) IBOutlet NSObject<PGThumbnailViewDelegate> *delegate;
@property (nonatomic, strong) id representedObject;
@property (nonatomic, assign) PGOrientation thumbnailOrientation;

@property (readonly) NSArray *items;
@property (nonatomic, copy) NSSet *selection;
//@property (nonatomic, readonly) NSSet *selection;
@property (readonly, weak) id selectionAnchor;
#else
@property(assign, nonatomic) NSObject<PGThumbnailViewDataSource> *dataSource;
@property(assign, nonatomic) NSObject<PGThumbnailViewDelegate> *delegate;
@property(retain, nonatomic) id representedObject;
@property(assign, nonatomic) PGOrientation thumbnailOrientation;

@property(readonly) NSArray *items;
@property(copy, nonatomic) NSSet *selection;
@property(readonly) id selectionAnchor;
#endif
- (void)selectItem:(id)item byExtendingSelection:(BOOL)extend;
- (void)deselectItem:(id)item;
- (void)toggleSelectionOfItem:(id)item;
- (void)moveUp:(BOOL)up byExtendingSelection:(BOOL)ext;
//- (void)selectAll;	//	2023/09/18
- (BOOL)selectActiveNodeIfDisplayedInThisView;

- (NSUInteger)indexOfItemAtPoint:(NSPoint)p;
- (NSRect)frameOfItemAtIndex:(NSUInteger)index withMargin:(BOOL)flag;

- (void)reloadData;
- (void)sizeToFit;
//- (void)scrollToSelectionAnchor;	2023/08/17 removed (method is now private)

//	invalidates selected items (forces a screen update)
- (void)selectionNeedsDisplay;	//	2023/11/23

- (void)windowDidChangeKey:(NSNotification *)aNotif;
- (void)systemColorsDidChange:(NSNotification *)aNotif;

@end

@protocol PGThumbnailViewDataSource <NSObject>

@required	//@optional
- (NSArray *)itemsForThumbnailView:(PGThumbnailView *)sender;
- (NSImage *)thumbnailView:(PGThumbnailView *)sender thumbnailForItem:(id)item;
- (BOOL)thumbnailView:(PGThumbnailView *)sender canSelectItem:(id)item;
- (BOOL)thumbnailView:(PGThumbnailView *)sender isContainerItem:(id)item;
- (OSType)thumbnailView:(PGThumbnailView *)sender typeCodeForItem:(id)item;	//	2023/10/22
- (NSURL *)thumbnailView:(PGThumbnailView *)sender urlForItem:(id)item;	//	2023/10/14
- (NSString *)thumbnailView:(PGThumbnailView *)sender labelForItem:(id)item;
- (NSColor *)thumbnailView:(PGThumbnailView *)sender labelColorForItem:(id)item;
- (NSRect)thumbnailView:(PGThumbnailView *)sender highlightRectForItem:(id)item; // A rect within {{0, 0}, {1, 1}}.
- (BOOL)thumbnailView:(PGThumbnailView *)sender hasRealThumbnailForItem:(id)item;

//	can return NSNotFound if item is not a container/folder:
//- (NSInteger)thumbnailView:(PGThumbnailView *)sender directChildrenCountForItem:(id)item;
//	packs 2 half-NSUInteger values into a single NSUInteger
//	upper half is folder count; lower half is image count
//- (NSUInteger)thumbnailView:(PGThumbnailView *)sender folderAndImageDirectChildrenCountForItem:(id)item;
- (uint64_t)thumbnailView:(PGThumbnailView *)sender byteSizeAndFolderAndImageCountOfDirectChildrenForItem:(id)item;
- (uint64_t)thumbnailView:(PGThumbnailView *)sender byteSizeOfAllChildrenForItem:(id)item;
- (uint64_t)thumbnailView:(PGThumbnailView *)sender byteSizeOf:(id)item;

- (id)activeNodeForThumbnailView:(PGThumbnailView *)sender;	//	2023/11/23
- (BOOL)thumbnailView:(PGThumbnailView *)sender isParentOfActiveNode:(id)item;

@end

@protocol PGThumbnailViewDelegate <NSObject>

@optional
- (void)thumbnailViewSelectionDidChange:(PGThumbnailView *)sender;
- (void)thumbnailView:(PGThumbnailView *)sender selectAllDirectChildrenOf:(id)item;	//	2023/09/18

@end
