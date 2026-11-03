// Shared by hide toolbar and its options, which only work on top of it.
#import "StdPatch/StdPatch.h"

extern DPPatch DPHideToolbar, DPRevealToolbarOnHover, DPShowToolbarWithSidebar, DPShowToolbarOnNewTab;
extern NSHashTable<NSView *> *DPPanes;  // Every content pane laid out so far.

// Shows the hidden toolbar while the pointer is at the top of a pane, or in its place while an option keeps it there. One per pane.
@interface DPToolbarHover : NSObject
@property (nonatomic, weak) NSView *pane, *bar, *bookmarks;
@property (nonatomic, strong) NSTrackingArea *tracking;
@property (nonatomic, strong) NSTimer *animation, *hideTimer, *inPlaceAnimation;
@property (nonatomic) BOOL revealed, inPlace;
@property (nonatomic) CGFloat progress, inPlaceProgress;  // How far the pointer, and an option keeping it in place, have brought the toolbar back.
+ (DPToolbarHover *)forPane:(NSView *)pane;  // nil until the pane is laid out.
+ (DPToolbarHover *)attachToPane:(NSView *)pane;
- (void)updateForBar:(NSView *)bar bookmarks:(NSView *)bookmarks;
@end

// Layout.m
NSRect DPLaidOutFrame(NSView *view);  // Where Dia put the view, before the patch moved it.
CGFloat DPTop(NSView *pane, NSRect r);  // Distances from the pane's top, whichever way it's flipped.
CGFloat DPBottom(NSView *pane, NSRect r);
NSView *DPBookmarksUnder(NSView *pane, NSView *bar);
BOOL DPKeptInPlace(NSView *pane);  // With the sidebar open, or on a new tab page, when their options are on.
NSString *DPVerifyKeptInPlace(DPPatch *patch);
void DPApplyToolbar(NSView *pane);
void DPApplyToolbarOpacity(DPToolbarHover *hover);
void DPRelayoutPanes(void);
