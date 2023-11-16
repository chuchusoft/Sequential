//
//	PGFullSizeContentTitlebarAccessoryViewController.m
//
//	Created on 2023/11/14.
//

#import "PGFullSizeContentTitlebarAccessoryViewController.h"

@interface PGFullSizeContentTextFieldCell : NSTextFieldCell
@end

@implementation PGFullSizeContentTextFieldCell

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	if(self.drawsBackground) {
		//	when in full-size content mode, clip the drawing to just the text
		//	itself (with a small margin) and not the entire cellFrame
		NSSize size = self.attributedStringValue.size;
//NSLog(@"-drawInteriorWithFrame: size = (%5.2f, %5.2f) cellFrame.size = (%5.2f, %5.2f)",
//size.width, size.height, cellFrame.size.width, cellFrame.size.height);
		#define MARGIN 4.0f
		NSRect r = NSMakeRect(MAX(NSMinX(cellFrame), NSMaxX(cellFrame) - size.width - MARGIN),
								cellFrame.origin.y, size.width + MARGIN, cellFrame.size.height);
		NSRectClip(r);
	}

	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end

//	MARK: -
@interface PGFullSizeContentButtonCell : NSButtonCell
@end

@implementation PGFullSizeContentButtonCell

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	//	draw blue/gray circle
	#define STROKE_WIDTH 0.5f
	#define HALF_STROKE_WIDTH (STROKE_WIDTH * 0.5f)
	NSBezierPath *const path = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(
								cellFrame, HALF_STROKE_WIDTH, HALF_STROKE_WIDTH)];
	BOOL const isEnabled = self.isEnabled;
	if(isEnabled)
		[[NSColor.systemBlueColor highlightWithLevel:0.15f] set];
	else
		[[NSColor.systemGrayColor highlightWithLevel:0.70f] set];
	[path fill];

	if(isEnabled)
		[[NSColor.systemBlueColor highlightWithLevel:0.00f] set];
	else
		[[NSColor.systemGrayColor highlightWithLevel:0.35f] set];
	path.lineWidth = STROKE_WIDTH;
	[path stroke];

	//	only draw chevron (as text) when the mouse is hovering over the view/cell
	NSPoint const windowMouseLocation = [controlView.window convertPointFromScreen:NSEvent.mouseLocation];
	NSPoint const viewMouseLocation = [controlView convertPoint:windowMouseLocation fromView:nil];
//NSLog(@"viewMouseLocation (%5.2f, %5.2f) - cellFrame (%5.2f, %5.2f) - [%5.2f x %5.2f]",
//	viewMouseLocation.x, viewMouseLocation.y, cellFrame.origin.x, cellFrame.origin.y,
//	cellFrame.size.width, cellFrame.size.height);
	if(NSPointInRect(viewMouseLocation, cellFrame))
		[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end

//	MARK: -
@interface PGFullSizeContentTitlebarAccessoryViewController ()

#if !__has_feature(objc_arc)
{
	NSObject<PGFullSizeContentTitlebarAccessoryViewDelegate> *_delegate;
	IBOutlet NSButton *_toggleButton;
}
#endif

@property (nonatomic, weak) IBOutlet NSButton *toggleButton;

@end

@implementation PGFullSizeContentTitlebarAccessoryViewController

/* - (void)viewDidLoad {
	[super viewDidLoad];
	// Do view setup here.
} */

- (NSInteger)toggleButtonIntegerValue {
	return self.toggleButton.integerValue;
}

- (void)setToggleButtonIntegerValue:(NSInteger)value {
	self.toggleButton.integerValue = value;
}

- (BOOL)isToggleButtonEnabled {
	return self.toggleButton.isEnabled;
}

- (void)setToggleButtonEnabled:(BOOL)enabled {
	self.toggleButton.enabled = enabled;
}

- (IBAction)toggleFullSizeContent:(id)sender {
	NSButton *button = sender;
	[self.delegate fullSizeContentTitlebarAccessoryViewWasToggled:0 != button.intValue];
}

@end
