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
#import "PGBookmarkController.h"
#import <Carbon/Carbon.h>

// Models
#import "PGResourceIdentifier.h"
#import "PGBookmark.h"

// Controllers
#import "PGDocumentController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"

//	2023/08/12 the paused document data blob is too large for NSUserDefaults in macOS 12 Monterey:
//	"Sequential [User Defaults] CFPrefsPlistSource (Domain: com.SequentialX.Sequential,
//	User: kCFPreferencesCurrentUser, ByHost: No, Container: (null), Contents Need Refresh: Yes):
//	Attempting to store >= 4194304 bytes of data in CFPreferences/NSUserDefaults on this platform
//	is invalid. This is a bug in Sequential or a library it uses."
//
//	Solution: store this data in a separate file in the Application Support folder instead of in
//	the app's UserDefaults object.
static NSString *const PGPausedDocumentsFileName		=	@"PausedDocuments.plist";
//static NSString *const PGPausedDocumentsKey            = @"PGPausedDocuments4"; // file-ref is NSURL (not AliasHandle)
#if 0
static NSString *const PGPausedDocumentsDeprecated3Key = @"PGPausedDocuments3"; // Deprecated after 2.1.2.
static NSString *const PGPausedDocumentsDeprecated2Key = @"PGPausedDocuments2"; // Deprecated after 1.3.2.
static NSString *const PGPausedDocumentsDeprecatedKey  = @"PGPausedDocuments"; // Deprecated after 1.2.2.
#endif

static PGBookmarkController *sharedBookmarkController = nil;

#if !__LP64__
static OSStatus PGBookmarkControllerFlagsChanged(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData)
{
	[(PGBookmarkController *)inUserData setDeletesBookmarks:!!(GetCurrentEventKeyModifiers() & optionKey)];
	return noErr;
}
#endif

static
NSURL*
GetBookmarksFileURL(BOOL createParentFolderIfNonExistant) {
	NSFileManager*		fileMgr = NSFileManager.defaultManager;
	NSArray<NSURL*>*	urls = [fileMgr URLsForDirectory:NSApplicationSupportDirectory
											   inDomains:NSUserDomainMask];
	if (nil == urls || 1 != urls.count)
		return nil;

	NSURL*	parentFolder = [[urls objectAtIndex:0] URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier
																   isDirectory:YES];
	if (nil == parentFolder)
		return nil;
	NSError*	error = nil;
	BOOL		b = createParentFolderIfNonExistant ?
					[fileMgr createDirectoryAtURL:parentFolder
					  withIntermediateDirectories:NO
									   attributes:nil
											error:&error] : YES;
//if (!b) NSLog(@"error %@", error);
	if (!b) {
		if (!error || !error.userInfo)
			return nil;

		id	ue	=	[error.userInfo objectForKey:NSUnderlyingErrorKey];
		if (!ue || ![ue isKindOfClass:NSError.class])
			return nil;

		error	=	(NSError*) ue;
		if (NSPOSIXErrorDomain != error.domain || EEXIST != error.code)
			return nil;
	}

	return [parentFolder URLByAppendingPathComponent:PGPausedDocumentsFileName isDirectory:NO];
}

@interface PGBookmarkController(Private)

- (void)_updateMenuItemForBookmark:(PGBookmark *)aBookmark;
- (void)_removeBookmarkAtIndex:(NSUInteger)index; // Removes without updating.
- (void)_saveBookmarks;

@end

@implementation PGBookmarkController

#pragma mark +PGBookmarkController

+ (id)sharedBookmarkController
{
	return sharedBookmarkController ? sharedBookmarkController : [[[self alloc] init] autorelease];
}

#pragma mark -PGBookmarkController

- (IBAction)open:(id)sender
{
	PGBookmark *const bookmark = [(NSMenuItem *)sender representedObject];
	BOOL const deleteBookmark = _deletesBookmarks || NSEventModifierFlagOption & [[NSApp currentEvent] modifierFlags];
	if(!deleteBookmark && [bookmark isValid]) {
		[[PGDocumentController sharedDocumentController] openDocumentWithBookmark:bookmark display:YES];
		return;
	}
	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
	[alert setAlertStyle:NSAlertStyleInformational];
	NSButton *const deleteButton = [alert addButtonWithTitle:NSLocalizedString(@"Delete Bookmark", nil)];
	NSButton *const cancelButton = [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
	if(deleteBookmark) return [self removeBookmark:bookmark];
	[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"The file referenced by the bookmark %@ could not be found.", @"Bookmarked file could not be found error. %@ is replaced with the missing page's saved filename."), [[bookmark fileIdentifier] displayName]]];
	[alert setInformativeText:NSLocalizedString(@"It may have been moved or deleted.", @"Bookmarked file could not be found error informative text.")];
	[deleteButton setKeyEquivalent:@""];
	[cancelButton setKeyEquivalent:@"\r"];
	if([alert runModal] == NSAlertFirstButtonReturn) [self removeBookmark:bookmark];
	else [self _updateMenuItemForBookmark:bookmark];
}

#pragma mark -

- (BOOL)deletesBookmarks
{
	return _deletesBookmarks;
}
- (void)setDeletesBookmarks:(BOOL)flag
{
	_deletesBookmarks = flag;
	[bookmarkItem setTitle:flag ? NSLocalizedString(@"Delete", @"The title of the bookmarks menu. Two states.") : NSLocalizedString(@"Resume", @"The title of the bookmarks menu. Two states.")];
}

#pragma mark -

- (void)addBookmark:(PGBookmark *)aBookmark
{
	NSUInteger i;
	while((i = [_bookmarks indexOfObject:aBookmark]) != NSNotFound) [self _removeBookmarkAtIndex:i];
	[_bookmarks addObject:aBookmark];
	[self addMenuItemForBookmark:aBookmark];
	[self _saveBookmarks];
}
- (void)removeBookmark:(PGBookmark *)aBookmark
{
	if(!aBookmark) return;
	[self _removeBookmarkAtIndex:[_bookmarks indexOfObject:aBookmark]];
	[self _saveBookmarks];
}

- (void)addMenuItemForBookmark:(PGBookmark *)aBookmark
{
	NSParameterAssert(aBookmark);
	[emptyMenuItem PG_removeFromMenu];
	if([bookmarkMenu numberOfItems]) [[bookmarkMenu itemAtIndex:0] setKeyEquivalent:@""];
	NSMenuItem *const item = [[[NSMenuItem alloc] init] autorelease];
	[item setTarget:self];
	[item setAction:@selector(open:)];
	[item setRepresentedObject:aBookmark];
	[bookmarkMenu insertItem:item atIndex:0];
	[aBookmark PG_addObserver:self selector:@selector(bookmarkDidUpdate:) name:PGBookmarkDidUpdateNotification];
	[self _updateMenuItemForBookmark:aBookmark];
}
- (PGBookmark *)bookmarkForIdentifier:(PGResourceIdentifier *)ident
{
	for(PGBookmark *const bookmark in _bookmarks) if(PGEqualObjects([bookmark documentIdentifier], ident)) return bookmark;
	return nil;
}

#pragma mark -

- (void)bookmarkDidUpdate:(NSNotification *)aNotif
{
	NSParameterAssert(aNotif);
	[self _updateMenuItemForBookmark:[aNotif object]];
	[self _saveBookmarks];
}

#pragma mark -PGBookmarkController(Private)

- (void)_updateMenuItemForBookmark:(PGBookmark *)aBookmark
{
	NSInteger const index = [bookmarkMenu indexOfItemWithRepresentedObject:aBookmark];
	if(-1 == index) return; // Fail gracefully.
	NSMenuItem *const item = [bookmarkMenu itemAtIndex:index];
	if(![aBookmark isValid]) {
		[item setAttributedTitle:nil];
		[item setTitle:[NSString stringWithFormat:NSLocalizedString(@"Missing File %@", @"Bookmark menu item used when the file named %@ cannot be found."), [[aBookmark fileIdentifier] displayName]]];
		return;
	}
	NSMutableAttributedString *const title = [[[NSMutableAttributedString alloc] init] autorelease];
	[title appendAttributedString:[[aBookmark documentIdentifier] attributedStringWithAncestory:NO]];
	if(!PGEqualObjects([aBookmark documentIdentifier], [aBookmark fileIdentifier])) {
		[[title mutableString] appendFormat:@" %C ", (unichar)0x25B8];
		[title appendAttributedString:[[aBookmark fileIdentifier] attributedStringWithAncestory:NO]];
	}
	[item setAttributedTitle:title];
}
- (void)_removeBookmarkAtIndex:(NSUInteger)index
{
	[[_bookmarks objectAtIndex:index] PG_removeObserver:self name:PGBookmarkDidUpdateNotification];
	[_bookmarks removeObjectAtIndex:index];
	[bookmarkMenu removeItemAtIndex:[bookmarkMenu numberOfItems] - index - 1];
	if(![_bookmarks count]) [bookmarkMenu addItem:emptyMenuItem];
}

- (void)_saveBookmarks
{
#if 1	//	2023/08/12 now saved to a separate file instead of NSUserDefaults (because it generates too-much-data warnings)
		NSError*	error = nil;
		NSData*		archivedBookmarks = [NSKeyedArchiver archivedDataWithRootObject:_bookmarks
															  requiringSecureCoding:YES
																			  error:&error];
		if (nil == archivedBookmarks || nil != error)
			return;

		NSURL*	url = GetBookmarksFileURL(YES);
//NSLog(@"%@ url = %@", PGPausedDocumentsFileName, url);
		(void) [archivedBookmarks writeToURL:url options:NSDataWritingAtomic error:&error];
#elif 1	//	2021/07/21 modernized
/*	{
		NSError*	error = nil;
		NSData* d = [NSKeyedArchiver archivedDataWithRootObject:NSUserDefaults.standardUserDefaults.dictionaryRepresentation
										  requiringSecureCoding:YES
														  error:&error];
		NSLog(@"defaults as archived data is %lu bytes", d.length);
		NSLog(@"defaults is \n%@", NSUserDefaults.standardUserDefaults.dictionaryRepresentation);
	}
	{
		NSError*	error = nil;
		NSData* d = [NSKeyedArchiver archivedDataWithRootObject:_bookmarks
										  requiringSecureCoding:YES
														  error:&error];
		NSLog(@"_bookmarks as archived data is %lu bytes", d.length);
	}	*/

	//	this generates a warning in the log that too much data is written out
	//	but the data is written out anyway; if it ever stops working then
	//	the _bookmarks array will need to be written to a separate file in the
	//	~/Library/Preferences folder; use the NSLibraryDirectory key with this API:
	//
	//	-(NSArray<NSString *> *)NSSearchPathForDirectoriesInDomains(
	//		NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask,
	//		BOOL expandTilde);

	NSError*	error = nil;
	[NSUserDefaults.standardUserDefaults setObject:
		[NSKeyedArchiver archivedDataWithRootObject:_bookmarks
							  requiringSecureCoding:YES
											  error:&error]
											forKey:PGPausedDocumentsKey];
#else
	[[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:_bookmarks] forKey:PGPausedDocumentsKey];
#endif
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		if(!sharedBookmarkController) {
			sharedBookmarkController = [self retain];
#if !__LP64__
			EventTypeSpec const list[] = {{kEventClassKeyboard, kEventRawKeyModifiersChanged}, {kEventClassMenu, kEventMenuOpening}};
			InstallEventHandler(GetUserFocusEventTarget(), PGBookmarkControllerFlagsChanged, 2, list, self, NULL);
#endif
		}

#if 1	//	2023/08/12 now saved to a separate file instead of NSUserDefaults (because it generates too-much-data warnings)
		NSURL*		url = GetBookmarksFileURL(NO);
//NSLog(@"%@ url = %@", PGPausedDocumentsFileName, url);
		NSError*	error = nil;
		NSData*		bookmarksData = [NSData dataWithContentsOfURL:url options:0 error:&error];
#else
		NSUserDefaults *const defaults = [NSUserDefaults standardUserDefaults];
		NSData *bookmarksData = [defaults objectForKey:PGPausedDocumentsKey];
#endif

		BOOL bookmarksDataIsFromPGPausedDocumentsKey = nil != bookmarksData;

		//	2023/08/12 transfer list of paused documents from UserDefaults to separate file
		if (!bookmarksDataIsFromPGPausedDocumentsKey) {
			bookmarksData	=	[NSUserDefaults.standardUserDefaults objectForKey:@"PGPausedDocuments4"];
			if (nil != bookmarksData) {
				[NSUserDefaults.standardUserDefaults removeObjectForKey:@"PGPausedDocuments4"];
				[NSUserDefaults.standardUserDefaults synchronize];
			}
		}

#if 1	//	2021/07/21 modernized
		if(bookmarksData) {
			NSError* error = nil;
			NSSet* classes = [NSSet setWithArray:@[[NSMutableArray class], [PGBookmark class]]];
		//	NSSet* classes = [NSSet setWithArray:@[[NSData class], [NSMutableArray class], [PGBookmark class]]];
			_bookmarks = [[NSKeyedUnarchiver unarchivedObjectOfClasses:classes
															  fromData:bookmarksData
																 error:&error] retain];
		}
		if(!_bookmarks)
			_bookmarks = [NSMutableArray new];
#else
		if(!bookmarksData) {
			bookmarksData = [defaults objectForKey:PGPausedDocumentsDeprecated3Key];
			[defaults removeObjectForKey:PGPausedDocumentsDeprecated3Key];
		}
		if(!bookmarksData) {
			bookmarksData = [defaults objectForKey:PGPausedDocumentsDeprecated2Key];
			[defaults removeObjectForKey:PGPausedDocumentsDeprecated2Key];
		}
		if(!bookmarksData) {
			bookmarksData = [defaults objectForKey:PGPausedDocumentsDeprecatedKey];
			[defaults removeObjectForKey:PGPausedDocumentsDeprecatedKey];
		}
		_bookmarks = bookmarksData ? [[NSKeyedUnarchiver unarchiveObjectWithData:bookmarksData] retain] : [[NSMutableArray alloc] init];
#endif

		assert([_bookmarks isKindOfClass:[NSMutableArray class]]);
		if(!bookmarksDataIsFromPGPausedDocumentsKey)
			[self _saveBookmarks];
	}
	return self;
}
- (void)dealloc
{
	[self PG_removeObserver];
	[emptyMenuItem release];
	[_bookmarks release];
	[super dealloc];
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	[emptyMenuItem retain];
	for(PGBookmark *const bookmark in _bookmarks)
		[self addMenuItemForBookmark:bookmark];
}

@end
