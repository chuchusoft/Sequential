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
#import "PGGeometryTypes.h"

@interface PGInfoView : NSView
{
	@private
	NSString *_stringValue;
	NSUInteger _index;
	NSUInteger _count;
	NSUInteger _currentFolderIndex;	//	2023/10/01 added
	NSUInteger _currentFolderCount;	//	2023/10/01 added
	PGRectCorner _originCorner;
}

@property(readonly) NSAttributedString *attributedStringValue;
@property(copy, nonatomic) NSString *stringValue;
@property(assign, nonatomic) NSUInteger index;
@property(assign, nonatomic) NSUInteger count;
@property(assign, nonatomic) NSUInteger currentFolderIndex;	//	2023/10/01 added
@property(assign, nonatomic) NSUInteger currentFolderCount;	//	2023/10/01 added
@property(readonly) BOOL showsProgressBar;
@property(assign, nonatomic) PGRectCorner originCorner;

@end