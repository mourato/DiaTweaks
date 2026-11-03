#import "StdPatch/StdPatch.h"

extern DPPatch DPQuietDownloads;

static __weak NSView *DPPressed;  // by VoiceOver or Full Keyboard Access, until the run loop comes round

static BOOL DPButton_press(NSView *self, SEL _cmd) {
    DPPressed = self;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPressed = nil; });
    return DPCallOriginal(DPButton_press, self);
}

// Dia opens the list as a download starts, often while the page's link click is still the current event.
static BOOL DPAskedFor(NSView *anchor) {
    if ([DPPressed isDescendantOf:anchor] || [anchor isDescendantOf:DPPressed]) return YES;
    NSEvent *event = NSApp.currentEvent;
    if (event.window != anchor.window || (event.type != NSEventTypeLeftMouseDown && event.type != NSEventTypeLeftMouseUp)) return NO;
    NSView *clicked = [anchor.window.contentView.superview hitTest:event.locationInWindow];  // the frame view has no superview
    return [clicked isDescendantOf:anchor] || [anchor isDescendantOf:clicked];
}

static Class DPDownloadsMenu;

static void DPPopover_show(NSPopover *self, SEL _cmd, NSRect rect, NSView *anchor, NSRectEdge edge) {
    if (DPQuietDownloads.on && [self.contentViewController isKindOfClass:DPDownloadsMenu] && !DPAskedFor(anchor)) return;
    DPCallOriginal(DPPopover_show, self, rect, anchor, edge);
}

static void DPInstallQuietDownloads(void) {
    DPDownloadsMenu = objc_getClass(DPDiaDownloadsMenu);
    DPHookClass(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:), (IMP)DPPopover_show);
    DPHook(DPDiaDownloadsButton, @selector(accessibilityPerformPress), (IMP)DPButton_press);
    DPHook(DPDiaTabSurfaceButton, @selector(accessibilityPerformPress), (IMP)DPButton_press);
}

DP_PATCH(DPQuietDownloads) {
    .key = @"quietDownloads",
    .order = 95,
    .title = @"Don't pop up downloads",
    .detail = @"Stops the downloads list opening by itself each time a download starts. The downloads button still shows progress, and clicking it opens the list.",
    .symbol = @"arrow.down.circle",
    .tint = @"systemOrangeColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaDownloadsMenu, DPDiaDownloadsButton, DPDiaTabSurfaceButton),
    .install = DPInstallQuietDownloads,
};
