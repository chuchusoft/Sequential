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

extern NSString *const PGPreferenceWindowControllerBackgroundPatternColorDidChangeNotification;
extern NSString *const PGPreferenceWindowControllerBackgroundColorUsedInFullScreenDidChangeNotification;
extern NSString *const PGPreferenceWindowControllerDisplayScreenDidChangeNotification;

@interface PGPreferenceWindowController : NSWindowController<NSApplicationDelegate, NSToolbarDelegate>
#if !__has_feature(objc_arc)
{
	@private
	IBOutlet NSView *generalView;
	IBOutlet NSColorWell *customColorWell;	//	2023/08/17 added
	IBOutlet NSPopUpButton *screensPopUp;
	NSScreen *_displayScreen;

	IBOutlet NSView *thumbnailView;	//	2023/10/01 added

	IBOutlet NSView *navigationView;
	IBOutlet NSTextField *secondaryMouseActionLabel;

	IBOutlet NSView *updateView;
}
#endif

+ (id)sharedPrefController;

- (IBAction)changeDisplayScreen:(id)sender;
- (IBAction)showPrefsHelp:(id)sender;
- (IBAction)changePane:(NSToolbarItem *)sender; // Gets the pane name from [sender itemIdentifier].

#if __has_feature(objc_arc)
@property (readonly) NSColor *backgroundPatternColor;
@property (nonatomic, strong) NSScreen *displayScreen;
#else
@property(readonly) NSColor *backgroundPatternColor;
@property(retain) NSScreen *displayScreen;
#endif

@end
