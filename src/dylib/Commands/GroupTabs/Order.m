// Dia's scripting tabs list a window's tabs in order, but a group's index counts from the first unpinned tab, which nothing reports.
// So the first tab put back goes to index 0, and where it lands gives the offset. A tab moves by going alone into a scratch group,
// moving that group, and ungrouping it.
#import "GroupTabs.h"
#import <objc/message.h>

static NSString *DPURLOf(id tab) { return DPText(DPMsg(tab, @selector(URL))); }

static NSArray *DPWindowTabsMatching(BOOL (^match)(id tab)) {
    NSArray *best = nil;
    NSUInteger most = 0;
    for (id window in DPMsg(NSApp.delegate, @selector(appleScriptWindows))) {
        NSArray *tabs = DPMsg(window, @selector(appleScriptTabs));
        NSUInteger count = [tabs indexesOfObjectsPassingTest:^BOOL(id tab, NSUInteger i, BOOL *stop) { return match(tab); }].count;
        if (count > most) { best = tabs; most = count; }
    }
    return best;
}

NSDictionary *DPTabPlaces(NSDictionary<NSNumber *, NSString *> *urls) {
    NSSet *wanted = [NSSet setWithArray:urls.allValues];
    NSArray *tabs = DPWindowTabsMatching(^BOOL(id tab) { return [wanted containsObject:DPURLOf(tab)]; });
    // Scripting tabs have a URL but no session, so each session claims the first unclaimed tab at its URL.
    NSMutableDictionary<NSString *, NSNumber *> *sessions = [NSMutableDictionary new];
    for (NSNumber *sid in urls)
        for (id tab in tabs)
            if (!sessions[[tab valueForKey:@"tabId"]] && [DPURLOf(tab) isEqualToString:urls[sid]]) {
                sessions[[tab valueForKey:@"tabId"]] = sid;
                break;
            }
    return tabs && sessions.count == urls.count ? @{@"order": [tabs valueForKey:@"tabId"], @"sessions": sessions} : nil;
}

static void DPMoveTab(id delegate, id browser, NSNumber *sid, NSInteger index, void (^done)(void)) {
    void (*create)(id, SEL, id, NSArray *, id, void (^)(id)) = (void *)objc_msgSend;
    void (*move)(id, SEL, id, id, NSInteger, void (^)(id)) = (void *)objc_msgSend;
    void (*ungroup)(id, SEL, id, NSArray *, void (^)(id)) = (void *)objc_msgSend;
    create(delegate, @selector(browser:createTabGroupWithSessionIds:properties:completion:), browser, @[sid], [objc_getClass(DPDiaTabGroupProperties) new], ^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            id group = [result respondsToSelector:@selector(groupId)] ? DPMsg(result, @selector(groupId)) : nil;
            if (!group) return;
            move(delegate, @selector(browser:moveTabGroupWithId:toNewIndex:completion:), browser, group, index, ^(id _) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ungroup(delegate, @selector(browser:removeTabsFromGroupWithSessionIds:completion:), browser, @[sid], ^(id _) {
                        dispatch_async(dispatch_get_main_queue(), done);
                    });
                });
            });
        });
    });
}

static void DPRunMoves(id delegate, id browser, NSArray<NSArray *> *moves, NSUInteger index) {
    if (index >= moves.count) return;
    DPMoveTab(delegate, browser, moves[index][0], [moves[index][1] integerValue], ^{ DPRunMoves(delegate, browser, moves, index + 1); });
}

// A moved tab that's due comes up; one in the way goes to the end until it's due. Tabs that weren't grouped keep their order, so one
// out of place means the list changed since, and planning stops there.
static NSArray<NSArray *> *DPPlanMoves(NSArray<NSString *> *target, NSMutableArray<NSString *> *now, NSDictionary<NSString *, NSNumber *> *sessions, NSUInteger start) {
    NSMutableArray *moves = [NSMutableArray new];
    if (![[NSSet setWithArray:now] isEqualToSet:[NSSet setWithArray:target]]) return moves;
    for (NSUInteger i = 0; i < target.count; i++) {
        while (![now[i] isEqualToString:target[i]]) {
            BOOL due = sessions[target[i]] != nil;
            NSString *tab = due ? target[i] : now[i];
            NSUInteger to = due ? i : now.count - 1;
            if (!sessions[tab] || to < start) return moves;
            [now removeObject:tab];
            [now insertObject:tab atIndex:to];
            [moves addObject:@[sessions[tab], @(to - start)]];
        }
    }
    return moves;
}

void DPRestorePlaces(id delegate, id browser, NSDictionary *places) {
    NSDictionary<NSString *, NSNumber *> *sessions = places[@"sessions"];
    NSString *first = sessions.allKeys.firstObject;
    DPMoveTab(delegate, browser, sessions[first], 0, ^{
        NSArray *tabs = DPWindowTabsMatching(^BOOL(id tab) { return [[tab valueForKey:@"tabId"] isEqual:first]; });
        NSMutableArray *now = [[tabs valueForKey:@"tabId"] mutableCopy];
        NSUInteger start = [now indexOfObject:first];
        if (start != NSNotFound) DPRunMoves(delegate, browser, DPPlanMoves(places[@"order"], now, sessions, start), 0);
    });
}
