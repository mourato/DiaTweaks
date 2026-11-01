#import "StdPatch/StdPatch.h"

// One class in the tab bar, another in the sidebar.
static BOOL DPIsChatsButton(NSView *view) { return DPIsKind(view, DPDiaLibraryButton) || DPIsKind(view, DPDiaLibraryCell); }

DP_PATCH(DPHideChatsButton) {
    .key = @"hideChatsButton",
    .order = 70,
    .title = @"Hide Chats button",
    .detail = @"Hide the Chats button in the tab bar or sidebar.",
    .symbol = @"doc.plaintext",
    .tint = @"systemTealColor",
    .section = @"Sidebar and tab bar",
    .classes = DPClasses(DPDiaLibraryButton, DPDiaLibraryCell),
    .hides = DPIsChatsButton,
};
