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
#import "PGURLAlert.h"

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGZooming.h"

#if __has_feature(objc_arc)

@interface PGURLAlert ()

@property (nonatomic, weak) IBOutlet NSTextField *URLField;
@property (nonatomic, weak) IBOutlet NSButton *OKButton;

@end

#endif

//	MARK: -
@implementation PGURLAlert

//	MARK: - PGURLAlert

- (IBAction)ok:(id)sender
{
	[NSApp stopModalWithCode:NSAlertFirstButtonReturn];
}
- (IBAction)cancel:(id)sender
{
	[NSApp stopModalWithCode:NSAlertSecondButtonReturn];
}

//	MARK: -

- (NSURL *)runModal
{
	BOOL const canceled = [NSApp runModalForWindow:self.window] == NSAlertSecondButtonReturn;
	[self.window close];
	if(canceled) return nil;
#if __has_feature(objc_arc)
	return [NSURL PG_URLWithString:_URLField.stringValue];
#else
	return [NSURL PG_URLWithString:URLField.stringValue];
#endif
}

//	MARK: - NSWindowController

- (void)enableOKButton
{
#if __has_feature(objc_arc)
	_OKButton.enabled = [NSURL PG_URLWithString:_URLField.stringValue] != nil;
#else
	[OKButton setEnabled:[NSURL PG_URLWithString:[URLField stringValue]] != nil];
#endif
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self enableOKButton];	//	[self controlTextDidChange:nil];	2021/07/21
}

//	MARK: - NSObject

- (instancetype)init
{
	return [self initWithWindowNibName:@"PGURL"];
}

//	MARK: - NSObject(NSControlSubclassNotifications)

- (void)controlTextDidChange:(NSNotification *)aNotification
{
	[self enableOKButton];	//	[OKButton setEnabled:[NSURL PG_URLWithString:[URLField stringValue]] != nil];	2021/07/21
}

//	MARK: - <NSWindowDelegate>

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)defaultFrame
{
	return [window PG_zoomedFrame];
}

@end
