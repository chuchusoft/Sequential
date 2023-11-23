//
//	PGFullSizeContentController.h
//
//	Created on 2023/11/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSWindow;
@class NSTextField;

@interface PGFullSizeContentController : NSObject

- (instancetype)initWithWindow:(NSWindow *)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)toggleFullSizeContent;

@property (readonly, nullable) NSTextField *accessoryTextField;

@end

//	MARK: -

//	With the window passed to -[PGFullSizeContentController initWithWindow:],
//	its child windows are checked whether any conform to this protocol. If
//	so, when the parent window is being transitioned to/from fullsize-content
//	mode, the child window is invoked when the animation begins and ends.
@protocol PGFullSizeContentDelegate <NSObject>

@required
- (void)fullSizeContentController:(PGFullSizeContentController *)controller
			   willStartAnimating:(NSWindow *)window;
- (void)fullSizeContentController:(PGFullSizeContentController *)controller
			   didFinishAnimating:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
