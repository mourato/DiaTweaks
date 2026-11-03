#import "StdPatch/StdPatch.h"

static BOOL DPIsRecentTabsButton(NSView *view) { return DPHasLabel(view, @"Recent tabs"); }

DP_PATCH(DPHideRecentTabsButton) {
    .key = @"hideRecentTabsButton",
    .order = 80,
    .title = @"Hide recent tabs button",
    .detail = @"Hide the recent tabs button in the tab bar or sidebar.",
    .symbol = @"clock.arrow.circlepath",
    .tint = @"systemPinkColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaSidebarFooter, DPDiaTabStripController),
    .hides = DPIsRecentTabsButton,
};
