#import "HideToolbar.h"

static void DPApplyShowOnNewTab(DPPatch *patch) { DPRelayoutPanes(); }

DP_PATCH(DPShowToolbarOnNewTab) {
    .key = @"showToolbarOnNewTab",
    .order = 47,
    .title = @"Show toolbar on new tab pages",
    .detail = @"Keep the toolbar and bookmarks bar on new tab pages, and hide them again once a site opens.",
    .symbol = @"plus.square.on.square",
    .tint = @"systemOrangeColor",
    .requires = @"hideToolbar",
    .apply = DPApplyShowOnNewTab,
    .verify = DPVerifyKeptInPlace,
};
