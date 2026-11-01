#import "StdPatch/StdPatch.h"
#import "StdPatch/Hide.h"
#include <mach-o/getsect.h>
#include <notify.h>

extern const struct mach_header_64 __dso_handle;

static const CFTimeInterval DPAnimationDuration = 0.25;

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
static NSUserDefaults *DPDefaults;

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

DPPatch *DPPatchNamed(NSString *key) {
    for (NSUInteger i = 0; key && i < DPPatchCount; i++) if ([DPPatches[i]->key isEqualToString:key]) return DPPatches[i];
    return NULL;
}

DPPatch *DPRequired(DPPatch *patch) {
    return DPPatchNamed(patch->requires);
}

static void DPAnimate(void) {
    static NSTimer *timer;
    static CFTimeInterval start;
    static CGFloat *from;
    from = from ?: calloc(DPPatchCount, sizeof *from);
    start = CACurrentMediaTime();
    for (NSUInteger i = 0; i < DPPatchCount; i++) from[i] = DPPatches[i]->progress;
    if (timer) return;
    timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *t) {
        CGFloat elapsed = CACurrentMediaTime() - start, omega = 22;
        BOOL done = elapsed >= DPAnimationDuration * 2;
        CGFloat eased = done ? 1 : 1 - (1 + omega * elapsed) * exp(-omega * elapsed);
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->progress = from[i] + (DPPatches[i]->on - from[i]) * eased;
        for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i]->relayout) DPPatches[i]->relayout();
        if (done) {
            [t invalidate];
            timer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

void DPSetPatch(DPPatch *patch, BOOL on, BOOL save) {
    if (patch->on == on) return;
    patch->on = on;
    if (save) [DPDefaults setBool:on forKey:patch->key];
    if (patch->apply) patch->apply(patch);
    else DPAnimate();
}

BOOL DPSavedOn(DPPatch *patch) {
    id value = [DPDefaults objectForKey:patch->key];
    return !patch->unavailable && (value ? [value boolValue] : patch->defaultOn);
}

static int DPCompareOrder(const void *a, const void *b) {
    return (*(DPPatch *const *)a)->order - (*(DPPatch *const *)b)->order;
}

// The DP_PATCH entries, in Settings order.
static void DPReadPatches(void) {
    unsigned long size = 0;
    DPPatch **entries = (DPPatch **)getsectiondata(&__dso_handle, "__DATA", "__dppatches", &size);
    DPPatch **sorted = malloc(size);
    memcpy(sorted, entries, size);
    DPPatchCount = size / sizeof *sorted;
    qsort(sorted, DPPatchCount, sizeof *sorted, DPCompareOrder);
    DPPatches = sorted;
}

void DPLoadPatches(void) {
    DPDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPReadPatches();

    for (NSUInteger i = 0; i < DPPatchCount; i++)
        for (const char *const *name = DPPatches[i]->classes; name && *name; name++) DPPatches[i]->unavailable |= !objc_getClass(*name);
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        for (DPPatch *required = DPRequired(patch); required; required = DPRequired(required)) patch->unavailable |= required->unavailable;
        patch->on = DPSavedOn(patch);
        patch->progress = patch->on;
        if (!patch->hides) continue;
        patch->apply = patch->apply ?: DPApplyHides;
        patch->verify = patch->verify ?: DPVerifyHides;
    }
}

// diatweaks saves settings, then posts com.diapatches.changed. They apply like switches flipped in Settings, without saving them again.
static void DPApplySavedSettings(void) {
    CFPreferencesAppSynchronize(CFSTR("com.diapatches"));
    for (NSUInteger i = 0; i < DPPatchCount; i++) DPSetPatch(DPPatches[i], DPSavedOn(DPPatches[i]), NO);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

void DPInstallPatches(void) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) if (!DPPatches[i]->unavailable && DPPatches[i]->install) DPPatches[i]->install();
    DPInstallHides();
    int token;
    notify_register_dispatch("com.diapatches.changed", &token, dispatch_get_main_queue(), ^(int _) { DPApplySavedSettings(); });
}

BOOL DPWriteManifest(NSString *path) {
    DPReadPatches();
    NSMutableArray<NSDictionary *> *patches = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i], *required = DPRequired(patch), *disabler = DPPatchNamed(patch->disabledBy);
        [patches addObject:@{
            @"key": patch->key,
            @"title": patch->title,
            @"detail": patch->detail,
            @"defaultOn": @(patch->defaultOn),
            @"requires": required ? required->key : NSNull.null,
            @"disabledBy": disabler ? disabler->key : NSNull.null,
        }];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"patches": patches}
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    return [json writeToFile:path atomically:YES];
}
