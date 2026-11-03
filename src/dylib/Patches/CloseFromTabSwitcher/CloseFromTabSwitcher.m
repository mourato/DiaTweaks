#import "StdPatch/StdPatch.h"

// The switcher never drops a closed tab while open, so after closing one it reopens and steps back into place.

@interface NSObject (DPSwiftFields)
- (id)safeSwiftValueForKey:(NSString *)key;
@end

extern DPPatch DPCloseFromTabSwitcher;

static id DPField(id object, NSString *key) {
    return [object respondsToSelector:@selector(safeSwiftValueForKey:)] ? [object safeSwiftValueForKey:key] : nil;
}

static NSWindowController *DPOpenSwitcher(void) {
    for (NSWindow *window in NSApp.windows)
        if (window.visible && DPIsKind(window.windowController, DPDiaTabSwitcher)) return window.windowController;
    return nil;
}

// Tab IDs are UUIDs, and the items only come through as their description.
static NSArray<NSString *> *DPSwitcherTabs(NSWindowController *switcher, NSString **focused) {
    id state = DPField(DPField(DPField(switcher, @"viewModel"), @"stateSubject"), @"currentValue");
    if (focused) *focused = [DPField(state, @"focusedItemID") description];
    NSString *items = [DPField(state, @"items") description] ?: @"";
    static NSRegularExpression *uuid;
    if (!uuid) uuid = [NSRegularExpression regularExpressionWithPattern:@"[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}" options:0 error:nil];
    NSMutableArray *tabs = [NSMutableArray new];
    for (NSTextCheckingResult *match in [uuid matchesInString:items options:0 range:NSMakeRange(0, items.length)])
        [tabs addObject:[items substringWithRange:match.range]];
    return tabs;
}

static id DPScriptTab(NSString *tabID) {
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        for (id tab in [window valueForKey:@"appleScriptTabs"])
            if ([[tab valueForKey:@"tabId"] isEqual:tabID]) return tab;
    return nil;
}

static NSMenuItem *DPCycleItem(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.keyEquivalent isEqualToString:@"\t"] && item.keyEquivalentModifierMask == NSEventModifierFlagControl) return item;
        NSMenuItem *found = DPCycleItem(item.submenu);
        if (found) return found;
    }
    return nil;
}

static void DPOpenSwitcherAgain(void) {
    NSMenuItem *cycle = DPCycleItem(NSApp.mainMenu);
    if (cycle) [NSApp sendAction:cycle.action to:cycle.target from:cycle];
}

// Once open, the switcher moves on ⌃⇥ itself rather than through the menu.
static void DPStep(void) {
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:NSApp.keyWindow.windowNumber context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48]
             atStart:NO];
}

// Steps only once the last step has shown, so a slow switcher isn't overshot.
static void DPFocus(NSString *tabID, NSString *lastSeen, int tries) {
    NSString *focused = nil;
    NSWindowController *switcher = DPOpenSwitcher();
    if (switcher) DPSwitcherTabs(switcher, &focused);
    if (!tries || [focused isEqual:tabID]) return;
    if (focused && ![focused isEqual:lastSeen]) DPStep();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DPFocus(tabID, focused ?: lastSeen, tries - 1);
    });
}

// Closing finishes later, and a switcher opened before then would still list the tab.
static void DPReopenOnceClosed(NSString *closed, NSString *focus, int tries) {
    if (!tries || !(NSEvent.modifierFlags & NSEventModifierFlagControl)) return;
    if (DPScriptTab(closed)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPReopenOnceClosed(closed, focus, tries - 1); });
        return;
    }
    DPOpenSwitcherAgain();
    DPFocus(focus, nil, 100);
}

static BOOL DPCloseFocusedTab(NSWindowController *switcher) {
    NSString *focused = nil;
    NSMutableArray<NSString *> *tabs = [DPSwitcherTabs(switcher, &focused) mutableCopy];
    NSUInteger index = [tabs indexOfObject:focused];
    id tab = DPScriptTab(focused);
    if (index == NSNotFound || !tab) return NO;
    [tab performSelector:@selector(close:) withObject:nil];
    [tabs removeObjectAtIndex:index];
    [switcher close];
    if (tabs.count > 1) DPReopenOnceClosed(focused, tabs[MIN(index, tabs.count - 1)], 50);
    return YES;
}

// The switcher picks the highlighted tab as soon as another modifier goes down, so it never sees ⌘.
static BOOL DPTakeEvent(NSEvent *event) {
    if (!DPCloseFromTabSwitcher.on || !(event.type == NSEventTypeKeyDown || event.type == NSEventTypeFlagsChanged)) return NO;
    if (!(event.modifierFlags & NSEventModifierFlagControl)) return NO;
    NSWindowController *switcher = DPOpenSwitcher();
    if (!switcher) return NO;
    if (event.type == NSEventTypeFlagsChanged) return event.keyCode == 54 || event.keyCode == 55;
    // ⇧ may still be down from cycling backward, and ⌘⇧W would close the window.
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption);
    return (mods == NSEventModifierFlagCommand || !mods) && [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"w"] && DPCloseFocusedTab(switcher);
}

// Every event comes through here, before the switcher's own key handling can take it.
static NSEvent *DPApplication_nextEvent(NSApplication *self, SEL _cmd, NSEventMask mask, NSDate *until, NSRunLoopMode mode, BOOL dequeue) {
    NSEvent *event;
    do event = DPCallOriginal(DPApplication_nextEvent, self, mask, until, mode, dequeue);
    while (dequeue && event && DPTakeEvent(event));
    return event;
}

static void DPInstallCloseFromTabSwitcher(void) {
    DPHookClass(NSApplication.class, @selector(nextEventMatchingMask:untilDate:inMode:dequeue:), (IMP)DPApplication_nextEvent);
}

DP_PATCH(DPCloseFromTabSwitcher) {
    .key = @"closeFromTabSwitcher",
    .defaultOn = YES,
    .order = 85,
    .title = @"Close tabs from the tab switcher",
    .detail = @"Press W or ⌘W while the tab switcher (⌃⇥) is open to close the highlighted tab and keep switching.",
    .symbol = @"rectangle.on.rectangle.slash",
    .tint = @"systemOrangeColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabSwitcher),
    .install = DPInstallCloseFromTabSwitcher,
};
