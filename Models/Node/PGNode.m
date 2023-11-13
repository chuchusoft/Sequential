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
#import "PGNode.h"

// Models
#import "PGDocument.h"
#import "PGResourceAdapter.h"
#import "PGContainerAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGBookmark.h"

// Controllers
#import "PGDisplayController.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"

static
NSComparisonResult
CompareByteSize(uint64_t a, uint64_t b) {
	if(a == b)	return NSOrderedSame;
	if(a < b)	return NSOrderedAscending;
	return NSOrderedDescending;
}

NSString *const PGNodeLoadingDidProgressNotification = @"PGNodeLoadingDidProgress";
NSString *const PGNodeReadyForViewingNotification    = @"PGNodeReadyForViewing";

NSString *const PGImageRepKey       = @"PGImageRep";

NSString *const PGNodeErrorDomain        = @"PGNodeError";

enum {
	PGNodeNothing = 0,
	PGNodeLoading = 1 << 0,
	PGNodeReading = 1 << 1,
	PGNodeLoadingOrReading = PGNodeLoading | PGNodeReading
}; // PGNodeStatus.

#if __has_feature(objc_arc)

@interface PGNode()

@property (nonatomic, weak) id<PGNodeParenting> parent;
@property (nonatomic, strong) PGDisplayableIdentifier *identifier;
//@property (nonatomic, strong) PGDataProvider *dataProvider;
@property (nonatomic, strong) NSMutableArray<PGResourceAdapter *> *potentialAdapters;
@property (nonatomic, strong) PGResourceAdapter *resourceAdapter;//@property (nonatomic, strong) PGResourceAdapter *adapter;
@property (nonatomic, assign) PGNodeStatus status;

@property (nonatomic, assign) BOOL viewable;
@property (nonatomic, strong) NSMenuItem *menuItem;
@property (nonatomic, assign) BOOL allowMenuItemUpdates;

- (void)_stopLoading;

- (void)_updateMenuItem;
- (void)_updateFileAttributes;

@end

#else

@interface PGNode(Private)

- (void)_setResourceAdapter:(PGResourceAdapter *)adapter;
- (void)_stopLoading;

- (void)_updateMenuItem;
- (void)_updateFileAttributes;

@end

#endif

@implementation PGNode

#pragma mark +PGNode

+ (NSArray *)pasteboardTypes
{
	return [NSArray arrayWithObjects:NSPasteboardTypeString, NSPasteboardTypeRTFD, NSFileContentsPboardType, nil];
}

#pragma mark +NSObject

+ (void)initialize
{
	srandom((unsigned) time(NULL)); // Used by our shuffle sort.
}

#pragma mark -PGNode

@synthesize dataProvider = _dataProvider;

- (id)initWithParent:(id<PGNodeParenting>)parent identifier:(PGDisplayableIdentifier *)ident
{
	if(!(self = [super init])) return nil;
	if(!ident) {
#if __has_feature(objc_arc)
		self = nil;
#else
		[self release];
#endif
		return nil;
	}
	_parent = parent;
#if __has_feature(objc_arc)
	_identifier = ident;
#else
	_identifier = [ident retain];
#endif
	_menuItem = [[NSMenuItem alloc] init];
	[_menuItem setRepresentedObject:[NSValue valueWithNonretainedObject:self]];
	[_menuItem setAction:@selector(jumpToPage:)];
	_allowMenuItemUpdates = YES;
	[self _updateMenuItem];
	[_identifier PG_addObserver:self selector:@selector(identifierIconDidChange:) name:PGDisplayableIdentifierIconDidChangeNotification];
	[_identifier PG_addObserver:self selector:@selector(identifierDisplayNameDidChange:) name:PGDisplayableIdentifierDisplayNameDidChangeNotification];
	return self;
}
#if !__has_feature(objc_arc)
- (PGDisplayableIdentifier *)identifier
{
	return [[_identifier retain] autorelease];
}
#endif

#pragma mark -

#if !__has_feature(objc_arc)
- (PGDataProvider *)dataProvider
{
	return [[_dataProvider retain] autorelease];
}
#endif
- (void)setDataProvider:(PGDataProvider *)dp
{
	NSParameterAssert(dp);
	if(dp == _dataProvider) return;
#if __has_feature(objc_arc)
	_dataProvider = dp;
#else
	[_dataProvider release];
	_dataProvider = [dp retain];
#endif
	[self reload];
}
- (void)reload
{
	_status |= PGNodeLoading;
#if !__has_feature(objc_arc)
	[_potentialAdapters release];
#endif
	_potentialAdapters = [[_dataProvider adaptersForNode:self] mutableCopy];
	[self _setResourceAdapter:[_potentialAdapters lastObject]];
	if([_potentialAdapters count]) [_potentialAdapters removeLastObject];
#if __has_feature(objc_arc)
	[_resourceAdapter loadIfNecessary];
#else
	[_resourceAdapter loadIfNecessary];
#endif
}
#if !__has_feature(objc_arc)
- (PGResourceAdapter *)resourceAdapter
{
	return [[_resourceAdapter retain] autorelease];
}
#endif
- (void)loadFinishedForAdapter:(PGResourceAdapter *)adapter
{
	NSParameterAssert(PGNodeLoading & _status);
	NSParameterAssert(adapter == _resourceAdapter);
	[self _stopLoading];
	[self readIfNecessary];
}
- (void)fallbackFromFailedAdapter:(PGResourceAdapter *)adapter
{
	NSParameterAssert(PGNodeLoading & _status);
	NSParameterAssert(adapter == _resourceAdapter);
	[self _setResourceAdapter:[_potentialAdapters lastObject]];
	if(![_potentialAdapters count]) return [self _stopLoading];
	[_potentialAdapters removeLastObject];
	[_resourceAdapter loadIfNecessary];
}

#pragma mark -

- (NSImage *)thumbnail
{
	return PGNodeLoading & _status ? nil : [[self resourceAdapter] thumbnail];
}
- (BOOL)isViewable
{
	return _viewable;
}
- (PGNode *)viewableAncestor
{
	return _viewable ? self : [[self parentNode] viewableAncestor];
}
#if !__has_feature(objc_arc)
- (NSMenuItem *)menuItem
{
	return [[_menuItem retain] autorelease];
}
#endif
- (BOOL)canBookmark
{
	return [self isViewable] && [[self identifier] hasTarget];
}
- (PGBookmark *)bookmark
{
#if __has_feature(objc_arc)
	return [[PGBookmark alloc] initWithNode:self];
#else
	return [[[PGBookmark alloc] initWithNode:self] autorelease];
#endif
}

#pragma mark -

- (void)becomeViewed
{
	[[[self resourceAdapter] activity] prioritize:self];
	if(PGNodeReading & _status) return;
	_status |= PGNodeReading;
	[self readIfNecessary];
}
- (void)readIfNecessary
{
	if((PGNodeLoadingOrReading & _status) == PGNodeReading) [_resourceAdapter read];
}
- (void)setIsReading:(BOOL)reading {	//	2023/10/21
	NSParameterAssert((PGNodeLoadingOrReading & _status) == PGNodeNothing ||
						(PGNodeLoadingOrReading & _status) == PGNodeReading);
	if(reading)
		_status |= PGNodeReading;
	else
		_status &= ~PGNodeReading;
}
- (void)readFinishedWithImageRep:(NSImageRep *)aRep
{
	NSParameterAssert((PGNodeLoadingOrReading & _status) == PGNodeReading);
	_status &= ~PGNodeReading;
	[self PG_postNotificationName:PGNodeReadyForViewingNotification userInfo:[NSDictionary dictionaryWithObjectsAndKeys:aRep, PGImageRepKey, nil]];
}

#pragma mark -

- (void)removeFromDocument
{
	if([[self document] node] == self) [[self document] close];
	else [[self parentAdapter] removeChild:self];
}
- (void)detachFromTree
{
	@synchronized(self) {
		_parent = nil;
	}
}
- (NSComparisonResult)compare:(PGNode *)node
{
	NSParameterAssert(node);
	NSParameterAssert([self document]);
	PGSortOrder const o = [[self document] sortOrder];
	NSInteger const d = PGSortDescendingMask & o ? -1 : 1;
	PGDataProvider *const dp1 = [[self resourceAdapter] dataProvider];
	PGDataProvider *const dp2 = [[node resourceAdapter] dataProvider];
	NSComparisonResult r = NSOrderedSame;
	switch(PGSortOrderMask & o) {
		case PGUnsorted:           return NSOrderedSame;
		case PGSortByDateModified: r = [[dp1 dateModified] compare:[dp2 dateModified]]; break;
		case PGSortByDateCreated:  r = [[dp1 dateCreated] compare:[dp2 dateCreated]]; break;
		case PGSortBySize:         r = CompareByteSize([dp1 dataByteSize], [dp2 dataByteSize]); break;
	//	case PGSortBySize:         r = [[dp1 dataLength] compare:[dp2 dataLength]]; break;
		case PGSortByKind:         r = [[dp1 kindString] compare:[dp2 kindString]]; break;
		case PGSortShuffle:        return random() & 1 ? NSOrderedAscending : NSOrderedDescending;
	}
	return (NSOrderedSame == r ? [[[self identifier] displayName] PG_localizedCaseInsensitiveNumericCompare:[[node identifier] displayName]] : r) * d; // If the actual sort order doesn't produce a distinct ordering, then sort by name too.
}
- (BOOL)writeToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
	BOOL wrote = NO;
	if([types containsObject:NSPasteboardTypeString]) {
		if(pboard) {
			[pboard addTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
			[pboard setString:[[self identifier] displayName] forType:NSPasteboardTypeString];
		}
		wrote = YES;
	}
#if 1
	//	2023/09/10 the original code is time- and space- expensive if the caller does
	//	not provide a NSPasteboard instance. When one is provided, the NSData instance
	//	must be created, but if one is not provided, avoid the creation of the NSData
	//	instance. This improves overall performance when anything involving the
	//	Services menu occurs, as well as when updating the menu items in the menu bar.
	NSData* data = nil;
	if([types containsObject:NSPasteboardTypeRTFD]) {
		if(pboard) {
			data = [[self resourceAdapter] data];

			[pboard addTypes:[NSArray arrayWithObject:NSPasteboardTypeRTFD] owner:nil];
#if __has_feature(objc_arc)
			NSFileWrapper *const wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:data];
#else
			NSFileWrapper *const wrapper = [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
#endif
			[wrapper setPreferredFilename:[[self identifier] displayName]];
#if __has_feature(objc_arc)
			NSAttributedString *const string = [NSAttributedString attributedStringWithAttachment:[[NSTextAttachment alloc] initWithFileWrapper:wrapper]];
#else
			NSAttributedString *const string = [NSAttributedString attributedStringWithAttachment:[[[NSTextAttachment alloc] initWithFileWrapper:wrapper] autorelease]];
#endif
			//	2021/07/21 cannot pass nil to -RTFDFileWrapperFromRange::documentAttributes:
			//	for the documentAttributes: parameter
			[pboard setData:[string RTFDFromRange:NSMakeRange(0, [string length]) documentAttributes:@{NSDocumentTypeDocumentAttribute:@"some doc type"}] forType:NSPasteboardTypeRTFD];
		}
		wrote = YES;
	}
	if([types containsObject:NSFileContentsPboardType]) {
		if(pboard) {
			if(!data) data = [[self resourceAdapter] data];

			[pboard addTypes:[NSArray arrayWithObject:NSFileContentsPboardType] owner:nil];
			[pboard setData:data forType:NSFileContentsPboardType];
		}
		wrote = YES;
	}
#else
	NSData *const data = [[self resourceAdapter] canGetData] ? [[self resourceAdapter] data] : nil;
	if(data) {
		if([types containsObject:NSPasteboardTypeRTFD]) {
			[pboard addTypes:[NSArray arrayWithObject:NSPasteboardTypeRTFD] owner:nil];
			NSFileWrapper *const wrapper = [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
			[wrapper setPreferredFilename:[[self identifier] displayName]];
			NSAttributedString *const string = [NSAttributedString attributedStringWithAttachment:[[[NSTextAttachment alloc] initWithFileWrapper:wrapper] autorelease]];
			//	2021/07/21 cannot pass nil to -RTFDFileWrapperFromRange::documentAttributes:
			//	for the documentAttributes: parameter
			[pboard setData:[string RTFDFromRange:NSMakeRange(0, [string length]) documentAttributes:@{NSDocumentTypeDocumentAttribute:@"some doc type"}] forType:NSPasteboardTypeRTFD];
			wrote = YES;
		}
		if([types containsObject:NSFileContentsPboardType]) {
			if(pboard) {
				[pboard addTypes:[NSArray arrayWithObject:NSFileContentsPboardType] owner:nil];
				[pboard setData:data forType:NSFileContentsPboardType];
			}
			wrote = YES;
		}
	}
#endif
	return wrote;
}
- (void)addToMenu:(NSMenu *)menu flatten:(BOOL)flatten
{
	[_menuItem PG_removeFromMenu];
	if(flatten && [[self resourceAdapter] hasChildren]) {
		[[self resourceAdapter] addChildrenToMenu:menu];
	} else {
		[[self resourceAdapter] addChildrenToMenu:[_menuItem submenu]];
		[menu addItem:_menuItem];
	}
}

#pragma mark -

- (PGNode *)ancestorThatIsChildOfNode:(PGNode *)aNode
{
	PGNode *const parent = [self parentNode];
	return aNode == parent ? self : [parent ancestorThatIsChildOfNode:aNode];
}
- (BOOL)isDescendantOfNode:(PGNode *)aNode
{
	return [self ancestorThatIsChildOfNode:aNode] != nil;
}

#pragma mark -

- (void)identifierIconDidChange:(NSNotification *)aNotif
{
	[self _updateMenuItem];
}
- (void)identifierDisplayNameDidChange:(NSNotification *)aNotif
{
	[self _updateMenuItem];
	if([[self document] isCurrentSortOrder:PGSortByName]) [[self parentAdapter] noteChildValueForCurrentSortOrderDidChange:self];
	[[self document] noteNodeDisplayNameDidChange:self];
}

#pragma mark -

- (void)noteIsViewableDidChange
{
	BOOL const showsLoadingIndicator = !!(PGNodeLoading & _status);
	BOOL const viewable = showsLoadingIndicator || [_resourceAdapter adapterIsViewable];
	if(viewable == _viewable) return;
	_viewable = viewable;
	[[self document] noteNodeIsViewableDidChange:self];
}

#pragma mark -PGNode(Private)

- (void)_setResourceAdapter:(PGResourceAdapter *)adapter
{
	if(adapter == _resourceAdapter) return;
	[[_resourceAdapter activity] setParentActivity:nil];
#if __has_feature(objc_arc)
	_resourceAdapter = adapter;
#else
	[_resourceAdapter release];
	_resourceAdapter = [adapter retain];
#endif
	PGActivity *const parentActivity = [[self parentAdapter] activity];
	[[_resourceAdapter activity] setParentActivity:parentActivity ? parentActivity : [[self document] activity]];
	[self _updateFileAttributes];
	[self noteIsViewableDidChange];
}
- (void)_stopLoading
{
#if !__has_feature(objc_arc)
	[_potentialAdapters release];
#endif
	_potentialAdapters = nil;
	_status &= ~PGNodeLoading;
	[self noteIsViewableDidChange];
	[[self document] noteNodeThumbnailDidChange:self recursively:NO];
}

#pragma mark -

- (void)_updateMenuItem
{
	if(!_allowMenuItemUpdates) return;
#if __has_feature(objc_arc)
	NSMutableAttributedString *const label = [[[self identifier] attributedStringWithAncestory:NO] mutableCopy];
#else
	NSMutableAttributedString *const label = [[[[self identifier] attributedStringWithAncestory:NO] mutableCopy] autorelease];
#endif
	NSString *info = nil;
	NSDate *date = nil;
	PGDataProvider *const dp = [[self resourceAdapter] dataProvider];
	switch(PGSortOrderMask & [[self document] sortOrder]) {
		case PGSortByDateModified: date = [dp dateModified]; break;
		case PGSortByDateCreated:  date = [dp dateCreated]; break;
		case PGSortBySize: info = [[NSNumber numberWithUnsignedLongLong:[dp dataByteSize]] PG_bytesAsLocalizedString]; break;
	//	case PGSortBySize: info = [[dp dataLength] PG_bytesAsLocalizedString]; break;
		case PGSortByKind: info = [dp kindString]; break;
	}
#if __has_feature(objc_arc)
	if(date && !info)
		info = [NSDateFormatter localizedStringFromDate:date
											  dateStyle:NSDateFormatterShortStyle
											  timeStyle:NSDateFormatterShortStyle];
#else
	if(date && !info) info = [date PG_localizedStringWithDateStyle:kCFDateFormatterShortStyle timeStyle:kCFDateFormatterShortStyle];
#endif
	if(info)
#if __has_feature(objc_arc)
		[label appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%@)", info]
																	  attributes:@{
			NSForegroundColorAttributeName: NSColor.grayColor,
			NSFontAttributeName: [NSFont boldSystemFontOfSize:12]}]];
#else
		[label appendAttributedString:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%@)", info] attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor grayColor], NSForegroundColorAttributeName, [NSFont boldSystemFontOfSize:12], NSFontAttributeName, nil]] autorelease]];
#endif
	[_menuItem setAttributedTitle:label];
}
- (void)_updateFileAttributes
{
	[[self parentAdapter] noteChildValueForCurrentSortOrderDidChange:self];
	[self _updateMenuItem];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[_resourceAdapter activity] setParentActivity:nil];

	// Using our generic -PG_removeObserver is about twice as slow as removing the observer for the specific objects we care about. When closing huge folders of thousands of files, this makes a big difference. Even now it's still the slowest part.
	[_identifier PG_removeObserver:self name:PGDisplayableIdentifierIconDidChangeNotification];
	[_identifier PG_removeObserver:self name:PGDisplayableIdentifierDisplayNameDidChangeNotification];
#if !__has_feature(objc_arc)
	[_identifier release];

	[_dataProvider release];
	[_potentialAdapters release];
	[_resourceAdapter release];

	[_menuItem release];
	[super dealloc];
#endif
}

#pragma mark -NSObject(NSObject)

- (NSUInteger)hash
{
	return [[self class] hash] ^ [[self identifier] hash];
}
- (BOOL)isEqual:(id)anObject
{
	return [anObject isMemberOfClass:[self class]] && PGEqualObjects([self identifier], [(PGNode *)anObject identifier]);
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@(%@) %p: %@>",
		self.class, _resourceAdapter.class, self, self.identifier];
}

#pragma mark -<PGResourceAdapting>

- (PGNode *)parentNode
{
	return [[_parent containerAdapter] node];
}
- (PGContainerAdapter *)parentAdapter
{
	return [_parent containerAdapter];
}
- (PGNode *)rootNode
{
	return [self parentNode] ? [[self parentNode] rootNode] : self;
}
- (PGDocument *)document
{
	return [_parent document];
}

#pragma mark -

- (void)noteFileEventDidOccurDirect:(BOOL)flag
{
	[[self identifier] noteNaturalDisplayNameDidChange];
	[self _updateFileAttributes];
	[_resourceAdapter noteFileEventDidOccurDirect:flag];
}
- (void)noteSortOrderDidChange
{
	[self _updateMenuItem];
	[_resourceAdapter noteSortOrderDidChange];
}

@end
