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
#import "PGImageSaveAlert.h"

// Models
#import "PGNode.h"
#import "PGContainerAdapter.h"
#import "PGGenericImageAdapter.h"
#import "PGResourceIdentifier.h"

// Other Sources
#import "PGFoundationAdditions.h"

@implementation PGImageSaveAlert

- (BOOL)_saveNode:(id)node toDirectory:(NSURL *)dir {
	@autoreleasepool {
		NSData *const data = [[node resourceAdapter] data];
		if(!data)
			return NO;

		NSURL *const url = [dir URLByAppendingPathComponent:[self saveNameForNode:node] isDirectory:NO];
		if(![data writeToURL:url atomically:NO])
			return NO;

		id const dataProvider = [[node resourceAdapter] dataProvider];
		NSDate *const dateModified = [dataProvider dateModified];
		NSDate *const dateCreated = [dataProvider dateCreated];
		if(!dateModified && !dateCreated)
			return YES;

		NSError *error = nil;
		NSMutableDictionary *const md = [NSMutableDictionary dictionaryWithCapacity:2];
		if(dateModified)
			[md setObject:dateModified forKey:NSURLContentModificationDateKey];
		if(dateCreated)
			[md setObject:dateCreated forKey:NSURLCreationDateKey];
		return [url setResourceValues:md error:&error];
	}
}

- (void)_setDestination:(NSURL *)directoryURL {
	//	step 1: set _destination
	[_destination release];
	{
		NSMutableData* utf8path = directoryURL ? [[NSMutableData alloc] initWithLength:8192] : nil;
		//	2023/09/24 using modern delegate methods (URLs) but still need to use
		//	NSFileManager API in -outlineView:objectValueForTableColumn:byItem:
		if(directoryURL && [directoryURL getFileSystemRepresentation:utf8path.mutableBytes maxLength:utf8path.length])
			_destination = [[NSString alloc] initWithUTF8String:utf8path.bytes];
		else
			_destination = nil;
		[utf8path release];
	}

	if(!_destination)	//	outline view requires non-nil _destination
		return;

	//	step 2: reload node outline view
	[nodesOutline reloadData];

	//	step 3: perform first-time setup
	if(_firstTime) {
		[nodesOutline expandItem:_rootNode expandChildren:YES];
		_firstTime = NO;
	}

	//	step 4: perform initial selection of nodes using what the user
	//	has selected in the active thumbnail view
	if(!_initialSelection) return;
	NSMutableIndexSet *const indexes = [NSMutableIndexSet indexSet];
	for(PGNode *const node in _initialSelection) {
		if(![[node resourceAdapter] canSaveData]) continue;
		NSInteger const rowIndex = [nodesOutline rowForItem:node];
		if(-1 != rowIndex) [indexes addIndex:(NSUInteger)rowIndex];
	}
	[nodesOutline selectRowIndexes:indexes byExtendingSelection:NO];
	NSUInteger const firstRow = [indexes firstIndex];
	if(NSNotFound != firstRow) [nodesOutline scrollRowToVisible:firstRow];
	[_initialSelection release];
	_initialSelection = nil;
}

- (id)initWithRoot:(PGNode *)root initialSelection:(NSSet *)aSet
{
	if(!(self = [super initWithWindowNibName:@"PGImageSave"])) return nil;
	_rootNode = [root retain];
	_initialSelection = [aSet copy];
	_saveNamesByNodePointer = [[NSMutableDictionary alloc] init];
	[[NSProcessInfo processInfo] PG_disableSuddenTermination];
	return self;
}
- (void)beginSheetForWindow:(NSWindow *)window
{
	(void)[self window];
	_firstTime = YES;
	[_openPanel release];
	_openPanel = [[NSOpenPanel alloc] init];
	[_openPanel PG_addObserver:self selector:@selector(windowDidEndSheet:) name:NSWindowDidEndSheetNotification];
	[_openPanel setCanChooseFiles:NO];
	[_openPanel setCanChooseDirectories:YES];
	[_openPanel setCanCreateDirectories:YES];
	[_openPanel setAllowsMultipleSelection:NO];
	[_openPanel setDelegate:self];

	[_openPanel setAccessoryView:accessoryView];
	[accessoryView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[accessoryView setFrame:[[accessoryView superview] bounds]];

	NSSavePanel *const savePanel = [NSSavePanel savePanel];
	[_openPanel setPrompt:[savePanel prompt]];
	[_openPanel setTitle:[savePanel title]];
	[self retain];

	_openPanel.directoryURL		=	_rootNode.identifier.URL.URLByDeletingLastPathComponent;
	_openPanel.allowedFileTypes	=	nil;
	if(window) {
		[_openPanel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
			[self openPanelDidEnd:_openPanel returnCode:result contextInfo:NULL];
		}];
	} else {
		[self openPanelDidEnd:_openPanel returnCode:[_openPanel runModal] contextInfo:NULL];
	}
}
- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[panel orderOut:self];
	[_openPanel PG_removeObserver:self name:NSWindowDidEndSheetNotification];
	[_openPanel setDelegate:nil];
	[self release];
}

#pragma mark -

- (NSString *)saveNameForNode:(PGNode *)node
{
	NSString *const modifiedName = [_saveNamesByNodePointer objectForKey:[NSValue valueWithNonretainedObject:node]];
	return modifiedName ? [[modifiedName retain] autorelease] : [[node identifier] naturalDisplayName];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[NSProcessInfo processInfo] PG_enableSuddenTermination];
	[nodesOutline setDataSource:nil];
	[nodesOutline setDelegate:nil];
	[_rootNode release];
	[_initialSelection release];
	[_saveNamesByNodePointer release];
	[_destination release];
	[_openPanel release];
	[super dealloc];
}

#pragma mark -<NSOpenSavePanelDelegate>

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
#if !defined(NS_BLOCK_ASSERTIONS)
	{	//	url should be an URL to a directory
		id value = nil;
		NSParameterAssert(url && url.isFileURL &&
			[url getResourceValue:&value forKey:NSURLIsDirectoryKey error:nil] &&
			value && [value isEqual:@YES]);
	}
#endif

	//	using [nodesOutline selectedRowIndexes] requires initialization of nodesOutline's
	//	selection and data which might not have occurred yet so perform that init now
	if(!_destination)
		[self _setDestination:url];

	NSUInteger existingFileCount = 0;
	NSString *existingFilename = nil;
	@autoreleasepool {
		NSMutableData* utf8path = [NSMutableData dataWithLength:8192];

		NSIndexSet *const rows = [nodesOutline selectedRowIndexes];
		NSUInteger i = [rows firstIndex];
		for(; NSNotFound != i; i = [rows indexGreaterThanIndex:i]) {
			NSString *const name = [self saveNameForNode:[nodesOutline itemAtRow:i]];

			//	2023/09/24 modernized to using URLs but still need to use NSFileManager API so...
			if(![url getFileSystemRepresentation:utf8path.mutableBytes maxLength:utf8path.length])
				continue;

			NSString *const path = [NSString stringWithUTF8String:utf8path.bytes];
			if(![[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:name]])
				continue;

			existingFileCount++;
			existingFilename = name;
		}
	}
	if(existingFileCount && !_saveOnSheetClose) {
		NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
		[alert setAlertStyle:NSAlertStyleCritical];
		if(1 == existingFileCount) [alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"%@ already exists in %@. Do you want to replace it?", @"Replace file alert. The first %@ is replaced with the filename, the second is replaced with the destination name."), existingFilename, [_destination PG_displayName]]];
		else [alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"%lu pages already exist in %@. Do you want to replace them?", @"Replace multiple files alert. %lu is replaced with a number greater than 1, %@ is replaced with the destination name."), (unsigned long)existingFileCount, [_destination PG_displayName]]];
		[alert setInformativeText:NSLocalizedString(@"Replacing a file overwrites its current contents.", @"Informative text for replacement alerts.")];
		[[alert addButtonWithTitle:NSLocalizedString(@"Replace", nil)] setKeyEquivalent:@""];
		[[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)] setKeyEquivalent:@"\r"];
		[alert beginSheetModalForWindow:_openPanel completionHandler:^(NSModalResponse returnCode) {
			if(NSAlertFirstButtonReturn == returnCode)
				_saveOnSheetClose = YES;
		}];

		*outError = [NSError PG_errorWithDomain:@"com.sequential" code:-1 localizedDescription:(NSString *)nil userInfo:(NSDictionary *)nil];
		return NO;
	}
	NSMutableArray *const unsavedNodes = [NSMutableArray array];
	NSMutableIndexSet *const unsavedRows = [NSMutableIndexSet indexSet];
	NSIndexSet *const rows = [[[nodesOutline selectedRowIndexes] copy] autorelease];
	NSUInteger i = [rows firstIndex];
	for(; NSNotFound != i; i = [rows indexGreaterThanIndex:i]) {
		id const node = [nodesOutline itemAtRow:i];
		if([self _saveNode:node toDirectory:url])
			continue;

		[unsavedNodes addObject:node];
		[unsavedRows addIndex:i];
	}
	if(![unsavedNodes count])
		return YES;

	if(_destination) {	//	cannot reset outline view if _destination is nil
		[nodesOutline reloadData];
		[nodesOutline selectRowIndexes:unsavedRows byExtendingSelection:NO];
	}

	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
	if(1 == [unsavedNodes count]) [alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"The image %@ could not be saved to %@.", @"Single image save failure alert. The first %@ is replaced with the filename, the second is replaced with the destination name."), [self saveNameForNode:[unsavedNodes objectAtIndex:0]], [_destination PG_displayName]]];
	else [alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"%lu images could not be saved to %@.", @"Multiple image save failure alert. %lu is replaced with the number of files, %@ is replaced with the destination name."), (unsigned long)[unsavedNodes count], [_destination PG_displayName]]];
	[alert setInformativeText:NSLocalizedString(@"Make sure the volume is writable and has enough free space.", @"Informative text for save failure alerts.")];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
	[alert beginSheetModalForWindow:_openPanel completionHandler:^(NSModalResponse returnCode) {}];

	*outError = [NSError PG_errorWithDomain:@"com.sequential" code:-2 localizedDescription:(NSString *)nil userInfo:(NSDictionary *)nil];
	return NO;
}

- (void)panel:(id)sender didChangeToDirectoryURL:(nullable NSURL *)url {
	[self _setDestination:url];
}

#pragma mark -<NSOutlineViewDataSource>

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return item ? [[(PGContainerAdapter *)[item resourceAdapter] sortedChildren] objectAtIndex:index] : _rootNode;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[item resourceAdapter] hasSavableChildren];
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return item ? [[(PGContainerAdapter *)[item resourceAdapter] unsortedChildren] count] : 1;
}
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *const saveName = [self saveNameForNode:item];
	if(tableColumn == nameColumn) return saveName;
	else if(tableColumn == errorColumn) if([[NSFileManager defaultManager] fileExistsAtPath:[_destination stringByAppendingPathComponent:saveName]]) return NSLocalizedString(@"File already exists.", @"Appears in the image save alert beside each filename that conflicts with an existing file in the destination folder.");
	return nil;
}
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSParameterAssert(tableColumn == nameColumn);
	if([(NSString *)object length]) [_saveNamesByNodePointer setObject:object forKey:[NSValue valueWithNonretainedObject:item]];
}

#pragma mark -<NSOutlineViewDelegate>

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if(tableColumn == nameColumn) {
		[cell setIcon:[[[(PGNode *)item resourceAdapter] dataProvider] icon]];
		[cell setEnabled:[[item resourceAdapter] canSaveData]];
	}
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if(tableColumn != nameColumn) return NO;
	[outlineView editColumn:0 row:[outlineView rowForItem:item] withEvent:nil select:NO];
	NSText *const fieldEditor = [[outlineView window] fieldEditor:NO forObject:outlineView];
	if(!fieldEditor) return NO;
	NSUInteger const extStart = [[fieldEditor string] rangeOfString:@"." options:NSBackwardsSearch].location;
	if(NSNotFound != extStart) [fieldEditor setSelectedRange:NSMakeRange(0, extStart)];
	return NO;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return [[item resourceAdapter] canSaveData];
}

#pragma mark -<NSWindowDelegate>

- (void)windowDidEndSheet:(NSNotification *)notification
{
	if(!_saveOnSheetClose) return;
	[_openPanel ok:self];
	_saveOnSheetClose = NO;
}

@end
