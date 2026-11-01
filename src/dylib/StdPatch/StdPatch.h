// StdPatch: the toolkit every patch is built on. This header is the whole API.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "StdPatch/Dia.h"

#pragma mark Patches

typedef struct DPPatch DPPatch;
struct DPPatch {
    __unsafe_unretained NSString *key;  // Its NSUserDefaults key in com.diapatches.
    BOOL defaultOn;
    int order;  // Settings lists patches by ascending order.
    __unsafe_unretained NSString *title, *detail;
    __unsafe_unretained NSString *symbol, *tint;  // SF Symbol and NSColor class property for the row's icon.
    __unsafe_unretained NSString *section;  // Its group in Settings.
    const char *const *classes;  // Dia classes it needs (DPClasses). If one is missing, it stays off and Settings says so.
    __unsafe_unretained NSString *requires;    // Key of a patch that must be on. Settings lists this one as an option on that patch's page.
    __unsafe_unretained NSString *disabledBy;  // Key of a patch that, while on, hides what this one changes. Settings marks it.
    BOOL (*hides)(NSView *view);  // While on, hides every view this matches in Dia's toolbar, sidebar and tab strip.
    void (*install)(void);        // Runs once at launch whether or not the patch is on; install hooks here.
    void (*apply)(DPPatch *patch);  // Applies a toggle at once. Without it, `progress` eases toward `on` while every patch's `relayout` runs each frame.
    void (*relayout)(void);
    // nil if Dia's views match `on`, otherwise a few words on what's wrong. `make test` runs it; hide patches get one.
    // Find views with DPFindViews rather than through your own hooks, so a hook that never ran shows up as a failure.
    NSString *(*verify)(DPPatch *patch);
    BOOL on, unavailable;
    CGFloat progress;
};

#define DPClasses(...) ((const char *const []){__VA_ARGS__, NULL})

// Declares a patch and registers it. A new patch is a new folder in Patches/ and nothing else:
//     DP_PATCH(DPHideFooButton) { .key = @"hideFooButton", .title = @"Hide Foo button", ... };
#define DP_PATCH(name)                                                                              \
    DPPatch name;                                                                                   \
    __attribute__((used, section("__DATA,__dppatches"))) static DPPatch *const name##Entry = &name; \
    DPPatch name =

extern DPPatch *const *DPPatches;  // In Settings order.
extern NSUInteger DPPatchCount;
DPPatch *DPPatchNamed(NSString *key);
DPPatch *DPRequired(DPPatch *patch);  // The patch named by `requires`, or NULL.
void DPSetPatch(DPPatch *patch, BOOL on, BOOL save);  // save: NO changes it only until Dia quits (test mode).
BOOL DPSavedOn(DPPatch *patch);
void DPLoadPatches(void);     // Reads every DP_PATCH, what it needs and its saved switch.
void DPInstallPatches(void);  // Runs the installs of the available ones, and from then on applies settings diatweaks saves.
BOOL DPWriteManifest(NSString *path);  // patches.json, the patch list diatweaks shows. Reads no settings.
extern NSNotificationName const DPPatchesDidChangeNotification;  // Posted after a switch in Settings or diatweaks changed patches.

#pragma mark Hooks

// Replaces -[className sel], usually a name from Dia.h, and logs it if Dia has no such method. Two patches can hook the
// same method: each replacement's DPCallOriginal calls what was there when it was installed.
void DPHook(const char *className, SEL sel, IMP replacement);
void DPHookClass(Class cls, SEL sel, IMP replacement);  // The same for a class in hand, such as a view's own class.
IMP DPOriginalIMP(id object, SEL sel, IMP replacement);

// Inside a hook function `hook`: DPCallOriginal(hook, self, args...) calls what it replaced, typed like the hook.
#define DPCallOriginal(hook, self, ...) \
    ((__typeof__(&hook))DPOriginalIMP(self, _cmd, (IMP)hook))(self, _cmd, ##__VA_ARGS__)

#pragma mark Views

NSView *DPFindView(NSView *root, BOOL (^match)(NSView *view));  // Depth first, root included.
NSArray<NSView *> *DPFindViews(const char *className);          // In every visible window.
NSView *DPSubview(NSView *parent, const char *className);       // First direct subview of that class.
BOOL DPIsKind(id object, const char *className);
BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel);
void DPRelayoutViews(NSHashTable<NSView *> *views);  // Lays each out again now.
void *DPIvar(id object, const char *name);            // Address of an instance variable, or NULL.

#pragma mark Values

id DPGet(id object, const void *key);
void DPSet(id object, const void *key, id value);

// Patches override values Dia keeps setting, such as frames, radii and paths. DPOverride remembers Dia's value and
// ours; DPDiaValue gives back Dia's: the remembered one while `current` is still ours, else `current`, which Dia set since.
void DPOverride(id object, const void *key, id dia, id ours);
id DPDiaValue(id object, const void *key, id current);

#pragma mark App

void DPOnLaunch(void (^block)(void));
void DPOnQuit(void (^block)(void));

// A menu item that runs `action`, for any menu. DPAddMenuItem appends one to a menu in the menu bar by title, nil for
// the app menu; DPOnMenuItem points Dia's own items at `action`. Menus exist once Dia has launched: call them from DPOnLaunch.
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void));
NSMenuItem *DPAddMenuItem(NSString *menu, NSString *title, void (^action)(void));
void DPOnMenuItem(NSString *menu, NSString *titlePrefix, void (^action)(void));
