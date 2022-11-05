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
#import "PGActivityPanelController.h"

// Models
#import "PGActivity.h"

// Views
#import "PGProgressIndicatorCell.h"

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

@interface PGActivityPanelController(Private)

- (void)_update;

@end

#pragma mark -
@implementation PGActivityPanelController

- (IBAction)cancelLoad:(id)sender
{
	NSIndexSet *const indexes = [activityOutline selectedRowIndexes];
	NSUInteger i = [indexes firstIndex];
	for(; NSNotFound != i; i = [indexes indexGreaterThanIndex:i]) [[activityOutline itemAtRow:i] cancel:sender];
}

#pragma mark -PGActivityPanelController(Private)

- (void)_update
{
	[activityOutline reloadData];
	[activityOutline expandItem:nil expandChildren:YES];
}

- (void)_enableCancelButton
{
	[cancelButton setEnabled:[[activityOutline selectedRowIndexes] count] > 0];
}

#pragma mark -NSObject(NSOutlineViewNotifications)

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self _enableCancelButton];	//	[cancelButton setEnabled:[[activityOutline selectedRowIndexes] count] > 0];
}

#pragma mark -PGFloatingPanelController

- (NSString *)nibName
{
	return @"PGActivity";
}
- (void)windowWillShow
{
	_updateTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_update) userInfo:nil repeats:YES] retain];
	[self _update];
}
- (void)windowWillClose
{
	[_updateTimer invalidate];
	[_updateTimer release];
	_updateTimer = nil;
}

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	[progressColumn setDataCell:[[[PGProgressIndicatorCell alloc] init] autorelease]];
	[self _enableCancelButton];	//	[self outlineViewSelectionDidChange:nil];
}

#pragma mark -NSObject

- (void)dealloc
{
	[self windowWillClose];
	[super dealloc];
}

#pragma mark id<NSOutlineViewDataSource>

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item
{
	return [[(item ? item : [PGActivity applicationActivity]) childActivities:YES] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item
{
	return [[(item ? item : [PGActivity applicationActivity]) childActivities:YES] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return item ? [[item childActivities:YES] count] > 0 : YES;
}

// NOTE: this method is optional for the View Based OutlineView.
- (nullable id)outlineView:(NSOutlineView *)outlineView
 objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
					byItem:(nullable id)item
{
	if(tableColumn == identifierColumn) {
		static NSDictionary *attrs = nil;
		if(!attrs) {
			NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
			[style setTighteningFactorForTruncation:0.3f];
			[style setLineBreakMode:NSLineBreakByTruncatingMiddle];
			attrs = [[NSDictionary alloc] initWithObjectsAndKeys:style, NSParagraphStyleAttributeName, nil];
		}
		return [[[NSAttributedString alloc] initWithString:[item activityDescription] attributes:attrs] autorelease];
	} else if(tableColumn == progressColumn) {
		return [NSNumber numberWithDouble:[(PGActivity*) item progress]];
	}
	return nil;
}

#pragma mark id<NSOutlineViewDelegate>

#if 1
// View Based OutlineView: See the delegate method -tableView:viewForTableColumn:row: in NSTableView.
- (nullable NSView *)outlineView:(NSOutlineView *)outlineView
			  viewForTableColumn:(nullable NSTableColumn *)tableColumn
							item:(id)item
{
	NSTextField*	result = [[NSTextField new] autorelease];
	result.drawsBackground	=	NO;
	result.bordered			=	NO;
	result.bezeled			=	NO;
	result.editable			=	NO;

	result.font				=	[NSFont systemFontOfSize:0.0];
	result.alignment		=	NSTextAlignmentLeft;

	if(tableColumn == progressColumn) {
		PGActivity*		ai		=	(PGActivity*) item;
		if(![ai progress] || 0 != [[ai childActivities:YES] count])
			return nil;
	}
	return result;
}

/* View Based OutlineView: See the delegate method -tableView:rowViewForRow: in NSTableView.
- (nullable NSTableRowView *)outlineView:(NSOutlineView *)outlineView
						  rowViewForItem:(id)item
{
} */

#else

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if(tableColumn == progressColumn)
		[cell setHidden:![(PGActivity*) item progress] || [[(PGActivity*) item childActivities:YES] count]];
}

#endif

@end
