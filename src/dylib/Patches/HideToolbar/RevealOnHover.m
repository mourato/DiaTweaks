#import "HideToolbar.h"

static void DPApplyReveal(DPPatch *patch) { DPRelayoutPanes(); }

static NSString *DPVerifyRevealToolbar(DPPatch *patch) {
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        BOOL watching = patch->on && DPHideToolbar.on && !hover.inPlace && bar && !bar.hiddenOrHasHiddenAncestor;
        if ((hover.tracking != nil) != watching) return watching ? @"nothing watches the top of the page" : @"still watching the top of the page";
        if (watching && !hover.revealed && bar.alphaValue > 0.01) return @"toolbar shows while the pointer is away";
    }
    return nil;
}

DP_PATCH(DPRevealToolbarOnHover) {
    .key = @"revealToolbarOnHover",
    .order = 40,
    .title = @"Reveal toolbar on hover",
    .detail = @"Show the hidden toolbar while the pointer is at the top of the page.",
    .symbol = @"cursorarrow",
    .tint = @"systemTealColor",
    .requires = @"hideToolbar",
    .apply = DPApplyReveal,
    .verify = DPVerifyRevealToolbar,
};
