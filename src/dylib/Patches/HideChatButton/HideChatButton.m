#import "StdPatch/StdPatch.h"

static BOOL DPIsChatButton(NSView *view) { return DPHasLabel(view, @"Chat with this tab"); }

DP_PATCH(DPHideChatButton) {
    .key = @"hideChatButton",
    .order = 60,
    .title = @"Hide Chat button",
    .detail = @"Hide the Chat button at the top right of the toolbar.",
    .symbol = @"bubble.fill",
    .tint = @"systemPurpleColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaToolbar),
    .disabledBy = @"hideToolbar",
    .hides = DPIsChatButton,
};
