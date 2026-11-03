#import "HideToolbar.h"
#import "Patches/Peek/Peek.h"

// The bar stays in Dia's layout: hiding it makes Dia reflow in ways it won't undo.
static NSView *DPToolbar_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    DPToolbarHover *hover = [DPToolbarHover forPane:self.superview];
    BOOL hidden = ((DPHideToolbar.on && hover.progress == 0 && hover.inPlaceProgress == 0) || DPInPeek(self)) && (self == hover.bar || self == hover.bookmarks);
    return hidden ? nil : DPCallOriginal(DPToolbar_hitTest, self, point);
}

static void DPPane_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPane_layout, self);
    [DPPanes addObject:self];
    DPApplyToolbar(self);
}

static void DPInstallHideToolbar(void) {
    DPPanes = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaContentPane, @selector(layout), (IMP)DPPane_layout);
    DPHook(DPDiaToolbar, @selector(hitTest:), (IMP)DPToolbar_hitTest);
    DPHook(DPDiaBookmarksBar, @selector(hitTest:), (IMP)DPToolbar_hitTest);
}

static NSString *DPVerifyHideToolbar(DPPatch *patch) {
    NSArray<NSView *> *panes = DPFindViews(DPDiaContentPane);
    if (!panes.count) return @"no toolbar found";
    for (NSView *pane in panes) {
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        if (!bar) return @"no toolbar found";
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        if (hover.progress > 0 || hover.inPlaceProgress > 0) continue;  // Revealed by the pointer, or kept in place by an option.
        NSView *bookmarks = DPBookmarksUnder(pane, bar);
        NSArray<NSView *> *bars = bookmarks ? @[bar, bookmarks] : @[bar];
        BOOL hidden = patch->on, found = NO;
        for (NSView *view in bars) {
            if (fabs(view.alphaValue - (hidden ? 0 : 1)) > 0.01) return hidden ? @"toolbar still shows" : @"toolbar is invisible";
            if (hidden && [view hitTest:NSMakePoint(NSMidX(view.frame), NSMidY(view.frame))]) return @"toolbar still takes clicks";
        }
        CGFloat edge = DPBottom(pane, DPLaidOutFrame(bars.lastObject));
        for (NSView *view in pane.subviews) {
            NSRect laidOut = DPLaidOutFrame(view);
            if ([bars containsObject:view] || view.hidden || fabs(DPTop(pane, laidOut) - edge) > 0.5) continue;
            found = YES;
            CGFloat shift = hidden ? edge - DPTop(pane, bar.frame) : 0;
            if (fabs(DPTop(pane, view.frame) - (DPTop(pane, laidOut) - shift)) > 0.5)
                return hidden ? @"page didn't move up into the toolbar's place" : @"page isn't below the toolbar";
        }
        if (!found) return @"no page found below the toolbar";
    }
    return nil;
}

DP_PATCH(DPHideToolbar) {
    .key = @"hideToolbar",
    .order = 30,
    .title = @"Hide toolbar",
    .detail = @"Remove the bar with the address, navigation buttons and extensions. Experimental.",
    .symbol = @"menubar.rectangle",
    .tint = @"systemGrayColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaContentPane, DPDiaToolbar),
    .install = DPInstallHideToolbar,
    .relayout = DPRelayoutPanes,
    .verify = DPVerifyHideToolbar,
};
