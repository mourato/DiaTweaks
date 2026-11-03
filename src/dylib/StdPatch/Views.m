#import "StdPatch/StdPatch.h"

NSView *DPFindView(NSView *root, BOOL (^match)(NSView *)) {
    if (!root || match(root)) return root;
    for (NSView *sub in root.subviews) {
        NSView *found = DPFindView(sub, match);
        if (found) return found;
    }
    return nil;
}

static void DPCollectViews(NSView *view, Class cls, NSMutableArray<NSView *> *views) {
    if ([view isKindOfClass:cls]) [views addObject:view];
    for (NSView *sub in view.subviews) DPCollectViews(sub, cls, views);
}

NSArray<NSView *> *DPFindViews(const char *className) {
    Class cls = objc_getClass(className);
    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows)
        if (cls && window.isVisible) DPCollectViews(window.contentView, cls, views);
    return views;
}

NSString *DPTabLayout(void) { return DPFindViews(DPDiaSidebarFooter).count ? @"vertical" : @"horizontal"; }

NSView *DPSubview(NSView *parent, const char *className) {
    for (NSView *sub in parent.subviews) if (DPIsKind(sub, className)) return sub;
    return nil;
}

BOOL DPIsKind(id object, const char *className) {
    Class cls = objc_getClass(className);
    return cls && [object isKindOfClass:cls];
}

BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel) {
    return [view.accessibilityLabel isEqualToString:accessibilityLabel];
}

void DPRelayoutViews(NSHashTable<NSView *> *views) {
    for (NSView *view in views.allObjects) {
        view.needsLayout = YES;
        [view layoutSubtreeIfNeeded];
    }
}

void *DPIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return ivar ? (uint8_t *)(__bridge void *)object + ivar_getOffset(ivar) : NULL;
}

id DPGet(id object, const void *key) {
    return objc_getAssociatedObject(object, key);
}

void DPSet(id object, const void *key, id value) {
    objc_setAssociatedObject(object, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DPOverride(id object, const void *key, id dia, id ours) {
    DPSet(object, key, @[dia, ours]);
}

id DPDiaValue(id object, const void *key, id current) {
    NSArray *values = DPGet(object, key);
    return values && [values[1] isEqual:current] ? values[0] : current;
}
