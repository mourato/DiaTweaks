#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import <mach-o/getsect.h>
#import <mach-o/ldsyms.h>

// Patching costs Dia the entitlement Apple Passwords requires of browsers, so an extension hands each passkey request to
// diapatch, which runs it in the unpatched Dia.

extern DPPatch DPPasskeys;

static NSString *const kExtensionID = @"ljonmeeapeagnkmjklinbocjbjepecce";  // from the key in extension/manifest.json

static NSString *DPAppSupport(NSString *path) {
    return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:path];
}

static BOOL DPWriteExtension(NSString *folder) {
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *name in @[ @"manifest.json", @"page.js", @"bridge.js", @"worker.js" ]) {
        NSString *section = [@"__pk_" stringByAppendingString:name.stringByDeletingPathExtension];
        unsigned long size = 0;
        uint8_t *bytes = getsectiondata(&_mh_dylib_header, "__TEXT", section.UTF8String, &size);
        if (!bytes || ![[NSData dataWithBytes:bytes length:size] writeToFile:[folder stringByAppendingPathComponent:name] atomically:YES]) return NO;
    }
    return YES;
}

// Dia's Chromium looks for native messaging hosts in Chrome's folder.
static NSString *DPHostManifestPath(void) { return DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.diapatches.passkeys.json"); }

static BOOL DPRegisterHost(void) {
    NSDictionary *manifest = @{
        @"name" : @"com.diapatches.passkeys",
        @"description" : @"DiaTweaks passkeys",
        @"path" : DPAppSupport(@"DiaPatches/bin/diapatch"),
        @"type" : @"stdio",
        @"allowed_origins" : @[ [NSString stringWithFormat:@"chrome-extension://%@/", kExtensionID] ],
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:DPHostManifestPath().stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    return [json writeToFile:DPHostManifestPath() atomically:YES];
}

static BOOL gExtensionLoaded;

// Dia passes Chromium its command line here.
static id DPConfiguration_init(id self, SEL _cmd, int argc, NSArray *argv, NSString *profilePath, NSUInteger applicationID, BOOL isProduction,
                               NSUInteger restorationPolicy, BOOL loadAllProfiles, BOOL quitRunLoop, NSString *suiteName) {
    return DPCallOriginal(DPConfiguration_init, self, argc + 1, [argv arrayByAddingObject:[@"--load-extension=" stringByAppendingString:DPAppSupport(@"DiaPatches/passkeys-extension")]], profilePath, applicationID, isProduction,
                          restorationPolicy, loadAllProfiles, quitRunLoop, suiteName);
}

static void DPShowHelper(NSNotification *note) {
    NSRunningApplication *helper = [NSRunningApplication runningApplicationWithProcessIdentifier:[note.object intValue]];
    void (^show)(void) = ^{ [helper activateFromApplication:NSRunningApplication.currentApplication options:NSApplicationActivateAllWindows]; };
    if (![note.name hasSuffix:@"signIn"]) return show();
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Sign in to Dia once for passkeys";
    alert.informativeText = @"Passkeys open in a second copy of Dia, which needs you to sign in with your Dia email once. Your passkey carries on after.";
    NSUInteger browser = [NSApp.orderedWindows indexOfObjectPassingTest:^BOOL(NSWindow *window, NSUInteger i, BOOL *stop) { return window.visible && window.canBecomeMainWindow; }];
    if (browser == NSNotFound) return (void)([alert runModal], show());
    [alert beginSheetModalForWindow:NSApp.orderedWindows[browser] completionHandler:^(NSModalResponse _) { show(); }];
}

static void DPInstallPasskeys(void) {
    NSString *extension = DPAppSupport(@"DiaPatches/passkeys-extension");
    if (!DPPasskeys.on) {
        [NSFileManager.defaultManager removeItemAtPath:extension error:nil];
        [NSFileManager.defaultManager removeItemAtPath:DPHostManifestPath() error:nil];
        return;
    }
    if (!DPWriteExtension(extension) || !DPRegisterHost()) return (void)NSLog(@"DiaPatches: couldn't set up passkeys");
    DPHook("ArcBrowserApplicationConfiguration", @selector(init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:shouldLoadAllProfilesAtStartup:quitRunLoopOnTermination:userDefaultsSuiteName:),
           (IMP)DPConfiguration_init);
    gExtensionLoaded = YES;
    for (NSString *name in @[ @"com.diapatches.passkeys.show", @"com.diapatches.passkeys.signIn" ])
        [NSDistributedNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPShowHelper(note); }];
}

static void DPApplyPasskeys(DPPatch *patch) {
    if (patch->on == gExtensionLoaded || patch->on != DPSavedOn(patch)) return;  // the self-test flips patches without saving
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to allow iCloud passkeys" : @"Relaunch Dia to stop using iCloud passkeys";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPPasskeys) {
    .key = @"passkeys",
    .order = 100,
    .title = @"Allow iCloud passkeys",
    .detail = @"Lets sites sign you in with passkeys saved in Apple Passwords, which a patched Dia can't reach. For each one, the original Dia that DiaTweaks keeps opens behind the Touch ID prompt, then quits. Your passkeys stay in Apple Passwords. Experimental.",
    .symbol = @"person.badge.key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .install = DPInstallPasskeys,
    .apply = DPApplyPasskeys,
};
