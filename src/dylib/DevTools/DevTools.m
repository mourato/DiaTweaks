#import "DevTools/DevTools.h"
#import "Updates/Updates.h"
#include <dlfcn.h>

static void DPDescribe(NSView *view, NSUInteger depth, NSMutableString *out) {
    NSString *label = view.accessibilityLabel;
    [out appendFormat:@"%*s%@ %@", (int)depth * 2, "", NSStringFromClass(view.class), NSStringFromRect(view.frame)];
    if (label.length) [out appendFormat:@" label=\"%@\"", label];
    if (view.layer.cornerRadius > 0)
        [out appendFormat:@" radius=%g corners=%lu", view.layer.cornerRadius, (unsigned long)view.layer.maskedCorners];
    if (view.hidden) [out appendString:@" hidden"];
    [out appendString:@"\n"];
    for (NSView *sub in view.subviews) DPDescribe(sub, depth + 1, out);
}

NSString *DPDescribeViews(NSView *root) {
    NSMutableString *out = [NSMutableString new];
    if (root) DPDescribe(root, 0, out);
    return out;
}

// Copies the front window's view tree, titlebar included, for finding the classes and labels a patch can match.
static void DPCopyViewTree(void) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.orderedWindows.firstObject;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:DPDescribeViews(window.contentView.superview) forType:NSPasteboardTypeString];
}

// Lets a script toggle patches and read the result without touching the screen:
//     com.diapatches.dev.set, object "hideToolbar=1"   toggles a patch the way its switch does.
//     com.diapatches.dev.dump                          writes every window's view tree to views.txt beside the dylib.
static void DPListenForScripts(void) {
    NSDistributedNotificationCenter *center = NSDistributedNotificationCenter.defaultCenter;
    [center addObserverForName:@"com.diapatches.dev.set" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSArray<NSString *> *parts = [note.object componentsSeparatedByString:@"="];
        DPPatch *patch = parts.count == 2 ? DPPatchNamed(parts[0]) : NULL;
        if (patch) DPSetPatch(patch, parts[1].boolValue, YES);
    }];
    [center addObserverForName:@"com.diapatches.dev.dump" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *_) {
        NSMutableString *out = [NSMutableString new];
        for (NSWindow *window in NSApp.windows)
            [out appendFormat:@"== window \"%@\"\n%@", window.title, DPDescribeViews(window.contentView.superview)];
        Dl_info dylib;
        dladdr((const void *)DPInstallDevTools, &dylib);
        NSString *path = [@(dylib.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"views.txt"];
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }];
}

void DPInstallDevTools(void) {
    if (![[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]) return;
    DPListenForScripts();
    DPOnLaunch(^{
        DPAddMenuItem(@"Help", @"DiaPatches: Copy View Tree", ^{ DPCopyViewTree(); });
        NSMenu *debug = [[NSMenu alloc] initWithTitle:@"Debug"];
        [debug addItem:DPMenuItem(@"Pretend Dia Has an Update", ^{ [DPUpdates.shared pretend:DPDia]; })];
        [debug addItem:DPMenuItem(@"Pretend DiaTweaks Has an Update", ^{ [DPUpdates.shared pretend:DPTweaks]; })];
        [debug addItem:DPMenuItem(@"Stop Pretending", ^{ [DPUpdates.shared stopPretending]; })];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Debug" action:nil keyEquivalent:@""];
        item.submenu = debug;
        [NSApp.mainMenu insertItem:item atIndex:1];
    });
}
