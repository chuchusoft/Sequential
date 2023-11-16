//
//	PGFullSizeContentController.h
//
//	Created on 2023/11/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSWindow;

@interface PGFullSizeContentController : NSObject

- (instancetype)initWithWindow:(NSWindow *)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)toggleFullSizeContent;

@property (readonly, nullable) NSTextField *accessoryTextField;

@end

NS_ASSUME_NONNULL_END
