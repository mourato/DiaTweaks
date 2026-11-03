#import "StdPatch/StdPatch.h"

extern DPPatch DPHideTrafficLights;
static char DPLightsKey;

static BOOL DPIsTrafficLights(NSView *view) { return DPIsKind(view, DPDiaTrafficLights); }

// The header's stack keeps room for hidden views. Out of the stack, the lights aren't subviews, so the header holds them.
static void DPSidebarHeader_layout(NSView *self, SEL _cmd) {
    NSView *lights = DPFindView(self, ^BOOL(NSView *view) { return DPIsTrafficLights(view); });
    if (lights) DPSet(self, &DPLightsKey, @[ lights, lights.superview ]);
    NSArray *held = DPGet(self, &DPLightsKey);
    NSStackView *stack = held.lastObject;
    if ([stack isKindOfClass:NSStackView.class])
        [stack setVisibilityPriority:DPHideTrafficLights.on ? NSStackViewVisibilityPriorityNotVisible : NSStackViewVisibilityPriorityMustHold forView:held.firstObject];
    DPCallOriginal(DPSidebarHeader_layout, self);
}

static void DPInstallHideTrafficLights(void) { DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPSidebarHeader_layout); }

DP_PATCH(DPHideTrafficLights) {
    .key = @"hideTrafficLights",
    .order = 92,
    .title = @"Hide traffic lights",
    .detail = @"Hide the close, minimize and zoom buttons. ⌘W, ⌘M and the Window menu still work.",
    .symbol = @"circle.circle",
    .tint = @"systemRedColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaTrafficLights, DPDiaSidebarHeader),
    .hides = DPIsTrafficLights,
    .install = DPInstallHideTrafficLights,
};
