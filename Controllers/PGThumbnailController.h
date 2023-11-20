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

// Views
@class PGBezelPanel;
#import "PGThumbnailBrowser.h"

// Controllers
#import "PGDisplayController.h"

// Other Sources
#import "PGGeometryTypes.h"

extern NSString *const PGThumbnailControllerContentInsetDidChangeNotification;

@interface PGThumbnailController : NSObject <NSWindowDelegate,
	PGThumbnailBrowserDataSource, PGThumbnailBrowserDelegate, PGThumbnailViewDataSource>
#if !__has_feature(objc_arc)
{
	@private
	PGBezelPanel *_window;			//	retains; owns the reference
	PGThumbnailBrowser *_browser;	//	references; does not own the reference

	PGDisplayController *_displayController;	//	references; does not own the reference; backs the displayController @property
	PGDocument *_document;			//	references; does not own the reference; backs the document @property

	BOOL _selfRetained;

	PGBezelPanel *_infoWindow;		//	retains; owns the reference; 2023/10/02 added
	NSView *_infoView;	//	references; does not own the reference; 2023/10/02 added [PGThumbnailInfoView]
}
#endif

+ (BOOL)canShowThumbnailsForDocument:(PGDocument *)aDoc;
+ (BOOL)shouldShowThumbnailsForDocument:(PGDocument *)aDoc;

#if __has_feature(objc_arc)
@property (nonatomic, weak) PGDisplayController *displayController;
@property (nonatomic, weak) PGDocument *document;
@property (readonly) PGInset contentInset;
@property (nonatomic, copy) NSSet *selectedNodes;	//	2023/10/02 was readonly
#else
@property(assign, nonatomic) PGDisplayController *displayController;
@property(assign, nonatomic) PGDocument *document;
@property(readonly) PGInset contentInset;
@property(copy, nonatomic) NSSet *selectedNodes;	//	2023/10/02 was readonly
#endif

- (void)selectAll;
- (void)display;
- (void)selectionNeedsDisplay;
- (void)fadeOut;

- (void)displayControllerActiveNodeDidChange:(NSNotification *)aNotif;
- (void)displayControllerActiveNodeWasRead:(NSNotification *)aNotif;
- (void)clipViewBoundsDidChange:(NSNotification *)aNotif;
- (void)parentWindowDidResize:(NSNotification *)aNotif;
- (void)parentWindowWillEnterFullScreenToScreenFrame:(NSRect)parentWindowFrame;
//- (void)parentWindowWillExitFullScreenToScreenFrame:(NSRect)parentWindowFrame;
- (void)parentWindowWillBeginSheet:(NSNotification *)aNotif;
- (void)parentWindowDidEndSheet:(NSNotification *)aNotif;

- (void)documentNodeThumbnailDidChange:(NSNotification *)aNotif;
- (void)documentBaseOrientationDidChange:(NSNotification *)aNotif;
- (void)documentSortedNodesDidChange:(NSNotification *)aNotif;
- (void)documentNodeIsViewableDidChange:(NSNotification *)aNotif;

@end

//	MARK: -
@interface PGDisplayController(PGThumbnailControllerCallbacks)

- (void)thumbnailPanelDidBecomeKey:(NSNotification *)aNotif;
- (void)thumbnailPanelDidResignKey:(NSNotification *)aNotif;

@end
