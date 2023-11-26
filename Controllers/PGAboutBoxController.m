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
#import "PGAboutBoxController.h"

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGZooming.h"

static NSString *const PGPaneItemKey = @"PGPaneItem";

static PGAboutBoxController *PGSharedAboutBoxController;

#if __has_feature(objc_arc)

@interface PGAboutBoxController ()

@property (nonatomic, weak) IBOutlet NSSegmentedControl *paneControl;
@property (nonatomic, weak) IBOutlet NSTextView *textView;

@end

#endif

//	MARK: -
@implementation PGAboutBoxController

//	MARK: + PGAboutBoxController

+ (PGAboutBoxController*)sharedAboutBoxController
{
#if __has_feature(objc_arc)
	return PGSharedAboutBoxController ? PGSharedAboutBoxController : [self new];
#else
	return PGSharedAboutBoxController ? PGSharedAboutBoxController : [[[self alloc] init] autorelease];
#endif
}

//	MARK: - PGAboutBoxController

- (IBAction)changePane:(id)sender
{
	NSString *path = nil;
#if __has_feature(objc_arc)
	switch(_paneControl.selectedSegment) {
		case 0: path = [[NSBundle mainBundle] pathForResource:@"Credits" ofType:@"rtf"]; break;
		case 1: path = [[NSBundle mainBundle] pathForResource:@"History" ofType:@"txt"]; break;
		case 2: path = [[NSBundle mainBundle] pathForResource:@"License" ofType:@"txt"]; break;
	}
	if(!path) return;
	[_textView setSelectedRange:NSMakeRange(0, 0)];
	[_textView.textStorage removeLayoutManager:_textView.layoutManager];
	NSDictionary *attrs = nil;
	NSTextStorage* ts = [[NSTextStorage alloc] initWithURL:[path PG_fileURL]
		options:@{NSCharacterEncodingDocumentAttribute:@(NSUTF8StringEncoding)}
												/* options:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding], NSCharacterEncodingDocumentAttribute, nil] */
		documentAttributes:&attrs error:NULL];
	[ts addLayoutManager:_textView.layoutManager];
#else
	switch([paneControl selectedSegment]) {
		case 0: path = [[NSBundle mainBundle] pathForResource:@"Credits" ofType:@"rtf"]; break;
		case 1: path = [[NSBundle mainBundle] pathForResource:@"History" ofType:@"txt"]; break;
		case 2: path = [[NSBundle mainBundle] pathForResource:@"License" ofType:@"txt"]; break;
	}
	if(!path) return;
	[textView setSelectedRange:NSMakeRange(0, 0)];
	[[textView textStorage] removeLayoutManager:[textView layoutManager]];
	NSDictionary *attrs = nil;
	NSTextStorage* ts = [[NSTextStorage alloc] initWithURL:[path PG_fileURL]
		options:@{NSCharacterEncodingDocumentAttribute:@(NSUTF8StringEncoding)}
												/* options:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding], NSCharacterEncodingDocumentAttribute, nil] */
		documentAttributes:&attrs error:NULL];
	[ts addLayoutManager:[textView layoutManager]];

	[ts autorelease];
#endif

	if(PGEqualObjects(attrs[NSDocumentTypeDocumentAttribute], NSPlainTextDocumentType)) {
		// There's no way to ask for the system-wide fixed pitch font, so
		// we use 10pt Monaco since it's the default for TextEdit.
		NSFont *const font = [NSFont fontWithName:@"Monaco" size:10.0f];
		if(font)
#if __has_feature(objc_arc)
			_textView.font = font;
#else
			[textView setFont:font];
#endif
	}
}

//	MARK: - NSWindowController

- (void)windowDidLoad
{
#if __has_feature(objc_arc)
	[_paneControl sizeToFit];
	[_paneControl removeFromSuperview];
	if([_paneControl respondsToSelector:@selector(setSegmentStyle:)])
		_paneControl.segmentStyle = NSSegmentStyleTexturedRounded;
#else
	[paneControl sizeToFit];
	[paneControl retain];
	[paneControl removeFromSuperview];
	if([paneControl respondsToSelector:@selector(setSegmentStyle:)])
		[paneControl setSegmentStyle:NSSegmentStyleTexturedRounded];
#endif

#if __has_feature(objc_arc)
	NSToolbar *const toolbar = [[NSToolbar alloc] initWithIdentifier:@"PGAboutBoxControllerToolbar"];
#else
	NSToolbar *const toolbar = [[(NSToolbar *)[NSToolbar alloc] initWithIdentifier:@"PGAboutBoxControllerToolbar"] autorelease];
#endif
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;
	toolbar.sizeMode = NSToolbarSizeModeRegular;
	[toolbar setAllowsUserCustomization:NO];
	toolbar.delegate = self;
	self.window.toolbar = toolbar;
	[self.window setShowsToolbarButton:NO];
	[self.window center];
	[self changePane:nil];
	[super windowDidLoad];
}

//	MARK: - NSObject

- (instancetype)init
{
	if((self = [super initWithWindowNibName:@"PGAbout"])) {
#if __has_feature(objc_arc)
		if(PGSharedAboutBoxController) {
			self = nil;
			return PGSharedAboutBoxController;
		} else PGSharedAboutBoxController = self;
#else
		if(PGSharedAboutBoxController) {
			[self release];
			return [PGSharedAboutBoxController retain];
		} else PGSharedAboutBoxController = [self retain];
#endif
	}
	return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[paneControl release];
	[super dealloc];
}
#endif

//	MARK: - <NSToolbarDelegate>

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)flag
{
	NSParameterAssert(PGEqualObjects(ident, PGPaneItemKey));
#if __has_feature(objc_arc)
	NSToolbarItem *const item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
	item.view = _paneControl;
	item.minSize = _paneControl.frame.size;
#else
	NSToolbarItem *const item = [[[NSToolbarItem alloc] initWithItemIdentifier:ident] autorelease];
	[item setView:paneControl];
	[item setMinSize:[paneControl frame].size];
#endif
	return item;
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return @[NSToolbarFlexibleSpaceItemIdentifier, PGPaneItemKey, NSToolbarFlexibleSpaceItemIdentifier];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

//	MARK: - <NSWindowDelegate>

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame
{
	return [window PG_zoomedFrame];
}

@end
