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
#import "PGThumbnailBrowser.h"

// Other Sources
#import "PGFoundationAdditions.h"

#if !defined(NDEBUG) && 0	//	used to fix the incorrect -[PGNode isEqual:] bug
	#import "PGNode.h"
	#import "PGResourceIdentifier.h"
#endif

#if __has_feature(objc_arc)

@interface PGThumbnailBrowser ()

@property(nonatomic, assign) NSUInteger updateCount;

- (void)_addColumnWithItem:(id)item;

@end

#endif

@interface PGThumbnailBrowser(Private)

- (void)_addColumnWithItem:(id)item;

@end

//	MARK: -
@implementation PGThumbnailBrowser

#if __has_feature(objc_arc)
@synthesize dataSource;
#else
@synthesize dataSource;
#endif
- (void)setDataSource:(NSObject<PGThumbnailBrowserDataSource, PGThumbnailViewDataSource> *)obj
{
	if(obj == dataSource) return;
	dataSource = obj;
	[self.views makeObjectsPerformSelector:@selector(setDataSource:) withObject:obj];
}
#if !__has_feature(objc_arc)
@synthesize delegate;
//@synthesize thumbnailOrientation = _thumbnailOrientation;
#endif
- (void)setThumbnailOrientation:(PGOrientation)orientation
{
	_thumbnailOrientation = orientation;
	NSUInteger i = self.numberOfColumns;
	while(i--) [[self viewAtIndex:i] setThumbnailOrientation:orientation];
}
- (NSSet *)selection
{
	PGThumbnailView *const lastView = self.views.lastObject;
	NSSet *const selection = lastView.selection;
	if(selection.count) return selection;
	id const item = lastView.representedObject;
	return item ? [NSSet setWithObject:item] : nil;
}
- (void)setSelection:(NSSet *)aSet
{
	++_updateCount;
	NSUInteger const initialNumberOfColumns = self.numberOfColumns;
	if(!initialNumberOfColumns) [self _addColumnWithItem:nil];
	else [[self viewAtIndex:0] reloadData];

	NSMutableArray *const path = [NSMutableArray array];
	id obj = [aSet anyObject];
	while((obj = [self.dataSource thumbnailBrowser:self parentOfItem:obj]))
		[path insertObject:obj atIndex:0];

	//	2023/09/25 special case: if the selection is a single container
	//	then the thumbnail view showing the container's contents is removed
	//	from the array of views displayed, which does not match the
	//	behavior of clicking on a single container (which displays the
	//	container's contents in a thumbnail view), so handle this special
	//	case by appending the container to the path, which will trigger
	//	the correct display in the following code; the code to restore
	//	the selection below also needs to handle this special case.
	BOOL singleContainerIsSelected = NO;
	if(1 == aSet.count) {
		obj = [aSet anyObject];
		if([self.dataSource thumbnailBrowser:self itemCanHaveChildren:obj]) {
			[path insertObject:obj atIndex:0];
			singleContainerIsSelected = YES;
		}
	}

	NSUInteger i = 0;
	for(; i < path.count; i++) {
		PGThumbnailView *const view = [self viewAtIndex:i];
		id const item = path[i];
		NSParameterAssert([[self dataSource] thumbnailBrowser:self itemCanHaveChildren:item]);
#if !defined(NDEBUG) && 0	//	used to fix the incorrect -[PGNode isEqual:] bug
NSLog(@"path[%lu].selection := %@", i, [[(PGNode*)item identifier] displayName]);
#endif
		view.selection = [NSSet setWithObject:item];
		if(i + 1 < self.numberOfColumns) {
			PGThumbnailView *const nextView = [self viewAtIndex:i + 1];
			nextView.representedObject = item;
			[nextView reloadData];
		} else [self _addColumnWithItem:item];
	}

	PGThumbnailView *const lastView = [self viewAtIndex:i];
	[self removeColumnsAfterView:lastView];
	if(singleContainerIsSelected) {
		//	2023/09/25 special case: need to set selection in 2nd-last
		//	thumbnail view instead of the last thumbnail view
		NSAssert(i > 0, @"i");
		[[self viewAtIndex:i-1] setSelection:aSet];
	} else if(lastView.representedObject == path.lastObject)
		lastView.selection = aSet;

	--_updateCount;
	if(!_updateCount) {
		[self.window makeFirstResponder:self.views.lastObject];
		[self.delegate thumbnailBrowser:self numberOfColumnsDidChangeFrom:initialNumberOfColumns];
	}
	if(self.numberOfColumns > initialNumberOfColumns)
		[self scrollToLastColumnAnimate:YES];

	//	2023/10/02 bugfix: delegate was not being invoked
	[self.delegate thumbnailBrowserSelectionDidChange:self];
}

//	2023/09/24 select all siblings of the currently selected node(s)
//	or all children if the selected node is a container
- (void)selectAll {
	//	if the last thumbnail view has selected nodes
	//	then select all viewable siblings in that thumbnail view
	PGThumbnailView *const lastView = self.views.lastObject;
	NSSet *const selection = lastView.selection;
	if(selection.count) {
		[lastView selectAll:self];
		return;
	}

	//	if the last thumbnail view has no selection then get its rep-obj
	//	and select of its direct children (which are viewable)
	id const item = lastView.representedObject;
	if(item) {
		//	if views.count is N then last thumbnail view is at index N-1
		//	and its rep-obj is displayed in the thumbnail view at index N-2
		NSParameterAssert([[self views] indexOfObject:lastView] == [[self views] count] - 1);
		PGThumbnailView *thumbnailView = self.views[self.views.count - 2];
		[self thumbnailView:thumbnailView selectAllDirectChildrenOf:item];
	}
}

//	MARK: -

- (void)redisplayItem:(id)item recursively:(BOOL)flag
{
	if(flag) return [self setNeedsDisplay:YES];
	id const parent = [self.dataSource thumbnailBrowser:self parentOfItem:item];
	for(PGThumbnailView *const view in self.views) {
		id const rep = view.representedObject;
		if(rep == parent) {
			NSUInteger const i = [view.items indexOfObjectIdenticalTo:item];
			if(NSNotFound != i) [view setNeedsDisplayInRect:[view frameOfItemAtIndex:i withMargin:YES]];
		}
	}
}

- (void)selectionNeedsDisplay {	//	2023/11/23
	for(PGThumbnailView *const view in self.views)
		[view selectionNeedsDisplay];
}

//	MARK: - PGThumbnailBrowser(Private)

- (void)_addColumnWithItem:(id)item
{
	if(item && dataSource && ![dataSource thumbnailBrowser:self itemCanHaveChildren:item]) return;
#if __has_feature(objc_arc)
	PGThumbnailView *const thumbnailView = [PGThumbnailView new];
#else
	PGThumbnailView *const thumbnailView = [[[PGThumbnailView alloc] init] autorelease];
#endif
//NSLog(@"PGThumbnailView %p . dataSource := %p %@", thumbnailView, [self dataSource], [[self dataSource] description]);
	thumbnailView.dataSource = self.dataSource;
	thumbnailView.delegate = self;
	thumbnailView.representedObject = item;
	thumbnailView.thumbnailOrientation = self.thumbnailOrientation;
	[thumbnailView reloadData];
	if(!self.numberOfColumns) self.columnWidth = NSWidth(thumbnailView.frame);
	[self addColumnWithView:thumbnailView];
}

//	MARK: - PGColumnView

- (void)insertColumnWithView:(NSView *)aView atIndex:(NSUInteger)index
{
	NSUInteger const columns = self.numberOfColumns;
	[super insertColumnWithView:aView atIndex:index];
	if(!_updateCount) [self.delegate thumbnailBrowser:self numberOfColumnsDidChangeFrom:columns];
}
- (void)removeColumnsAfterView:(NSView *)aView
{
	NSUInteger const columns = self.numberOfColumns;
	[super removeColumnsAfterView:aView];
	if(!_updateCount) [self.delegate thumbnailBrowser:self numberOfColumnsDidChangeFrom:columns];
}

//	MARK: - NSResponder

- (IBAction)moveLeft:(id)sender
{
	NSUInteger const i = [self.views indexOfObjectIdenticalTo:self.window.firstResponder];
	if(NSNotFound == i || !i) return;
	[self.views[i] setSelection:[NSSet set]];
	[self.window makeFirstResponder:self.views[i - 1]];
}
- (IBAction)moveRight:(id)sender
{
	NSUInteger const i = [self.views indexOfObjectIdenticalTo:self.window.firstResponder];
	if(NSNotFound == i || i + 1 >= self.numberOfColumns) return;
	PGThumbnailView *const view = self.views[i + 1];
	[self.window makeFirstResponder:view];
	NSArray *const items = view.items;
	if(items.count && !view.selection.count) [view selectItem:items[0] byExtendingSelection:NO];
}

//	MARK: - <PGThumbnailViewDelegate>

- (void)thumbnailViewSelectionDidChange:(PGThumbnailView *)sender
{
	if(_updateCount) return;
	NSSet *const newSelection = sender.selection;
	id const selectedItem = [newSelection anyObject];
	if(newSelection.count != 1 ||
		(dataSource && ![dataSource thumbnailBrowser:self itemCanHaveChildren:selectedItem])) {
		[self removeColumnsAfterView:sender];
		[self.delegate thumbnailBrowserSelectionDidChange:self];
		return;
	}
	NSArray *const views = self.views;
	NSUInteger const col = [views indexOfObjectIdenticalTo:sender];
	NSParameterAssert(NSNotFound != col);
	if(col + 1 < views.count) {
		PGThumbnailView *const nextView = views[col + 1];
		if(nextView.representedObject == selectedItem) return;
		[nextView setSelection:nil];
		nextView.representedObject = selectedItem;
		[nextView reloadData];

		if(![nextView selectActiveNodeIfDisplayedInThisView])
			[self scrollToTopOfColumnWithView:nextView];
	} else
		[self _addColumnWithItem:selectedItem];
	[self scrollToLastColumnAnimate:YES];
	[self.delegate thumbnailBrowserSelectionDidChange:self];
}

- (void)thumbnailView:(PGThumbnailView *)sender selectAllDirectChildrenOf:(id)item {
	//	2023/09/18 implements selecting all of a container's children when option-clicked
	NSParameterAssert(dataSource && [dataSource thumbnailBrowser:self itemCanHaveChildren:item]);

	NSArray *const views = self.views;
	NSUInteger const col = [views indexOfObjectIdenticalTo:sender];
	NSParameterAssert(NSNotFound != col);
	NSParameterAssert(col + 1 < [views count]);
	PGThumbnailView *const nextView = views[col + 1];
	NSParameterAssert(nextView);
	NSParameterAssert([nextView representedObject] == item);
	[nextView selectAll:nil];
}

@end

//	MARK: -
@implementation NSObject(PGThumbnailBrowserDataSource)

- (id)thumbnailBrowser:(PGThumbnailBrowser *)sender parentOfItem:(id)item
{
	return nil;
}
- (BOOL)thumbnailBrowser:(PGThumbnailBrowser *)sender itemCanHaveChildren:(id)item
{
	return YES;
}

@end

@implementation NSObject(PGThumbnailBrowserDelegate)

- (void)thumbnailBrowserSelectionDidChange:(PGThumbnailBrowser *)sender {}
- (void)thumbnailBrowser:(PGThumbnailBrowser *)sender numberOfColumnsDidChangeFrom:(NSUInteger)oldCount {}

@end
