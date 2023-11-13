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
@class PGNode;
@class PGDisplayableIdentifier;
#if !__has_feature(objc_arc)
@class PGSubscription;
#endif

extern NSString *const PGBookmarkDidUpdateNotification;

@interface PGBookmark : NSObject <NSSecureCoding>	//	NSCoding
#if !__has_feature(objc_arc)
{
	@private
	PGDisplayableIdentifier *_documentIdentifier;
	PGSubscription *_documentSubscription;
	PGDisplayableIdentifier *_fileIdentifier;
	PGSubscription *_fileSubscription;
}
#endif

- (id)initWithNode:(PGNode *)aNode;
- (id)initWithDocumentIdentifier:(PGDisplayableIdentifier *)docIdent
				  fileIdentifier:(PGDisplayableIdentifier *)fileIdent
					 displayName:(NSString *)aString; // For backward compatibility.

#if __has_feature(objc_arc)
@property (readonly, strong) PGDisplayableIdentifier *documentIdentifier;
@property (readonly, strong) PGDisplayableIdentifier *fileIdentifier;
@property (readonly, assign) BOOL isValid;
#else
@property(readonly) PGDisplayableIdentifier *documentIdentifier;
@property(readonly) PGDisplayableIdentifier *fileIdentifier;
@property(readonly) BOOL isValid;
#endif

- (void)eventDidOccur:(NSNotification *)aNotif;
- (void)identifierDidChange:(NSNotification *)aNotif;

@end
