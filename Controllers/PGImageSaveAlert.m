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

#if __has_feature(objc_arc)

@interface PGImageSaveAlert ()

@property (nonatomic, weak) IBOutlet NSView *accessoryView;
@property (nonatomic, weak) IBOutlet NSOutlineView *nodesOutline;
@property (nonatomic, weak) IBOutlet NSTableColumn *nameColumn;
@property (nonatomic, weak) IBOutlet NSTableColumn *errorColumn;
@property (nonatomic, strong) PGNode *rootNode;
@property (nonatomic, strong) NSSet *initialSelection;
@property (nonatomic, strong) NSOpenPanel *openPanel;
@property (nonatomic, strong) NSString *destination;
@property (nonatomic, strong) NSMutableDictionary *saveNamesByNodePointer;
@property (nonatomic, assign) BOOL saveOnSheetClose;
@property (nonatomic, assign) BOOL firstTime;

@end

#endif

//	MARK: -
@implementation PGImageSaveAlert

- (BOOL)_saveNode:(id)node toDirectory:(NSURL *)dir {
	@autoreleasepool {
		NSData *const data = [node resourceAdapter].data;
		if(!data)
			return NO;

		NSURL *const url = [dir URLByAppendingPathComponent:[self saveNameForNode:node] isDirectory:NO];
		if(![data writeToURL:url atomically:NO])
			return NO;

		id const dataProvider = [node resourceAdapter].dataProvider;
		NSDate *const dateModified = [dataProvider dateModified];
		NSDate *const dateCreated = [dataProvider dateCreated];
		if(!dateModified && !dateCreated)
			return YES;

		NSError *error = nil;
		NSMutableDictionary *const md = [NSMutableDictionary dictionaryWithCapacity:2];
		if(dateModified)
			md[NSURLContentModificationDateKey] = dateModified;
		if(dateCreated)
			md[NSURLCreationDateKey] = dateCreated;
		return [url setResourceValues:md error:&error];
	}
}

- (void)_setDestination:(NSURL *)directoryURL {
	//	step 1: set _destination
#if !__has_feature(objc_arc)
	[_destination release];
#endif
	{
		NSMutableData* utf8path = directoryURL ? [[NSMutableData alloc] initWithLength:8192] : nil;
		//	2023/09/24 using modern delegate methods (URLs) but still need to use
		//	NSFileManager API in -outlineView:objectValueForTableColumn:byItem:
		if(directoryURL && [directoryURL getFileSystemRepresentation:utf8path.mutableBytes maxLength:utf8path.length])
			_destination = [[NSString alloc] initWithUTF8String:utf8path.bytes];
		else
			_destination = nil;
#if !__has_feature(objc_arc)
		[utf8path release];
#endif
	}

	if(!_destination)	//	outline view requires non-nil _destination
		return;

	//	step 2: reload node outline view
#if __has_feature(objc_arc)
	[_nodesOutline reloadData];
#else
	[nodesOutline reloadData];
#endif

	//	step 3: perform first-time setup
	if(_firstTime) {
#if __has_feature(objc_arc)
		[_nodesOutline expandItem:_rootNode expandChildren:YES];
#else
		[nodesOutline expandItem:_rootNode expandChildren:YES];
#endif
		_firstTime = NO;
	}

	//	step 4: perform initial selection of nodes using what the user
	//	has selected in the active thumbnail view
	if(!_initialSelection) return;
	NSMutableIndexSet *const indexes = [NSMutableIndexSet indexSet];
	for(PGNode *const node in _initialSelection) {
		if(!node.resourceAdapter.canSaveData) continue;
#if __has_feature(objc_arc)
		NSInteger const rowIndex = [_nodesOutline rowForItem:node];
#else
		NSInteger const rowIndex = [nodesOutline rowForItem:node];
#endif
		if(-1 != rowIndex) [indexes addIndex:(NSUInteger)rowIndex];
	}
#if __has_feature(objc_arc)
	[_nodesOutline selectRowIndexes:indexes byExtendingSelection:NO];
#else
	[nodesOutline selectRowIndexes:indexes byExtendingSelection:NO];
#endif
	NSUInteger const firstRow = indexes.firstIndex;
#if __has_feature(objc_arc)
	if(NSNotFound != firstRow) [_nodesOutline scrollRowToVisible:firstRow];
#else
	if(NSNotFound != firstRow) [nodesOutline scrollRowToVisible:firstRow];
	[_initialSelection release];
#endif
	_initialSelection = nil;
}

- (instancetype)initWithRoot:(PGNode *)root initialSelection:(NSSet *)aSet
{
	if(!(self = [super initWithWindowNibName:@"PGImageSave"]))
		return nil;
#if __has_feature(objc_arc)
	_rootNode = root;
#else
	_rootNode = [root retain];
#endif
	_initialSelection = [aSet copy];
	_saveNamesByNodePointer = [[NSMutableDictionary alloc] init];
	[[NSProcessInfo processInfo] PG_disableSuddenTermination];
	return self;
}
- (void)beginSheetForWindow:(NSWindow *)window
{
	(void)self.window;
	_firstTime = YES;
#if !__has_feature(objc_arc)
	[_openPanel release];
#endif
	_openPanel = [[NSOpenPanel alloc] init];
	[_openPanel PG_addObserver:self selector:@selector(windowDidEndSheet:) name:NSWindowDidEndSheetNotification];
	[_openPanel setCanChooseFiles:NO];
	[_openPanel setCanChooseDirectories:YES];
	[_openPanel setCanCreateDirectories:YES];
	[_openPanel setAllowsMultipleSelection:NO];
	_openPanel.delegate = self;

#if __has_feature(objc_arc)
	_openPanel.accessoryView = _accessoryView;
	_accessoryView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
	_accessoryView.frame = _accessoryView.superview.bounds;
#else
	[_openPanel setAccessoryView:accessoryView];
	[accessoryView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[accessoryView setFrame:[[accessoryView superview] bounds]];
#endif

	NSSavePanel *const savePanel = [NSSavePanel savePanel];
	_openPanel.prompt = savePanel.prompt;
	_openPanel.title = savePanel.title;
#if !__has_feature(objc_arc)
	[self retain];
#endif

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
#if !__has_feature(objc_arc)
	[self release];
#endif
}

//	MARK: -

- (NSString *)saveNameForNode:(PGNode *)node
{
	NSString *const modifiedName = _saveNamesByNodePointer[[NSValue valueWithNonretainedObject:node]];
#if __has_feature(objc_arc)
	return modifiedName ? modifiedName : node.identifier.naturalDisplayName;
#else
	return modifiedName ? [[modifiedName retain] autorelease] : [[node identifier] naturalDisplayName];
#endif
}

//	MARK: - NSObject

- (void)dealloc
{
	[[NSProcessInfo processInfo] PG_enableSuddenTermination];
#if __has_feature(objc_arc)
	[_nodesOutline setDataSource:nil];
	[_nodesOutline setDelegate:nil];
#else
	[nodesOutline setDataSource:nil];
	[nodesOutline setDelegate:nil];

	[_rootNode release];
	[_initialSelection release];
	[_saveNamesByNodePointer release];
	[_destination release];
	[_openPanel release];
	[super dealloc];
#endif
}

//	MARK: - <NSOpenSavePanelDelegate>

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
#if !defined(NS_BLOCK_ASSERTIONS)
	{	//	url should be an URL to a directory
		id value = nil;
		NSParameterAssert(url && url.isFileURL &&
			[url getResourceValue:&value forKey:NSURLIsDirectoryKey error:nil] &&
			value && [value isEqual:@YES]);
	}
#endif

	//	using [_nodesOutline selectedRowIndexes] requires initialization of nodesOutline's
	//	selection and data which might not have occurred yet so perform that init now
	if(!_destination)
		[self _setDestination:url];

	NSUInteger existingFileCount = 0;
	NSString *existingFilename = nil;
	@autoreleasepool {
		NSMutableData* utf8path = [NSMutableData dataWithLength:8192];

#if __has_feature(objc_arc)
		NSIndexSet *const rows = _nodesOutline.selectedRowIndexes;
#else
		NSIndexSet *const rows = [nodesOutline selectedRowIndexes];
#endif
		NSUInteger i = rows.firstIndex;
		for(; NSNotFound != i; i = [rows indexGreaterThanIndex:i]) {
#if __has_feature(objc_arc)
			NSString *const name = [self saveNameForNode:[_nodesOutline itemAtRow:i]];
#else
			NSString *const name = [self saveNameForNode:[nodesOutline itemAtRow:i]];
#endif

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
#if __has_feature(objc_arc)
		NSAlert *const alert = [NSAlert new];
#else
		NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
#endif
		alert.alertStyle = NSAlertStyleCritical;
		if(1 == existingFileCount) alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"%@ already exists in %@. Do you want to replace it?", @"Replace file alert. The first %@ is replaced with the filename, the second is replaced with the destination name."), existingFilename, [_destination PG_displayName]];
		else alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"%lu pages already exist in %@. Do you want to replace them?", @"Replace multiple files alert. %lu is replaced with a number greater than 1, %@ is replaced with the destination name."), (unsigned long)existingFileCount, [_destination PG_displayName]];
		[alert setInformativeText:NSLocalizedString(@"Replacing a file overwrites its current contents.", @"Informative text for replacement alerts.")];
		[alert addButtonWithTitle:NSLocalizedString(@"Replace", nil)].keyEquivalent = @"";
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)].keyEquivalent = @"\r";
		[alert beginSheetModalForWindow:_openPanel completionHandler:^(NSModalResponse returnCode) {
			if(NSAlertFirstButtonReturn == returnCode)
				_saveOnSheetClose = YES;
		}];

		if(outError)
			*outError = [NSError PG_errorWithDomain:@"com.sequential"
											   code:-1
							   localizedDescription:nil
										   userInfo:nil];
		return NO;
	}
	NSMutableArray *const unsavedNodes = [NSMutableArray array];
	NSMutableIndexSet *const unsavedRows = [NSMutableIndexSet indexSet];
#if __has_feature(objc_arc)
	NSIndexSet *const rows = [_nodesOutline.selectedRowIndexes copy];
#else
	NSIndexSet *const rows = [[[nodesOutline selectedRowIndexes] copy] autorelease];
#endif
	NSUInteger i = rows.firstIndex;
	for(; NSNotFound != i; i = [rows indexGreaterThanIndex:i]) {
#if __has_feature(objc_arc)
		id const node = [_nodesOutline itemAtRow:i];
#else
		id const node = [nodesOutline itemAtRow:i];
#endif
		if([self _saveNode:node toDirectory:url])
			continue;

		[unsavedNodes addObject:node];
		[unsavedRows addIndex:i];
	}
	if(!unsavedNodes.count)
		return YES;

	if(_destination) {	//	cannot reset outline view if _destination is nil
#if __has_feature(objc_arc)
		[_nodesOutline reloadData];
		[_nodesOutline selectRowIndexes:unsavedRows byExtendingSelection:NO];
#else
		[nodesOutline reloadData];
		[nodesOutline selectRowIndexes:unsavedRows byExtendingSelection:NO];
#endif
	}

#if __has_feature(objc_arc)
	NSAlert *const alert = [NSAlert new];
#else
	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
#endif
	if(1 == unsavedNodes.count) alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"The image %@ could not be saved to %@.", @"Single image save failure alert. The first %@ is replaced with the filename, the second is replaced with the destination name."), [self saveNameForNode:unsavedNodes[0]], [_destination PG_displayName]];
	else alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"%lu images could not be saved to %@.", @"Multiple image save failure alert. %lu is replaced with the number of files, %@ is replaced with the destination name."), (unsigned long)unsavedNodes.count, [_destination PG_displayName]];
	[alert setInformativeText:NSLocalizedString(@"Make sure the volume is writable and has enough free space.", @"Informative text for save failure alerts.")];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
	[alert beginSheetModalForWindow:_openPanel completionHandler:^(NSModalResponse returnCode) {}];

	if(outError)
		*outError = [NSError PG_errorWithDomain:@"com.sequential"
										   code:-2
						   localizedDescription:nil
									   userInfo:nil];
	return NO;
}

- (void)panel:(id)sender didChangeToDirectoryURL:(nullable NSURL *)url {
	[self _setDestination:url];
}

//	MARK: - <NSOutlineViewDataSource>

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return item ? ((PGContainerAdapter *)[item resourceAdapter]).sortedChildren[index] : _rootNode;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item resourceAdapter].hasSavableChildren;
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return item ? ((PGContainerAdapter *)[item resourceAdapter]).unsortedChildren.count : 1;
}
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *const saveName = [self saveNameForNode:item];
#if __has_feature(objc_arc)
	if(tableColumn == _nameColumn) return saveName;
	else if(tableColumn == _errorColumn)
#else
	if(tableColumn == nameColumn) return saveName;
	else if(tableColumn == errorColumn)
#endif
		if([[NSFileManager defaultManager] fileExistsAtPath:[_destination stringByAppendingPathComponent:saveName]])
			return NSLocalizedString(@"File already exists.",
				@"Appears in the image save alert beside each filename that conflicts with an existing file in the destination folder.");
	return nil;
}
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
#if __has_feature(objc_arc)
	NSParameterAssert(tableColumn == _nameColumn);
#else
	NSParameterAssert(tableColumn == nameColumn);
#endif
	if(((NSString *)object).length) _saveNamesByNodePointer[[NSValue valueWithNonretainedObject:item]] = object;
}

//	MARK: - <NSOutlineViewDelegate>

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
#if __has_feature(objc_arc)
	if(tableColumn == _nameColumn)
#else
	if(tableColumn == nameColumn)
#endif
	{
		[cell setIcon:((PGNode *)item).resourceAdapter.dataProvider.icon];
		[cell setEnabled:[item resourceAdapter].canSaveData];
	}
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
#if __has_feature(objc_arc)
	if(tableColumn != _nameColumn) return NO;
#else
	if(tableColumn != nameColumn) return NO;
#endif
	[outlineView editColumn:0 row:[outlineView rowForItem:item] withEvent:nil select:NO];
	NSText *const fieldEditor = [outlineView.window fieldEditor:NO forObject:outlineView];
	if(!fieldEditor) return NO;
	NSUInteger const extStart = [fieldEditor.string rangeOfString:@"." options:NSBackwardsSearch].location;
	if(NSNotFound != extStart) fieldEditor.selectedRange = NSMakeRange(0, extStart);
	return NO;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return [item resourceAdapter].canSaveData;
}

//	MARK: - <NSWindowDelegate>

- (void)windowDidEndSheet:(NSNotification *)notification
{
	if(!_saveOnSheetClose) return;
	[_openPanel ok:self];
	_saveOnSheetClose = NO;
}

@end
