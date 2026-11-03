#import "Patches/HideToolbar/HideToolbar.h"

@interface DPToolbarHover (TestReset)
- (void)reset;
@end

DPPatch DPHideToolbar, DPRevealToolbarOnHover;
DPPatch DPShowToolbarWithSidebar, DPShowToolbarOnNewTab;
static BOOL inPeek;
BOOL DPInPeek(NSView *view) { return inPeek; }
const CGFloat DPPeekHeaderHeight = 36;
BOOL DPBesideSidebar(NSView *container) { return NO; }
static NSUInteger frameWrites, alphaWrites;
@interface CountingView : NSView
@end
@implementation CountingView
- (void)setFrame:(NSRect)rect { frameWrites++; [super setFrame:rect]; }
- (void)setAlphaValue:(CGFloat)value { alphaWrites++; [super setAlphaValue:value]; }
@end
@interface FlippedPane : NSView
@end
@implementation FlippedPane
- (BOOL)isFlipped { return YES; }
@end

// Cover both coordinate systems and a bookmarks bar while changing visibility and resizing.
static void checkGeometry(BOOL flipped, BOOL bookmarks) {
    CGFloat top = flipped ? 0 : 750, pageY = flipped ? 50 : 0;
    NSView *pane = [[(flipped ? FlippedPane.class : NSView.class) alloc] initWithFrame:NSMakeRect(0, 0, 1000, 800)];
    NSView *bar = [[objc_getClass(DPDiaToolbar) alloc] initWithFrame:NSMakeRect(0, top, 1000, 50)];
    NSView *marks = [[objc_getClass(DPDiaBookmarksBar) alloc] initWithFrame:NSMakeRect(0, flipped ? 50 : 725, 1000, 25)];
    NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, pageY + (flipped && bookmarks ? 25 : 0), 1000, 750 - (bookmarks ? 25 : 0))];
    NSView *web = [[NSView alloc] initWithFrame:page.bounds];
    [page addSubview:web]; [pane addSubview:bar]; if (bookmarks) [pane addSubview:marks]; [pane addSubview:page];
    NSRect original = page.frame;
    DPHideToolbar.on = YES; DPHideToolbar.progress = 1; DPApplyToolbar(pane);
    NSCAssert(NSEqualRects(page.frame, pane.bounds), @"hidden bars release their space");
    DPToolbarHover *hover = [DPToolbarHover forPane:pane];
    hover.revealed = YES; hover.progress = 0.4; DPApplyToolbar(pane);
    NSCAssert(NSEqualRects(page.frame, pane.bounds), @"revealing toolbar overlays the page");
    NSCAssert(fabs(bar.alphaValue - 0.4) < 0.0001, @"toolbar fade stays identical");
    if (bookmarks) NSCAssert(marks.alphaValue == bar.alphaValue, @"bookmarks fade with toolbar");
    NSCAssert(pane.subviews.lastObject == (bookmarks ? marks : bar), @"revealed bars stay on top");
    [hover reset];
    DPHideToolbar.on = NO; DPHideToolbar.progress = 0; DPApplyToolbar(pane);
    NSCAssert(NSEqualRects(page.frame, original), @"off restores both coordinate systems");
    NSCAssert(NSEqualRects(web.frame, page.bounds), @"web frame restores with the page");
    page.frame = NSMakeRect(original.origin.x, original.origin.y, 1100, original.size.height);
    DPApplyToolbar(pane);
    NSCAssert(NSWidth(page.frame) == 1100 && NSWidth(web.frame) == 1100, @"a new Dia frame is still applied");
}

int main(void) {
    @autoreleasepool {
        Class barClass = objc_allocateClassPair(CountingView.class, DPDiaToolbar, 0);
        objc_registerClassPair(barClass);
        objc_registerClassPair(objc_allocateClassPair(CountingView.class, DPDiaBookmarksBar, 0));
        NSView *pane = [[FlippedPane alloc] initWithFrame:NSMakeRect(0, 0, 1000, 800)];
        NSView *bar = [[barClass alloc] initWithFrame:NSMakeRect(0, 0, 1000, 50)];
        NSView *page = [[CountingView alloc] initWithFrame:NSMakeRect(0, 50, 1000, 750)];
        NSView *web = [[CountingView alloc] initWithFrame:page.bounds];
        [page addSubview:web]; [pane addSubview:bar]; [pane addSubview:page];
        DPHideToolbar.on = YES; DPHideToolbar.progress = 1; DPRevealToolbarOnHover.on = YES;
        DPApplyToolbar(pane);
        NSRect expected = NSMakeRect(0, 0, 1000, 800);
        NSCAssert(NSEqualRects(page.frame, expected), @"page fills toolbar space");
        NSCAssert(NSEqualRects(web.frame, page.bounds), @"web child fills page");
        frameWrites = alphaWrites = 0;
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < 10000; i++) { @autoreleasepool { DPApplyToolbar(pane); } }
        printf("steady_layout_ms=%.3f frame_writes=%lu alpha_writes=%lu\n", (CFAbsoluteTimeGetCurrent()-start)*1000,
               (unsigned long)frameWrites, (unsigned long)alphaWrites);
        NSCAssert(NSEqualRects(page.frame, expected), @"repeated layout preserves geometry");
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        frameWrites = alphaWrites = 0; start = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < 10000; i++) { @autoreleasepool {
            hover.progress = (i % 31) / 30.0;
#ifdef DP_OPTIMIZED
            DPApplyToolbarOpacity(hover);
#else
            DPApplyToolbar(pane);
#endif
        } }
        printf("hover_ticks_ms=%.3f frame_writes=%lu alpha_writes=%lu\n", (CFAbsoluteTimeGetCurrent()-start)*1000,
               (unsigned long)frameWrites, (unsigned long)alphaWrites);
#ifdef DP_OPTIMIZED
        inPeek = YES; hover.progress = 0.5; DPApplyToolbarOpacity(hover);
        NSCAssert(bar.alphaValue == 0, @"Peek keeps the toolbar hidden during hover animation");
        inPeek = NO; DPApplyToolbarOpacity(hover);
        NSCAssert(fabs(bar.alphaValue - 0.5) < 0.0001, @"normal hover still fades the toolbar");
#endif
#ifdef DP_OPTIMIZED
        NSCAssert(frameWrites == 0, @"hover does not change layout");
        NSCAssert(fabs(bar.alphaValue - hover.progress) < 0.0001, @"same fade equation");
#endif
        DPHideToolbar.on = NO; DPHideToolbar.progress = 0; DPApplyToolbar(pane);
        NSCAssert(NSEqualRects(page.frame, NSMakeRect(0, 50, 1000, 750)), @"disable restores layout");
        NSCAssert(bar.alphaValue == 1, @"disable restores toolbar");
        for (int flipped = 0; flipped < 2; flipped++)
            for (int bookmarks = 0; bookmarks < 2; bookmarks++) checkGeometry(flipped, bookmarks);
        puts("PASS: geometry, hover opacity, stacking, reset, resize; flipped/unflipped, bookmarks on/off");
    }
}
