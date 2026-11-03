#import "StdPatch/StdPatch.h"

void DPApplyWindowMaterial(DPPatch *patch);
NSString *DPVerifyWindowMaterial(DPPatch *patch);

DP_PATCH(DPTranslucentSidebar) {
    .key = @"translucentSidebar",
    .order = 84,
    .title = @"Translucent sidebar",
    .detail = @"See the page through the sidebar when it floats over it, in the window's material, or the one picked under Window material when that's on.",
    .symbol = @"sidebar.squares.left",
    .tint = @"systemCyanColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaWindowFrame, DPDiaWindowTint, DPDiaFloatingSidebar),
    .apply = DPApplyWindowMaterial,
    .verify = DPVerifyWindowMaterial,
};
