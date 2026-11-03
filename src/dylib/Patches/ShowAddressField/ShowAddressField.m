#import "StdPatch/StdPatch.h"

// Dia shows the address field's background and its buttons while the field is hovered. The field's hover tracker sets
// that state from the pointer, and a delayed tracker hands it on to the field after the pointer settles. While on, this
// marks the field hovered, hands that to the field itself, and keeps the pointer's comings and goings from undoing it.

extern DPPatch DPShowAddressField;

typedef void (*DPHoverHandler)(bool hovered, void *context __attribute__((swift_context))) __attribute__((swiftcall));

static id DPDelayedTracker(NSView *field) { return (__bridge id)*(void **)DPIvar(field, "hoverTracker"); }

static NSTrackingArea *DPHoverArea(NSView *field) {
    for (NSTrackingArea *area in field.trackingAreas)
        if (DPIsKind(area.owner, DPDiaHoverTracker)) return area;
    return nil;
}

static BOOL DPShowsHover(NSView *field) {
    id delayed = DPDelayedTracker(field);
    return delayed && *(BOOL *)DPIvar(delayed, "isHoverActive");
}

static void DPSetHover(NSView *field, BOOL hovered) {
    id delayed = DPDelayedTracker(field), tracker = DPHoverArea(field).owner;
    if (!delayed || !tracker) return;
    *(BOOL *)DPIvar(tracker, "isHovered") = hovered;
    *(BOOL *)DPIvar(delayed, "isHoverActive") = hovered;
    *(BOOL *)DPIvar(delayed, "isIncidentalHover") = NO;
    void **handler = DPIvar(delayed, "onUpdate");
    if (handler[0]) ((DPHoverHandler)handler[0])(hovered, handler[1]);
}

static BOOL DPKeepsHover(id tracker) {
    return DPShowAddressField.on && DPIsKind(objc_loadWeak((__autoreleasing id *)DPIvar(tracker, "view")), DPDiaAddressField);
}

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    if (!DPKeepsHover(self)) DPCallOriginal(DPTracker_mouseEntered, self, event);
}
static void DPTracker_mouseMoved(id self, SEL _cmd, NSEvent *event) {
    if (!DPKeepsHover(self)) DPCallOriginal(DPTracker_mouseMoved, self, event);
}
static void DPTracker_mouseExited(id self, SEL _cmd, NSEvent *event) {
    if (!DPKeepsHover(self)) DPCallOriginal(DPTracker_mouseExited, self, event);
}

// Each tab has its own field, and Dia lays one out before showing it.
static void DPField_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPField_layout, self);
    if (DPShowAddressField.on && !DPShowsHover(self)) DPSetHover(self, YES);
}

static BOOL DPPointerOver(NSView *field) {
    return NSPointInRect([field convertPoint:field.window.mouseLocationOutsideOfEventStream fromView:nil], field.bounds);
}

static void DPApplyShowAddressField(DPPatch *patch) {
    // Off, each field goes back to whether the pointer is over it.
    for (NSView *field in DPFindViews(DPDiaAddressField)) DPSetHover(field, patch->on || DPPointerOver(field));
}

static NSString *DPVerifyShowAddressField(DPPatch *patch) {
    for (NSView *field in DPFindViews(DPDiaAddressField)) {
        if (field.hiddenOrHasHiddenAncestor || !DPHoverArea(field)) continue;
        if (patch->on && !DPShowsHover(field)) return @"address field hides its background and buttons";
        if (!patch->on && DPShowsHover(field) && !DPPointerOver(field)) return @"address field stays highlighted";
    }
    return nil;
}

static void DPInstallShowAddressField(void) {
    DPHook(DPDiaHoverTracker, @selector(mouseEntered:), (IMP)DPTracker_mouseEntered);
    DPHook(DPDiaHoverTracker, @selector(mouseMoved:), (IMP)DPTracker_mouseMoved);
    DPHook(DPDiaHoverTracker, @selector(mouseExited:), (IMP)DPTracker_mouseExited);
    DPHook(DPDiaAddressField, @selector(layout), (IMP)DPField_layout);
}

DP_PATCH(DPShowAddressField) {
    .key = @"showAddressField",
    .order = 48,
    .title = @"Always show address field",
    .detail = @"Keep the address field’s background and its bookmark, split view and site buttons showing without pointing at it.",
    .symbol = @"link",
    .tint = @"systemBlueColor",
    .section = @"Toolbar Items",
    .classes = DPClasses(DPDiaAddressField, DPDiaHoverTracker),
    .disabledBy = @"hideToolbar",
    .install = DPInstallShowAddressField,
    .apply = DPApplyShowAddressField,
    .verify = DPVerifyShowAddressField,
};
