#import "StdPatch/Hide.h"

static BOOL DPIsPinnedTabOutline(NSView *view) { return DPIsKind(view, DPDiaPinnedTabOutline); }

// The outline sits inside each pinned tab, deeper than the bars hide patches search.
static void DPPinnedTab_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPPinnedTab_layout, self);
}

static void DPInstallHidePinnedTabBorder(void) { DPHook(DPDiaPinnedTab, @selector(layout), (IMP)DPPinnedTab_layout); }

DP_PATCH(DPHidePinnedTabBorder) {
    .key = @"hidePinnedTabBorder",
    .order = 82,
    .title = @"Hide pinned tab border",
    .detail = @"Remove the colored border around the selected pinned tab.",
    .symbol = @"square.dashed",
    .tint = @"systemIndigoColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaPinnedTab, DPDiaPinnedTabOutline),
    .hides = DPIsPinnedTabOutline,
    .install = DPInstallHidePinnedTabBorder,
};
