//
//	PGFullSizeContentController.m
//
//	Created on 2023/11/15.
//

#import "PGFullSizeContentController.h"

#import "PGFullSizeContentTitlebarAccessoryViewController.h"

//	<https://stackoverflow.com/questions/12322714/changing-color-of-nswindow-title-text>
static
NSView*
FindViewInSubview(NSArray<__kindof NSView *> *subviews,
	NSView *ignoreView, BOOL(^test)(NSView *)) {
	for(NSView *v in subviews) {
		if(v == ignoreView)
			continue;

		if(test(v))
			return v;

		NSView *found = FindViewInSubview(v.subviews, ignoreView, test);
		if(found)
			return found;
	}
	return nil;
}

//	<https://stackoverflow.com/questions/12322714/changing-color-of-nswindow-title-text>
static
NSTextField*
FindTitleTextFieldInTitleBar(NSWindow *const window) {
	NSView *windowContentView = window.contentView;
	if(!windowContentView)
		return nil;

	NSView *windowContentSuperView = windowContentView.superview;
	if(!windowContentSuperView)
		return nil;

	NSView *titleView = FindViewInSubview(windowContentSuperView.subviews, windowContentView, ^(NSView *view) {
		//	the title has a tag of 0 and is a NSTextField
		return (BOOL) (0 == view.tag && [view isKindOfClass:NSTextField.class]);
	});
	if(!titleView)
		return nil;

	NSCAssert([titleView isKindOfClass:NSTextField.class], @"");
	return (NSTextField *)titleView;
}

//	MARK: -

static
void
SetAlpha(NSView *const view, BOOL visible) {
	view.alphaValue = visible ? 1.00f : 0.001f;
}

static
void
SetTextFieldBackground(NSTextField *const tf, BOOL drawsBackground) {
	tf.drawsBackground = drawsBackground;
}

static
void
SetTextFieldAlphaAndBackground(NSTextField *const tf, BOOL visible, BOOL drawsBackground) {
	SetAlpha(tf, visible);
	SetTextFieldBackground(tf, drawsBackground);

	//	the titlebar textfield is normally configured with backgroundColor = nil
	//	so a NSColor.textBackgroundColor instance must be assigned to it when
	//	in full-size content mode, and when not in full-size content mode, the
	//	backgroundColor must be reset back to nil
	tf.backgroundColor = drawsBackground ? NSColor.textBackgroundColor : nil;
}

static
void
SetAlphaAndBackgroundIfTextField(NSView *const view, BOOL visible, BOOL drawsBackground) {
	SetAlpha(view, visible);

	if([view isKindOfClass:NSTextField.class])
		SetTextFieldBackground((NSTextField *)view, drawsBackground);
}

//	MARK: -

static
NSTrackingArea * _Nullable
DeleteTrackingArea(NSTrackingArea *trackingArea, NSView *trackingView) {
	NSCAssert(nil != trackingArea, @"");
	[trackingView removeTrackingArea:trackingArea];
	#if !__has_feature(objc_arc)
	[trackingArea release];
	#endif
//	trackingArea = nil;
	return nil;
}

static const NSString *const TrackingViewKey = @"TrackingView";

static
NSTrackingArea *
CreateAndRegisterTrackingArea(NSRect rect, PGFullSizeContentController *owner,
	NSView *view, NSView *viewForUserInfo) {
	NSTrackingArea *const trackingArea = [[NSTrackingArea alloc] initWithRect:rect
		options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
		  owner:owner
	   userInfo:viewForUserInfo ? @{ TrackingViewKey:viewForUserInfo } : nil];
	[view addTrackingArea:trackingArea];
	return trackingArea;
}

//	MARK: -

@interface PGFullSizeContentController () <PGFullSizeContentTitlebarAccessoryViewDelegate>

#if !__has_feature(objc_arc)
{
	NSWindow *_window;
	NSTrackingArea *_lhsTrackingArea;
	NSTrackingArea *_midTrackingArea;
	NSTrackingArea *_rhsTrackingArea;
	PGFullSizeContentTitlebarAccessoryViewController
		*_fullSizeContentTitlebarAccessoryViewController;
}
#endif

@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, strong, nullable) NSTrackingArea *lhsTrackingArea;
@property (nonatomic, strong, nullable) NSTrackingArea *midTrackingArea;
@property (nonatomic, strong, nullable) NSTrackingArea *rhsTrackingArea;
@property (nonatomic, weak) PGFullSizeContentTitlebarAccessoryViewController
							*fullSizeContentTitlebarAccessoryViewController;

@end

//	MARK: -
@implementation PGFullSizeContentController

- (instancetype)initWithWindow:(NSWindow *)window {
	NSAssert(window, @"");
/*	if(nil == window) {
		self = nil;
		return nil;
	}	*/

	self = [super init];
	if(self) {
		_window = window;

		PGFullSizeContentTitlebarAccessoryViewController *avc =
			[PGFullSizeContentTitlebarAccessoryViewController new];
		avc.layoutAttribute = NSLayoutAttributeRight;
		avc.delegate = self;
		[window addTitlebarAccessoryViewController:avc];
		_fullSizeContentTitlebarAccessoryViewController = avc;

	/*	//	<https://stackoverflow.com/questions/12322714/changing-color-of-nswindow-title-text>
		NSTextField *titleTextField = FindTitleTextFieldInTitleBar(window);
		if(titleTextField) {
			titleTextField.attributedStringValue = [[NSAttributedString alloc]
				initWithString:window.title
					attributes:@{ NSBackgroundColorAttributeName: [NSColor.blackColor colorWithAlphaComponent:0.75f],
								  NSForegroundColorAttributeName: [NSColor.whiteColor colorWithAlphaComponent:0.75f] }];
		}	*/

		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(_windowDidEnterFullScreen:)
												   name:NSWindowDidEnterFullScreenNotification
												 object:window];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(_windowDidExitFullScreen:)
												   name:NSWindowDidExitFullScreenNotification
												 object:window];
	}

	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self
												  name:NSWindowDidEnterFullScreenNotification
												object:_window];
	[NSNotificationCenter.defaultCenter removeObserver:self
												  name:NSWindowDidExitFullScreenNotification
												object:_window];

#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

//	MARK: private methods

- (void)_windowDidEnterFullScreen:(NSNotification *)notification {
	self.fullSizeContentTitlebarAccessoryViewController.toggleButtonEnabled = NO;
}

- (void)_windowDidExitFullScreen:(NSNotification *)notification {
	self.fullSizeContentTitlebarAccessoryViewController.toggleButtonEnabled = YES;
}

- (BOOL)_isShowingFullSizeContent {
	return 0 != (NSWindowStyleMaskFullSizeContentView & self.window.styleMask);
}

- (void)_updateTrackingAreas:(BOOL)isFullSizeContentView {
	NSWindow *w = self.window;
	NSView *rhs = self.fullSizeContentTitlebarAccessoryViewController.view;
	NSTextField *titleTextField = FindTitleTextFieldInTitleBar(w);
	//	There appears to be a bug in macOS which causes the text-field to
	//	not be found (*) and when this happens, the full-size-content mode
	//	goes "wonky": the contents of the window don't resize correctly;
	//	this bug manifests when the window is resized to a height which
	//	matches the height of the visible area of the screen that the
	//	window is on (a horizontal dock must be hidden for this to occur);
	//	it sometimes occurs at smaller window height values;
	//	the only way to make the window work properly again is for the
	//	user to resize the window manually - when that is done, the window
	//	behaves properly again.
	//	The code below mitigates this problem by checking whether
	//	titleTextField is non-nil.
	//
	//	(*) the NSTextField object is not in the view hierarachy so the
	//		FindTitleTextFieldInTitleBar() function returns a nil value.
//	NSAssert(titleTextField, @"");
/* {
NSLog(@"titleTextField = %@, superview %@, superview.children.count %lu",
titleTextField, titleTextField.superview,
titleTextField.superview.subviews.count);
} */
	NSButton *documentIconButton = [w standardWindowButton:NSWindowDocumentIconButton];
/* if(documentIconButton) {
	NSLog(@"documentIconButton = %@, superview %@, superview.children.count %lu",
	documentIconButton, documentIconButton.superview,
	documentIconButton.superview.subviews.count);
	for(NSView *v in documentIconButton.superview.subviews) {
		NSLog(@"\tchild %@", v);
	}
} */

	if(isFullSizeContentView) {
		NSRect r = NSZeroRect;
		NSView *superView = nil;
		for(NSUInteger i = NSWindowCloseButton; i <= NSWindowZoomButton; ++i) {
			NSButton *button = [w standardWindowButton:i];
			SetAlpha(button, NO);

			if(nil == superView)
				superView = button.superview;
			else
				NSAssert(superView == button.superview, @"");

			NSRect br = [button convertRect:button.bounds toView:superView];
			r = NSEqualRects(r, NSZeroRect) ? br : NSUnionRect(r, br);
		}
		NSAssert(nil == _lhsTrackingArea, @"");
		_lhsTrackingArea = CreateAndRegisterTrackingArea(r, self, superView, nil);

		r = NSZeroRect;
		for(NSView *view in rhs.subviews) {
			SetAlphaAndBackgroundIfTextField(view, NO, NO);

			NSRect br = [view convertRect:view.bounds toView:rhs];
			r = NSEqualRects(r, NSZeroRect) ? br : NSUnionRect(r, br);
		}
		NSAssert(nil == _rhsTrackingArea, @"");
		_rhsTrackingArea = CreateAndRegisterTrackingArea(r, self, rhs, nil);

		if(titleTextField) {
			SetTextFieldAlphaAndBackground(titleTextField, NO, NO);
			if(documentIconButton) {
				SetAlpha(documentIconButton, NO);
				NSRect tfr = [titleTextField convertRect:titleTextField.bounds
												  toView:titleTextField.superview];
				NSRect dir = [documentIconButton convertRect:documentIconButton.bounds
													  toView:documentIconButton.superview];
				NSAssert(nil == _midTrackingArea, @"");
				_midTrackingArea = CreateAndRegisterTrackingArea(NSUnionRect(tfr, dir), self,
									titleTextField.superview, titleTextField.superview);
			} else {
				NSAssert(nil == _midTrackingArea, @"");
				_midTrackingArea = CreateAndRegisterTrackingArea(titleTextField.bounds, self,
									titleTextField, titleTextField);
			}
		}
	} else {
		for(NSUInteger i = NSWindowCloseButton; i <= NSWindowZoomButton; ++i)
			SetAlpha([w standardWindowButton:i], YES);
		_lhsTrackingArea = DeleteTrackingArea(_lhsTrackingArea,
			[w standardWindowButton:NSWindowCloseButton].superview);

		for(NSView *view in rhs.subviews)
			SetAlphaAndBackgroundIfTextField(view, YES, NO);
		_rhsTrackingArea = DeleteTrackingArea(_rhsTrackingArea, rhs);

		if(titleTextField)
			SetTextFieldAlphaAndBackground(titleTextField, YES, NO);
		if(_midTrackingArea)
			_midTrackingArea = DeleteTrackingArea(_midTrackingArea,
				[_midTrackingArea.userInfo objectForKey:TrackingViewKey]);
	}
}

- (void)_setVisibilityOfTitleBarButtonsForTrackingArea:(NSTrackingArea *)trackingArea
											   visible:(BOOL)visible {
	if(_lhsTrackingArea == trackingArea) {
		for(NSUInteger i = NSWindowCloseButton; i <= NSWindowZoomButton; ++i)
			SetAlpha([self.window standardWindowButton:i], visible);
	} else if(_rhsTrackingArea == trackingArea) {
		NSView *rhs = self.fullSizeContentTitlebarAccessoryViewController.view;
		for(NSView *view in rhs.subviews)
			SetAlphaAndBackgroundIfTextField(view, visible, visible);
	} else if(_midTrackingArea == trackingArea) {
		NSTextField *titleTextField = FindTitleTextFieldInTitleBar(self.window);
		NSAssert(titleTextField, @"");
		SetTextFieldAlphaAndBackground(titleTextField, visible, visible);
		NSButton *documentIconButton =
			[self.window standardWindowButton:NSWindowDocumentIconButton];
		if(documentIconButton)
			SetAlpha(documentIconButton, visible);
	}
}

//	MARK: <MouseTrackingDelegate>
- (void)mouseEntered:(NSEvent *)theEvent {
	[self _setVisibilityOfTitleBarButtonsForTrackingArea:theEvent.trackingArea
												 visible:YES];
}

- (void)mouseExited:(NSEvent *)theEvent {
	[self _setVisibilityOfTitleBarButtonsForTrackingArea:theEvent.trackingArea
												 visible:NO];
}

//	MARK: <FullSizeContentTitlebarAccessoryViewDelegate>
- (void)fullSizeContentTitlebarAccessoryViewWasToggled:(BOOL)setting_IGNORED {
	NSWindow *const w = self.window;
	NSRect const frame = w.frame;
	NSWindowStyleMask styleMask = w.styleMask;
	NSWindowStyleMask const isFullSizeContentView =
		NSWindowStyleMaskFullSizeContentView & styleMask;

	w.titlebarAppearsTransparent = !isFullSizeContentView;
//	w.titleVisibility = isFullSizeContentView ? NSWindowTitleVisible :
//						NSWindowTitleHidden;

	if(isFullSizeContentView) {
		//	When the styleMask is altered, AppKit tries to animate the window
		//	to a larger size which is then reduced back to the final size
		//	specified by the frame variable in the -[NSWindow setFrame:display:]
		//	call below. That larger size causes problems with the title bar's
		//	title text field getting messed up. The simplest way to work-around
		//	this problem is to reduce the frame height by 1 point before altering
		//	the styleMask. However, because this frame height change causes a
		//	weird stuttering during the frame's animation, this height change is
		//	only done when the window's height is close to the height of the
		//	screen's visible area.
		if(w.screen.visibleFrame.size.height - frame.size.height < 4.0f) {
			//	do NOT animate this call, ie, don't use [w.animator setFrame:...]
			[w setFrame:NSMakeRect(frame.origin.x, frame.origin.y,
									frame.size.width, frame.size.height - 1.0f)
				display:NO];
//NSLog(@"*** window frame's height was reduced by 1 point ***");
		}
		styleMask &= ~NSWindowStyleMaskFullSizeContentView;
	} else
		styleMask |= NSWindowStyleMaskFullSizeContentView;
	w.animator.styleMask = styleMask;

	[self _updateTrackingAreas:!isFullSizeContentView];

	//	When the window's styleMask is changed, the frame's size is altered
	//	by NSWindow. Since the point of all of this is to *just* make the
	//	titlebar disappear but not change the window's size or location,
	//	reverse the changes to the frame by restoring its value.
	//	However, when the title bar is close to the top of the screen (just
	//	under the menu bar), the animation during -setFrame: looks odd so
	//	detect that situation and if so, perform a non-animated -setFrame:.
	CGFloat const titleBarHeight = [w standardWindowButton:NSWindowCloseButton].superview.frame.size.height;
	if(isFullSizeContentView &&
		NSMaxY(w.screen.visibleFrame) - NSMaxY(frame) < titleBarHeight) {
		[w setFrame:frame display:NO];	//	the animation looks odd
//NSLog(@"-setFrame: is NOT animated (titleBarHeight %5.2f", titleBarHeight);
	} else {
		[w.animator setFrame:frame display:NO];	//	the animation looks OK
	}
}

//	MARK: public API
- (void)toggleFullSizeContent {
	//	because this call does not invoke the delegate...
	self.fullSizeContentTitlebarAccessoryViewController.toggleButtonIntegerValue =
		1 - self.fullSizeContentTitlebarAccessoryViewController.toggleButtonIntegerValue;

	//	...this call becomes necessary
	[self fullSizeContentTitlebarAccessoryViewWasToggled:!self._isShowingFullSizeContent];
}

- (NSTextField *)accessoryTextField {
	NSView *rhs = self.fullSizeContentTitlebarAccessoryViewController.view;
	for(NSView *view in rhs.subviews) {
		if([view isKindOfClass:NSTextField.class])
			return (NSTextField *)view;
	}
	return nil;
}

@end
