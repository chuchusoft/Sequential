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
#import "PGDocumentWindow.h"

// Views
//#import "PGBezelPanel.h"
#import "PGDragHighlightView.h"

#if __has_feature(objc_arc)
@interface PGDocumentWindow ()
@property (nonatomic, strong) PGBezelPanel *dragHighlightPanel;
@end
#endif

//	MARK: -
@implementation PGDocumentWindow

//	MARK: - <NSDraggingDestination>

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
	NSDragOperation const op = [(id<PGDocumentWindowDelegate>)[self delegate] window:self dragOperationForInfo:sender];
	if(NSDragOperationNone == op) return NSDragOperationNone;
#if __has_feature(objc_arc)
	_dragHighlightPanel = [PGDragHighlightView PG_bezelPanel];
#else
	_dragHighlightPanel = [[PGDragHighlightView PG_bezelPanel] retain];
#endif
	[_dragHighlightPanel displayOverWindow:self];
	return op;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender
{
#if __has_feature(objc_arc)
	[_dragHighlightPanel fadeOut];
#else
	[[_dragHighlightPanel autorelease] fadeOut];
#endif
	_dragHighlightPanel = nil;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
	[self draggingExited:nil];
	return [(id<PGDocumentWindowDelegate>)[self delegate] window:self performDragOperation:sender];
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)sender
{
	[self draggingExited:nil];
}

//	MARK: - NSWindow

- (void)close
{
//	NSDisableScreenUpdates();	2021/07/21 deprecated
	for(NSWindow *const childWindow in [self childWindows])
		[childWindow close];
	[super close];
//	NSEnableScreenUpdates();	2021/07/21 deprecated
}

//	MARK: - NSObject

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_dragHighlightPanel release];
	[super dealloc];
}
#endif

@end

//	MARK: -
@implementation NSObject(PGDocumentWindowDelegate)

- (NSDragOperation)window:(PGDocumentWindow *)window dragOperationForInfo:(id<NSDraggingInfo>)info
{
	return NSDragOperationNone;
}
- (BOOL)window:(PGDocumentWindow *)window performDragOperation:(id<NSDraggingInfo>)info
{
	return NO;
}

@end
