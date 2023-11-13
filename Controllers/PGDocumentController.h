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
@class PGDocument;
@class PGResourceIdentifier;
@class PGBookmark;

// Controllers
@class PGDisplayController;
#if !__has_feature(objc_arc)
@class PGFullscreenController;
@class PGInspectorPanelController;
@class PGTimerPanelController;
@class PGActivityPanelController;
#endif

//	general prefs pane
extern NSString *const PGBackgroundColorSourceKey;	//	2023/08/17
extern NSString *const PGBackgroundColorKey;
extern NSString *const PGBackgroundPatternKey;
extern NSString *const PGBackgroundColorUsedInFullScreenKey;	//	2023/08/14

extern NSString *const PGAntialiasWhenUpscalingKey;
extern NSString *const PGImageScaleConstraintKey;

extern NSString *const PGEscapeKeyMappingKey;
extern NSString *const PGDimOtherScreensKey;

//	thumbnail prefs pane
extern NSString *const PGShowThumbnailImageNameKey;	//	2023/10/01 added
extern NSString *const PGShowThumbnailImageSizeKey;	//	2023/10/01 added
extern NSString *const PGShowThumbnailContainerNameKey;	//	2023/10/01 added
extern NSString *const PGShowThumbnailContainerChildCountKey;	//	2023/10/01 added
extern NSString *const PGShowThumbnailContainerChildSizeTotalKey;	//	2023/10/01 added
extern NSString *const PGThumbnailSizeFormatKey;	//	2023/10/01 added

//extern NSString *const PGShowFileNameOnImageThumbnailKey;	//	2022/10/15 added; 2023/10/01 removed
//extern NSString *const PGShowCountsAndSizesOnContainerThumbnailKey;	//	2022/10/15 added; 2023/09/11 removed
//extern NSString *const PGThumbnailContainerLabelTypeKey;	//	2023/09/11

//	navigation prefs pane
extern NSString *const PGMouseClickActionKey;
extern NSString *const PGBackwardsInitialLocationKey;

enum {
	PGNextPreviousAction = 0,
	PGLeftRightAction    = 1,
	PGRightLeftAction    = 2
};
enum {
	PGFullscreenMapping = 0,
	PGQuitMapping       = 1
};
enum {
	PGScaleFreely = 0,
	PGDownscaleOnly = 1,
	PGUpscaleOnly = 2,
};
typedef NSUInteger PGImageScaleConstraint;

#define PGScaleMax 16.0f
#define PGScaleMin (1.0f / 16.0f)

@class PGDisplayableIdentifier;	//	2023/10/29 to specify static type

@interface PGDocumentController :
	NSResponder <NSApplicationDelegate, NSMenuDelegate>
#if !__has_feature(objc_arc)
{
	@private
	IBOutlet NSMenu *orientationMenu;

	IBOutlet NSMenuItem *toggleFullscreen;
	IBOutlet NSMenuItem *zoomIn;
	IBOutlet NSMenuItem *zoomOut;
	IBOutlet NSMenuItem *scaleSliderItem;
	IBOutlet NSSlider *scaleSlider;

	IBOutlet NSMenuItem *pageMenuItem;
	IBOutlet NSMenu *defaultPageMenu;

	IBOutlet NSMenu *windowsMenu;
	IBOutlet NSMenuItem *windowsMenuSeparator;
	IBOutlet NSMenuItem *selectPreviousDocument;
	IBOutlet NSMenuItem *selectNextDocument;

	NSArray<PGDisplayableIdentifier*> *_recentDocumentIdentifiers;	//	2023/10/29 specified static type
	BOOL _fullscreen;

	PGDocument *_currentDocument;
	NSMutableArray<__kindof PGDocument*> *_documents;	//	2023/10/29 specified static type
	PGFullscreenController *_fullscreenController;
	BOOL _inFullscreen;

	PGInspectorPanelController *_inspectorPanel;
	PGTimerPanelController *_timerPanel;
	PGActivityPanelController *_activityPanel;

//	NSMutableDictionary *_classesByExtension;	2023/10/29 not used; removed
}
#endif

+ (PGDocumentController *)sharedDocumentController;

- (IBAction)orderFrontStandardAboutPanel:(id)sender;
- (IBAction)showPreferences:(id)sender;
- (IBAction)switchToFileManager:(id)sender;

- (IBAction)open:(id)sender;
- (IBAction)openURL:(id)sender;
- (IBAction)openRecentDocument:(id)sender;
- (IBAction)clearRecentDocuments:(id)sender;
- (IBAction)closeAll:(id)sender;

- (IBAction)toggleInspector:(id)sender;
- (IBAction)toggleTimer:(id)sender;
- (IBAction)toggleActivity:(id)sender;
- (IBAction)selectPreviousDocument:(id)sender;
- (IBAction)selectNextDocument:(id)sender;
- (IBAction)activateDocument:(id)sender;

- (IBAction)showKeyboardShortcuts:(id)sender;

- (BOOL)performEscapeKeyAction;
- (BOOL)performZoomIn;
- (BOOL)performZoomOut;
- (BOOL)performToggleFullscreen;

#if __has_feature(objc_arc)

@property (nonatomic, copy) NSArray<PGDisplayableIdentifier*> *recentDocumentIdentifiers;	//	2023/10/29 specified static type
@property (readonly) NSUInteger maximumRecentDocumentCount;
@property (readonly) PGDisplayController *displayControllerForNewDocument;
@property (nonatomic, assign, getter = isFullscreen) BOOL fullscreen;
@property (readonly) BOOL canToggleFullscreen;
@property (nonatomic, assign) BOOL usesEntireScreenWhenInFullScreen;	//	2023/08/14 added
@property (readonly) BOOL canToggleUsesEntireScreenWhenInFullScreen;	//	2023/08/14 added
@property (readonly, copy) NSArray *documents;
@property (readonly) NSMenu *scaleMenu;
@property (nonatomic, weak) IBOutlet NSSlider *scaleSlider;
@property (readonly, strong) IBOutlet NSMenu *defaultPageMenu;
@property (nonatomic, weak) PGDocument *currentDocument;
@property (readonly) BOOL pathFinderRunning;

#else

@property(copy, nonatomic) NSArray<PGDisplayableIdentifier*> *recentDocumentIdentifiers;	//	2023/10/29 specified static type
@property(readonly) NSUInteger maximumRecentDocumentCount;
@property(readonly) PGDisplayController *displayControllerForNewDocument;
@property(assign, nonatomic, getter = isFullscreen) BOOL fullscreen;
@property(readonly) BOOL canToggleFullscreen;
@property(assign, nonatomic) BOOL usesEntireScreenWhenInFullScreen;	//	2023/08/14 added
@property(readonly) BOOL canToggleUsesEntireScreenWhenInFullScreen;	//	2023/08/14 added
@property(readonly, copy) NSArray *documents;
@property(readonly) NSMenu *scaleMenu;
@property(readonly) NSSlider *scaleSlider;
@property(readonly) NSMenu *defaultPageMenu;
@property(assign, nonatomic) PGDocument *currentDocument;
@property(readonly) BOOL pathFinderRunning;

#endif

- (void)addDocument:(PGDocument *)document;
- (void)removeDocument:(PGDocument *)document;
- (PGDocument *)documentForIdentifier:(PGResourceIdentifier *)ident;
- (PGDocument *)next:(BOOL)flag documentBeyond:(PGDocument *)document;
- (NSMenuItem *)windowsMenuItemForDocument:(PGDocument *)document;

- (id)openDocumentWithContentsOfIdentifier:(PGResourceIdentifier *)ident display:(BOOL)flag;
- (id)openDocumentWithContentsOfURL:(NSURL *)URL display:(BOOL)flag;
- (id)openDocumentWithBookmark:(PGBookmark *)aBookmark display:(BOOL)flag;
- (void)noteNewRecentDocument:(PGDocument *)document;
- (void)noteDeletedRecentDocument:(PGDocument *)document;

- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;

- (void)recentDocumentIdentifierDidChange:(NSNotification *)aNotif;

@end
