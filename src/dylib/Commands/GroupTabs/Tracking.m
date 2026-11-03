#import "GroupTabs.h"

static NSHashTable *DPContents, *DPBrowsers;
static NSMapTable *DPBrowserByContents, *DPDelegateByBrowser, *DPWindowByBrowser;
static char DPSessionKey;

static long long DPContentsSession(id contents) {
    return [contents respondsToSelector:@selector(sessionId)] ? DPLongID(DPMsg(contents, @selector(sessionId))) : 0;
}

static void DPRemember(id contents, id session, id browser, id delegate) {
    if (browser) [DPBrowsers addObject:browser];
    if (browser && delegate) [DPDelegateByBrowser setObject:delegate forKey:browser];
    if (!contents || !browser) return;
    [DPBrowserByContents setObject:browser forKey:contents];
    [DPContents addObject:contents];
    long long sid = DPLongID(session);
    if (sid <= 0) sid = DPContentsSession(contents);
    if (sid > 0) DPSet(contents, &DPSessionKey, @(sid));
}

static id DPDelegateFor(id self, id browser) {
    if ([self respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) return self;
    return [DPDelegateByBrowser objectForKey:browser];
}

static void DPBrowser_setDelegate(id self, SEL _cmd, id delegate) {
    DPCallOriginal(DPBrowser_setDelegate, self, delegate);
    [DPBrowsers addObject:self];
    if (delegate) [DPDelegateByBrowser setObject:delegate forKey:self];
}

static void DPBrowser_setWindow(id self, SEL _cmd, NSWindow *window) {
    DPCallOriginal(DPBrowser_setWindow, self, window);
    [DPBrowsers addObject:self];
    if (window) [DPWindowByBrowser setObject:window forKey:self];
}

static void DPBrowser_didRestore(id self, SEL _cmd, id browser, id contents, id session) {
    DPCallOriginal(DPBrowser_didRestore, self, browser, contents, session);
    if (browser) DPRemember(contents, session, browser, DPDelegateFor(self, browser));
}

static void DPBrowser_didCreate(id self, SEL _cmd, id browser, id contents, BOOL active) {
    DPCallOriginal(DPBrowser_didCreate, self, browser, contents, active);
    if (browser && contents) DPRemember(contents, nil, browser, DPDelegateFor(self, browser));
}

// Tabs opened from Dia's own UI come from here, not from the Chromium callbacks above, which only see
// tabs restored at launch and ones a page opens.
static id DPBrowser_createWebContents(id self, SEL _cmd, id params) {
    id contents = DPCallOriginal(DPBrowser_createWebContents, self, params);
    DPRemember(contents, nil, self, [DPDelegateByBrowser objectForKey:self]);
    return contents;
}

// A tab dragged to another window changes browser.
static void DPBrowser_takeOwnership(id self, SEL _cmd, id contents) {
    DPCallOriginal(DPBrowser_takeOwnership, self, contents);
    DPRemember(contents, nil, self, [DPDelegateByBrowser objectForKey:self]);
}

id DPCommandBrowser(void) {
    NSMutableArray *ready = [NSMutableArray new];
    for (id browser in DPBrowsers.allObjects)
        if ([[DPDelegateByBrowser objectForKey:browser] respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) [ready addObject:browser];
    for (NSWindow *window in NSApp.orderedWindows)
        for (id browser in ready)
            if ([DPWindowByBrowser objectForKey:browser] == window) return browser;
    return ready.count == 1 ? ready[0] : nil;
}

id DPGroupingDelegate(id browser) {
    return [DPDelegateByBrowser objectForKey:browser];
}

NSArray *DPTrackedContents(id browser) {
    NSMutableArray *contents = [NSMutableArray new];
    for (id each in DPContents.allObjects) if ([DPBrowserByContents objectForKey:each] == browser) [contents addObject:each];
    return contents;
}

long long DPSessionOf(id contents) {
    long long sid = DPContentsSession(contents);
    return sid > 0 ? sid : DPLongID(DPGet(contents, &DPSessionKey));
}

void DPInstallGroupTabs(void) {
    DPContents = [NSHashTable weakObjectsHashTable];
    DPBrowsers = [NSHashTable weakObjectsHashTable];
    DPBrowserByContents = [NSMapTable weakToWeakObjectsMapTable];
    DPDelegateByBrowser = [NSMapTable weakToWeakObjectsMapTable];
    DPWindowByBrowser = [NSMapTable weakToWeakObjectsMapTable];

    DPHook(DPDiaBrowser, @selector(setDelegate:), (IMP)DPBrowser_setDelegate);
    DPHook(DPDiaBrowser, @selector(setWindow:), (IMP)DPBrowser_setWindow);
    DPHook(DPDiaBrowser, @selector(createWebContents:), (IMP)DPBrowser_createWebContents);
    DPHook(DPDiaBrowser, @selector(takeOwnershipOfWebContents:), (IMP)DPBrowser_takeOwnership);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didRestoreWebContents:withSessionId:), (IMP)DPBrowser_didRestore);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didCreateNewWebContents:isActive:), (IMP)DPBrowser_didCreate);
    DPInstallGroupMenus();
}
