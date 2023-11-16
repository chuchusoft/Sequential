//
//	PGFullSizeContentTitlebarAccessoryViewController.h
//
//	Created on 2023/11/14.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PGFullSizeContentTitlebarAccessoryViewDelegate;

@interface PGFullSizeContentTitlebarAccessoryViewController :
	NSTitlebarAccessoryViewController

@property (nonatomic, weak) NSObject<PGFullSizeContentTitlebarAccessoryViewDelegate> *delegate;

@property (nonatomic, assign) NSInteger toggleButtonIntegerValue;
@property (nonatomic, assign, getter=isToggleButtonEnabled) BOOL toggleButtonEnabled;

@end

//	MARK: -
@protocol PGFullSizeContentTitlebarAccessoryViewDelegate <NSObject>

@required
- (void)fullSizeContentTitlebarAccessoryViewWasToggled:(BOOL)setting;

@end

NS_ASSUME_NONNULL_END
