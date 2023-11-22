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

// Controllers
@class PGDisplayController;

typedef enum PGFloatingPanelToggleInstruction {
	PGFloatingPanelToggleInstructionHide = 0,
	PGFloatingPanelToggleInstructionDoNothing = 1,
	PGFloatingPanelToggleInstructionShowAtStatusWindowLevel = 2,
} PGFloatingPanelToggleInstruction;

@interface PGFloatingPanelController : NSWindowController
#if !__has_feature(objc_arc)
{
	@private
	BOOL _shown;
	PGDisplayController *_displayController;
}

@property(readonly, getter = isShown) BOOL shown;
- (PGDisplayController *)displayController;
// For overriding:
@property(readonly) NSString *nibName;
//@property(readonly) NSString *windowFrameAutosaveName;	2021/07/21 deprecated
#else
@property (nonatomic, assign, getter = isShown) BOOL shown;
@property (readonly) PGDisplayController *displayController;
#endif
- (void)toggleShown;
- (void)toggleShownUsing:(PGFloatingPanelToggleInstruction)i;

//	this was -(BOOL)setDisplayController: but that signature is non-standard
//	(because it returns a BOOL), and produces an error when compiling under
//	ARC, so use a similarly-named method:
- (BOOL)setDisplayControllerReturningWasChanged:(PGDisplayController *)controller;

@end

@protocol PGFloatingPanelProtocol
@required
- (void)windowWillShow;
- (void)windowWillClose;
@end
