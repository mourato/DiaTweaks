#import "HideToolbar.h"

static void DPApplyShowWithSidebar(DPPatch *patch) { DPRelayoutPanes(); }

DP_PATCH(DPShowToolbarWithSidebar) {
    .key = @"showToolbarWithSidebar",
    .order = 45,
    .title = @"Show toolbar with the sidebar",
    .detail = @"Bring the hidden toolbar back while the sidebar is open, and hide it again when the sidebar closes.",
    .symbol = @"sidebar.left",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .apply = DPApplyShowWithSidebar,
    .verify = DPVerifyKeptInPlace,
};
