// Arc's Peek, rebuilt from parts Dia has: a Shift-clicked link opens in the window Dia makes for it,
// which is then dressed as a card over the window it came from, with Arc's blur and controls.
#import "Peek.h"
#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <os/log.h>

// Set on a window while it's shown as a Peek, whose header takes the toolbar's place, whatever hide toolbar says.
static char DPPeekBackdropKey;
const CGFloat DPPeekHeaderHeight = 36;

BOOL DPInPeek(NSView *view) {
    return view.window && DPGet(view.window, &DPPeekBackdropKey);
}

static void DPRelayoutPanesIn(NSWindow *window) {
    for (NSView *pane in DPPanes) if (pane.window == window) pane.needsLayout = YES;
    // Edge-to-edge treats a Peek's page as always edge to edge; the page is placed again to grow or shrink it.
    for (NSView *container in DPContainers) {
        NSValue *requested = DPRequestedFrame(container);
        if (container.window == window && requested) container.frame = requested.rectValue;
    }
    window.contentView.needsLayout = YES;
}

// Docking the sidebar pushes the web content right; a floating or hidden sidebar leaves it at the window padding.
static BOOL DPSidebarShownIn(NSWindow *window) {
    CGFloat minX = CGFLOAT_MAX;
    for (NSView *container in DPContainers) {
        NSValue *requested = DPRequestedFrame(container);
        if (container.window != window || !requested) continue;
        minX = MIN(minX, NSMinX([container.superview convertRect:requested.rectValue toView:nil]));
    }
    return minX != CGFLOAT_MAX && minX > DPWindowPadding + 1;
}

// Shift-clicks reach Dia as popups, whose window has its own title and address bar above the page.
// In a Peek the bar is hidden and the page takes its place; the Peek's header sits in the title bar.
static void DPPopupContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPopupContent_layout, self);
    BOOL peek = DPInPeek(self);
    NSWindow *window = self.window;
    // The header is taller than the title bar it covers; the page gives up the difference.
    CGFloat titleBar = NSHeight(window.frame) - NSMaxY(window.contentLayoutRect), below = MAX(0, DPPeekHeaderHeight - titleBar);
    for (NSView *sub in self.subviews) {
        if (DPIsKind(sub, DPDiaPopupNavigationBar)) sub.hidden = peek;
        else if (peek) sub.frame = NSMakeRect(0, self.isFlipped ? below : 0, NSWidth(self.bounds), NSHeight(self.bounds) - below);
    }
}

// Dispositions are Chromium's WindowOpenDisposition, which ArcCore passes through unchanged.
// Arc's Peek, rebuilt from parts Dia has: a Shift-clicked link opens in the window Dia makes for it,
// which is then dressed as a card over the window it came from, with Arc's blur and controls.
// Dispositions are Chromium's WindowOpenDisposition, which ArcCore passes through unchanged.
enum { DPForegroundTab = 3, DPBackgroundTab = 4, DPPopup = 5, DPNewWindow = 6 };
static const CGFloat DPPeekInsetX = 0.09, DPPeekInsetY = 0.012;
static const CFTimeInterval DPPeekDuration = 0.25, DPPeekGrace = 3, DPShiftClickWindow = 1;

static CFTimeInterval DPPeekPendingUntil, DPShiftClickAt;
static __weak NSWindow *DPPeekParent;
static NSPoint DPPeekOrigin;
static NSURL *DPPeekURL;
// Windows that existed when the Peek was asked for; only a window opened after that can become it.
static NSHashTable<NSWindow *> *DPPeekKnownWindows;
static NSSet<NSString *> *DPPeekKnownScriptedWindows;
static char DPPeekActionKey;

static os_log_t DPLog(void) {
    static os_log_t log;
    return log = log ?: os_log_create("com.diapatches", "peek");
}

// ArcCore already reports a Shift-click as a popup; new tabs and windows are rerouted to one.
static BOOL DPPeekWanted(NSInteger disposition) {
    BOOL newContents = disposition == DPForegroundTab || disposition == DPBackgroundTab || disposition == DPPopup || disposition == DPNewWindow;
    return DPPeek.on && newContents && CACurrentMediaTime() - DPShiftClickAt < DPShiftClickWindow;
}

// Only a click held with Shift asks for a Peek: the Shift key held later, while a page calls window.open
// or a form submits, doesn't. Any other click withdraws a Peek still waiting for its window.
static void DPPeekWatchClicks(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
        BOOL shift = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagShift;
        DPShiftClickAt = shift ? CACurrentMediaTime() : 0;
        if (!shift) DPPeekPendingUntil = 0;
        return event;
    }];
}

static NSSet<NSString *> *DPScriptedWindowIds(void) {
    NSMutableSet *ids = [NSMutableSet new];
    for (id scripted in [NSApp valueForKey:@"appleScriptWindows"]) {
        NSString *windowId = [scripted valueForKey:@"windowId"];
        if (windowId) [ids addObject:windowId];
    }
    return ids;
}

static void DPPeekRequested(void) {
    DPPeekPendingUntil = CACurrentMediaTime() + DPPeekGrace;
    DPPeekParent = NSApp.keyWindow;
    DPPeekOrigin = NSEvent.mouseLocation;
    DPPeekKnownWindows = [NSHashTable weakObjectsHashTable];
    for (NSWindow *window in NSApp.windows) [DPPeekKnownWindows addObject:window];
    DPPeekKnownScriptedWindows = DPScriptedWindowIds();
}

static BOOL DPPeekCandidate(NSWindow *window) {
    NSWindow *parent = DPPeekParent;
    return parent && window != parent && CACurrentMediaTime() <= DPPeekPendingUntil
        && ([window isKindOfClass:objc_getClass(DPDiaPlatformWindow)] || [window isKindOfClass:objc_getClass(DPDiaPopupWindow)])
        && ![DPPeekKnownWindows containsObject:window];
}

// target="_blank" links and window.open arrive here as new web contents.
static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    if (DPPeekWanted(disposition)) {
        DPPeekRequested();
        DPPeekURL = url;
        disposition = DPPopup;
    }
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
}

// Only actions marked by the policy hook below read as popups, so nothing else in Dia sees the change.
static NSInteger DPNavigationAction_disposition(id self, SEL _cmd) {
    return objc_getAssociatedObject(self, &DPPeekActionKey) ? DPPopup : DPCallOriginal(DPNavigationAction_disposition, self);
}

// Plain links that Chromium wants anywhere but the current tab are asked about here first;
// Dia answers with the disposition to open them with.
static NSInteger DPWebContent_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    NSInteger raw = ((NSInteger (*)(id, SEL))DPOriginalIMP(action, @selector(navigationDisposition), (IMP)DPNavigationAction_disposition))(action, @selector(navigationDisposition));
    BOOL peek = DPPeekWanted(raw);
    os_log_debug(DPLog(), "Link click: disposition %ld, shift-click %d, peek %d", (long)raw, CACurrentMediaTime() - DPShiftClickAt < DPShiftClickWindow, peek);
    if (peek) {
        DPPeekRequested();
        DPPeekURL = [action valueForKey:@"url"];
        objc_setAssociatedObject(action, &DPPeekActionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
}

typedef NS_ENUM(NSInteger, DPPeekExit) { DPPeekExitClose, DPPeekExitMaximize, DPPeekExitSplit };
static void DPPeekEnd(NSWindow *peek, DPPeekExit exit);

// The header's buttons take the first click too, but keep the plain look of a toolbar.
@interface DPPeekHeaderButton : NSButton
@end
@implementation DPPeekHeaderButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

// Arc's round controls take the first click even though the Peek, not the backdrop, is key.
@interface DPPeekButton : NSButton
@end
@implementation DPPeekButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)updateLayer { self.layer.backgroundColor = [NSColor colorWithWhite:0.08 alpha:self.isHighlighted ? 0.7 : 0.9].CGColor; }
- (BOOL)wantsUpdateLayer { return YES; }
@end

// The backdrop's content: blurred page, a click anywhere closes the Peek.
@interface DPPeekBackdropView : NSVisualEffectView
@property (nonatomic, weak) NSWindow *peek;
@end
@implementation DPPeekBackdropView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { DPPeekEnd(self.peek, DPPeekExitClose); }
- (void)rightMouseDown:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}
@end

// Dia's own menu commands act on the key window, which the Peek is. Found by shortcut, which stays put
// across languages; `title`, when given, has to appear in the item's name too.
static NSMenuItem *DPFindMenuItem(NSMenu *menu, NSString *key, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = item.submenu ? DPFindMenuItem(item.submenu, key, title) : nil;
        if (found) return found;
        BOOL command = [item.keyEquivalent isEqualToString:key] && (item.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand;
        if (command && (!title || [item.title rangeOfString:title options:NSCaseInsensitiveSearch].location != NSNotFound)) return item;
    }
    return nil;
}

static BOOL DPPerformMenuItem(NSString *key, NSString *title) {
    NSMenuItem *item = DPFindMenuItem(NSApp.mainMenu, key, title);
    return item && [NSApp sendAction:item.action to:item.target from:item];
}

@class DPPeekBackdrop;
static NSURL *DPPeekCurrentURL(DPPeekBackdrop *backdrop);

// A borderless window between the parent and the Peek: Dia draws its pages above anything
// added to its own windows, so the blur and controls live here instead.
@interface DPPeekBackdrop : NSPanel
@property (nonatomic, weak) NSWindow *peek, *host;
@property (nonatomic, strong) DPPeekBackdropView *blur;
@property (nonatomic, strong) NSView *controls, *header;
@property (nonatomic, strong) NSTextField *address;
@property (nonatomic, strong) NSTimer *addressTimer;
@property (nonatomic) NSPoint origin;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic) BOOL animating, hidSidebar;
@property (nonatomic, strong) NSSet<NSString *> *knownScriptedWindows;
@property (nonatomic, strong) NSMutableArray *observers;
@property (nonatomic, strong) id monitor;
@end

@implementation DPPeekBackdrop

- (instancetype)initWithPeek:(NSWindow *)peek host:(NSWindow *)host origin:(NSPoint)origin url:(NSURL *)url {
    if (!(self = [super initWithContentRect:host.frame styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                    backing:NSBackingStoreBuffered defer:NO])) return nil;
    _peek = peek;
    _host = host;
    _origin = origin;
    _url = url;
    _observers = [NSMutableArray new];
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = NO;
    self.releasedWhenClosed = NO;
    self.excludedFromWindowsMenu = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorTransient;

    _blur = [DPPeekBackdropView new];
    _blur.peek = peek;
    _blur.material = NSVisualEffectMaterialFullScreenUI;
    _blur.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _blur.state = NSVisualEffectStateActive;
    _blur.wantsLayer = YES;
    _blur.layer.cornerRadius = 10;
    _blur.layer.cornerCurve = kCACornerCurveContinuous;
    _blur.layer.masksToBounds = YES;
    // The controls sit beside the blur rather than in it, so closing can fade the blur on its own.
    NSView *content = [[NSView alloc] initWithFrame:host.contentLayoutRect];
    _blur.frame = content.bounds;
    _blur.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_blur];
    self.contentView = content;

    // Fixed frames rather than a stack view, which squeezed the circles out of shape.
    static const CGFloat side = 28, gap = 8;
    _controls = [NSView new];
    NSArray *specs = @[@[@"xmark", @"Close Peek"], @[@"arrow.up.left.and.arrow.down.right", @"Open as Tab"], @[@"rectangle.split.2x1", @"Open Side by Side"]];
    for (NSUInteger i = 0; i < specs.count; i++) {
        DPPeekButton *button = [DPPeekButton buttonWithImage:[NSImage imageWithSystemSymbolName:specs[i][0] accessibilityDescription:specs[i][1]]
                                                      target:self action:@selector(control:)];
        button.tag = i;
        button.bordered = NO;
        button.toolTip = specs[i][1];
        button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightBold];
        button.contentTintColor = NSColor.whiteColor;
        button.imagePosition = NSImageOnly;
        button.wantsLayer = YES;
        button.layer.cornerRadius = side / 2;
        button.layer.cornerCurve = kCACornerCurveCircular;
        button.frame = NSMakeRect(0, (specs.count - 1 - i) * (side + gap), side, side);
        [_controls addSubview:button];
    }
    _controls.frame = NSMakeRect(0, 0, side, specs.count * side + (specs.count - 1) * gap);
    _controls.alphaValue = 0;
    [content addSubview:_controls];

    // Arc's bar over the page: back, forward and reload on the left, the site in the middle. It covers the
    // Peek's own top bar (a popup's title bar, or a browser window's toolbar), so it moves and scales with the page.
    _header = [NSView new];
    _header.wantsLayer = YES;
    NSArray *navigation = @[@[@"chevron.left", @"Back"], @[@"chevron.right", @"Forward"], @[@"arrow.clockwise", @"Reload"]];
    for (NSUInteger i = 0; i < navigation.count; i++) {
        NSButton *button = [DPPeekHeaderButton buttonWithImage:[NSImage imageWithSystemSymbolName:navigation[i][0] accessibilityDescription:navigation[i][1]]
                                                  target:self action:@selector(navigate:)];
        button.tag = i;
        button.bordered = NO;
        button.toolTip = navigation[i][1];
        button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium];
        button.contentTintColor = NSColor.secondaryLabelColor;
        button.autoresizingMask = NSViewMinYMargin | NSViewMaxYMargin;
        [_header addSubview:button];
    }
    _address = [NSTextField labelWithString:url.host ?: @""];
    _address.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _address.textColor = NSColor.secondaryLabelColor;
    _address.alignment = NSTextAlignmentCenter;
    _address.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_header addSubview:_address];
    __weak DPPeekBackdrop *weakSelf = self;
    _addressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        DPPeekBackdrop *backdrop = weakSelf;
        NSURL *current = backdrop ? DPPeekCurrentURL(backdrop) : nil;
        if (current) backdrop.address.stringValue = current.host ?: current.absoluteString;
    }];
    return self;
}

// Dia's Back, Forward and Reload commands, which act on the Peek as the key window.
- (void)navigate:(NSButton *)sender {
    static NSString *const keys[] = {@"[", @"]", @"r"};
    [self.peek makeKeyWindow];
    if (!DPPerformMenuItem(keys[sender.tag], nil)) os_log(DPLog(), "Peek found no menu command for ⌘%{public}@", keys[sender.tag]);
}

- (void)setChromeAlpha:(CGFloat)alpha animated:(BOOL)animated {
    (animated ? self.controls.animator : self.controls).alphaValue = alpha;
}

- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)control:(NSButton *)sender { DPPeekEnd(self.peek, sender.tag); }

// Arc's card is nearly full height, centred in the window and inset at the sides, with the controls in the right margin.
- (NSRect)peekFrame {
    NSRect frame = self.host.frame;
    return NSInsetRect(frame, NSWidth(frame) * DPPeekInsetX, MAX(10, NSHeight(frame) * DPPeekInsetY));
}

- (void)layoutHeader {
    NSView *frameView = self.peek.contentView.superview;
    if (!frameView) return;
    if (self.header.superview != frameView) [frameView addSubview:self.header positioned:NSWindowAbove relativeTo:nil];
    CGFloat height = DPPeekHeaderHeight, width = NSWidth(frameView.bounds);
    self.header.frame = NSMakeRect(0, NSHeight(frameView.bounds) - height, width, height);
    for (NSView *sub in self.header.subviews)
        if ([sub isKindOfClass:NSButton.class]) sub.frame = NSMakeRect(10 + sub.tag * 30, (height - 28) / 2, 28, 28);
    self.address.frame = NSMakeRect(110, (height - 18) / 2, MAX(0, width - 220), 18);
}

- (NSRect)local:(NSRect)screenRect { return [self.contentView convertRect:[self convertRectFromScreen:screenRect] fromView:nil]; }

- (void)layoutPeek {
    NSWindow *host = self.host, *peek = self.peek;
    if (!host || !peek) return;
    if (!NSEqualRects(self.frame, host.frame)) [self setFrame:host.frame display:YES];
    NSRect frame = self.peekFrame;
    if (!self.animating && !NSEqualRects(frame, peek.frame)) [peek setFrame:frame display:YES animate:NO];
    NSRect card = [self local:frame];
    NSSize size = self.controls.frame.size;
    self.controls.frame = (NSRect){{NSMaxX(card) + 12, NSMaxY(card) - size.height}, size};
    [self layoutHeader];
}

@end

#pragma mark - Header color

// The header takes the page's color the way Dia's toolbar does: the color Dia samples from the top of the rendered
// page, so a sticky header shows through after scrolling. Until a sample arrives, the theme-color the page declares,
// else the background it paints. Chromium reports all of them on the page's WebContents, which knows its view.
static NSHashTable *DPWebContentsSeen;
static char DPTopBandColorKey;

static NSColor *DPColorFromArc(id arcColor) {
    if ([arcColor isKindOfClass:NSColor.class]) return arcColor;
    if (![arcColor respondsToSelector:NSSelectorFromString(@"a")]) return nil;
    unsigned char (*channel)(id, SEL) = (void *)objc_msgSend;
    CGFloat alpha = channel(arcColor, NSSelectorFromString(@"a")) / 255.0;
    if (alpha == 0) return nil;
    return [NSColor colorWithSRGBRed:channel(arcColor, NSSelectorFromString(@"r")) / 255.0 green:channel(arcColor, NSSelectorFromString(@"g")) / 255.0
                                blue:channel(arcColor, NSSelectorFromString(@"b")) / 255.0 alpha:alpha];
}

static NSColor *DPPageColorIn(NSWindow *window) {
    for (id contents in DPWebContentsSeen) {
        NSView *view = [contents valueForKey:@"nativeView"];
        if (view.window != window) continue;
        NSColor *color = DPGet(contents, &DPTopBandColorKey) ?: DPColorFromArc([contents valueForKey:@"themeColor"])
            ?: DPColorFromArc([contents valueForKey:@"rootBackgroundColor"]);
        if (color) return color;
    }
    return nil;
}

// The buttons and address follow the color: dark on a light page, light on a dark one.
static void DPPeekTintHeader(NSWindow *peek) {
    DPPeekBackdrop *backdrop = peek ? objc_getAssociatedObject(peek, &DPPeekBackdropKey) : nil;
    NSView *header = backdrop.header;
    if (!header) return;
    NSColor *color = [DPPageColorIn(peek) colorWithAlphaComponent:1];
    header.appearance = nil;
    if (color) {
        NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        CGFloat luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent;
        header.appearance = [NSAppearance appearanceNamed:luminance < 0.5 ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    }
    [header.effectiveAppearance performAsCurrentDrawingAppearance:^{
        header.layer.backgroundColor = (color ?: NSColor.windowBackgroundColor).CGColor;
    }];
}

static void DPPageColorChanged(id contents) {
    [DPWebContentsSeen addObject:contents];
    NSView *view = [contents valueForKey:@"nativeView"];
    if (view.window && DPInPeek(view)) DPPeekTintHeader(view.window);
}

static void DPWebContents_setThemeColor(id self, SEL _cmd, id color) {
    DPCallOriginal(DPWebContents_setThemeColor, self, color);
    DPPageColorChanged(self);
}

static void DPWebContents_setRootBackgroundColor(id self, SEL _cmd, id color) {
    DPCallOriginal(DPWebContents_setRootBackgroundColor, self, color);
    DPPageColorChanged(self);
}

// Dia's handler for the sampled color, on the delegate of the page's WebContents.
static void DPTopBand_didSample(id self, SEL _cmd, id contents, id color, BOOL crossfade) {
    DPCallOriginal(DPTopBand_didSample, self, contents, color, crossfade);
    if (!contents) return;
    DPSet(contents, &DPTopBandColorKey, DPColorFromArc(color));
    DPPageColorChanged(contents);
}

// Hooked only if the handler takes the color as an object, so a changed signature can't be misread.
static void DPHookTopBandColor(void) {
    SEL sel = NSSelectorFromString(@"webContents:didSampleTopBandColor:shouldCrossfade:");
    Method method = class_getInstanceMethod(objc_getClass(DPDiaWebContent), sel);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    char color[8] = "", object[8] = "";
    if (types) method_getArgumentType(method, 3, color, sizeof color), method_getArgumentType(method, 2, object, sizeof object);
    if (!types || color[0] != '@' || object[0] != '@') {
        os_log(DPLog(), "Peek can't follow the page's top color: handler is %{public}s", types ?: "missing");
        return;
    }
    DPHook(DPDiaWebContent, sel, (IMP)DPTopBand_didSample);
}

// A small copy of the card centred on the clicked link, which the Peek grows out of and shrinks back into.
static NSRect DPPeekSeed(NSPoint origin, NSRect card) {
    NSSize size = NSMakeSize(NSWidth(card) * 0.12, NSHeight(card) * 0.12);
    return NSMakeRect(origin.x - size.width / 2, origin.y - size.height / 2, size.width, size.height);
}

#pragma mark - Window scaling

// The window server can draw a window scaled, like the Dock's minimize effect, while the window keeps
// its size, so the page never re-lays out mid-animation. These are private SkyLight calls, looked up
// at runtime so a missing one just means no scaling.
typedef int DPConnection;
static DPConnection (*DPMainConnection)(void);
static CGError (*DPSetWindowTransform)(DPConnection, uint32_t, CGAffineTransform);
static CGError (*DPSetWindowAlpha)(DPConnection, uint32_t, float);

static BOOL DPCanScaleWindows(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DPMainConnection = dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
        DPSetWindowTransform = dlsym(RTLD_DEFAULT, "CGSSetWindowTransform");
        DPSetWindowAlpha = dlsym(RTLD_DEFAULT, "CGSSetWindowAlpha");
    });
    return DPMainConnection && DPSetWindowTransform && DPSetWindowAlpha;
}

// Opacity set through AppKit lands a screen refresh after a transform does, which shows as a flash;
// going through the window server keeps the two in step.
static void DPSetServerAlpha(NSWindow *window, CGFloat alpha) {
    DPSetWindowAlpha(DPMainConnection(), (uint32_t)window.windowNumber, alpha);
}

// Window server coordinates start at the top left of the main screen.
static CGRect DPServerRect(NSRect rect) {
    return CGRectMake(NSMinX(rect), NSHeight(NSScreen.screens.firstObject.frame) - NSMaxY(rect), NSWidth(rect), NSHeight(rect));
}

// Draws the window's full contents squeezed into `shown`. The transform maps screen points to window points.
static void DPShowWindowIn(NSWindow *window, NSRect shown) {
    if (!DPCanScaleWindows()) return;
    CGRect actual = DPServerRect(window.frame), target = DPServerRect(shown);
    CGAffineTransform transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(-CGRectGetMinX(target), -CGRectGetMinY(target)),
        CGAffineTransformMakeScale(CGRectGetWidth(actual) / MAX(CGRectGetWidth(target), 1), CGRectGetHeight(actual) / MAX(CGRectGetHeight(target), 1)));
    DPSetWindowTransform(DPMainConnection(), (uint32_t)window.windowNumber, transform);
}

static NSRect DPLerpRect(NSRect a, NSRect b, CGFloat t) {
    return NSMakeRect(NSMinX(a) + (NSMinX(b) - NSMinX(a)) * t, NSMinY(a) + (NSMinY(b) - NSMinY(a)) * t,
                      NSWidth(a) + (NSWidth(b) - NSWidth(a)) * t, NSHeight(a) + (NSHeight(b) - NSHeight(a)) * t);
}

// Scales the window from one rect to another frame by frame. `curve` eases progress; `fade` maps progress
// to opacity. `settle` puts the window back at its real frame afterwards; a window about to close skips
// that, or it would flash at full size for a frame.
static void DPAnimateWindow(NSWindow *window, NSRect from, NSRect to, CFTimeInterval duration, BOOL settle,
                            CGFloat (^curve)(CGFloat), CGFloat (^fade)(CGFloat), void (^completion)(void)) {
    if (!DPCanScaleWindows()) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = duration;
            window.animator.alphaValue = fade(1);
        } completionHandler:completion];
        return;
    }
    DPShowWindowIn(window, from);
    DPSetServerAlpha(window, fade(0));
    // Dia's main thread is busy setting up a new page as a Peek opens, so the clock starts on the first
    // frame that runs and skips over stalls; otherwise the animation would jump straight to its end.
    __block CFTimeInterval start = 0, last = 0;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *t) {
        CFTimeInterval now = CACurrentMediaTime();
        if (!start) start = last = now;
        if (now - last > 0.05) start += now - last - 1.0 / 60;
        last = now;
        CGFloat progress = MIN(1, (now - start) / duration);
        DPShowWindowIn(window, DPLerpRect(from, to, curve(progress)));
        DPSetServerAlpha(window, fade(progress));
        if (progress < 1) return;
        [t invalidate];
        if (settle) DPShowWindowIn(window, window.frame);
        window.alphaValue = fade(1);
        if (completion) completion();
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

static void DPPeekDress(NSWindow *peek, BOOL embedded) {
    for (NSWindowButton b = NSWindowCloseButton; b <= NSWindowZoomButton; b++) [peek standardWindowButton:b].hidden = embedded;
    peek.excludedFromWindowsMenu = embedded;
    peek.movable = !embedded;
    // The Peek is sized to its card; dragging an edge would pull the page off it.
    static char removedResizableKey;
    if (embedded && (peek.styleMask & NSWindowStyleMaskResizable)) {
        peek.styleMask &= ~NSWindowStyleMaskResizable;
        objc_setAssociatedObject(peek, &removedResizableKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!embedded && objc_getAssociatedObject(peek, &removedResizableKey)) {
        peek.styleMask |= NSWindowStyleMaskResizable;
        objc_setAssociatedObject(peek, &removedResizableKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSWindowCollectionBehavior embeddedBehavior = NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorTransient;
    peek.collectionBehavior = embedded ? peek.collectionBehavior | embeddedBehavior : peek.collectionBehavior & ~embeddedBehavior;
    // A popup's title stays out of the way of the Peek's header, which covers the title bar.
    if (![peek isKindOfClass:objc_getClass(DPDiaPopupWindow)]) return;
    peek.titlebarAppearsTransparent = embedded;
    peek.titleVisibility = embedded ? NSWindowTitleHidden : NSWindowTitleVisible;
}

static void DPPeekTearDown(NSWindow *peek) {
    DPPeekBackdrop *backdrop = objc_getAssociatedObject(peek, &DPPeekBackdropKey);
    if (!backdrop) return;
    objc_setAssociatedObject(peek, &DPPeekBackdropKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DPRelayoutPanesIn(peek);
    for (id observer in backdrop.observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    if (backdrop.monitor) [NSEvent removeMonitor:backdrop.monitor];
    [backdrop.addressTimer invalidate];
    [backdrop.header removeFromSuperview];
    [backdrop.host removeChildWindow:backdrop];
    [backdrop orderOut:nil];
}

// Where the Peek has navigated to: Dia's scripting knows each window's tabs, and the Peek is the
// only window it lists that wasn't there when the link was clicked. Falls back to the link that opened it.
static NSURL *DPPeekCurrentURL(DPPeekBackdrop *backdrop) {
    NSURL *found = nil;
    for (id scripted in [NSApp valueForKey:@"appleScriptWindows"]) {
        if ([backdrop.knownScriptedWindows containsObject:[scripted valueForKey:@"windowId"]]) continue;
        NSString *url = [[scripted valueForKey:@"activeTab"] valueForKey:@"URL"];
        if (!url.length) continue;
        if (found) return backdrop.url;
        found = [NSURL URLWithString:url];
    }
    return found ?: backdrop.url;
}

// Dia's scripting can add a tab to a given window. Its windows only say which tab has focus,
// so the window the Peek came from is brought forward first and found by its focused tab.
static void DPOpenTabInFocusedWindow(NSURL *url) {
    NSString *(^quote)(NSString *) = ^NSString *(NSString *value) {
        return [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    };
    NSString *window = @"window 1";
    for (id scripted in [NSApp valueForKey:@"appleScriptWindows"])
        if ([[[scripted valueForKey:@"activeTab"] valueForKey:@"isFocused"] boolValue]) {
            window = [NSString stringWithFormat:@"(first window whose id is \"%@\")", quote([scripted valueForKey:@"windowId"])];
            break;
        }
    NSString *source = [NSString stringWithFormat:@"tell application id \"%@\" to make new tab at end of tabs of %@ with properties {URL:\"%@\"}",
                        NSBundle.mainBundle.bundleIdentifier, window, quote(url.absoluteString)];
    NSDictionary *error = nil;
    BOOL opened = [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error] != nil;
    if (!opened) os_log(DPLog(), "Peek couldn't open as a tab: %{public}@", error);
}

static void DPPeekHideSidebar(NSWindow *peek, int attempts);
static void DPPeekRestoreSidebar(NSWindow *peek, DPPeekBackdrop *backdrop);

// Like Arc's expand: the Peek's page becomes a tab of the window it came from.
static BOOL DPPeekOpenAsTab(NSWindow *peek, DPPeekBackdrop *backdrop) {
    NSURL *url = DPPeekCurrentURL(backdrop);
    if (!url) return NO;
    NSWindow *host = backdrop.host;
    DPPeekRestoreSidebar(peek, backdrop);
    [host removeChildWindow:peek];
    DPPeekTearDown(peek);
    [peek close];
    [host makeKeyAndOrderFront:nil];
    // Dia moves tab focus to the host asynchronously.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPOpenTabInFocusedWindow(url);
    });
    return YES;
}

static void DPPeekEnd(NSWindow *peek, DPPeekExit exit) {
    DPPeekBackdrop *backdrop = objc_getAssociatedObject(peek, &DPPeekBackdropKey);
    if (!backdrop || backdrop.animating) return;
    NSWindow *host = backdrop.host;
    if (exit == DPPeekExitMaximize && DPPeekOpenAsTab(peek, backdrop)) return;
    if (exit != DPPeekExitClose) {
        // Without a tab to move into, maximize takes over the parent's frame; split shares it.
        NSRect frame = host.frame, left, right;
        NSDivideRect(frame, &left, &right, floor(NSWidth(frame) / 2), NSMinXEdge);
        DPPeekRestoreSidebar(peek, backdrop);
        [host removeChildWindow:peek];
        DPPeekTearDown(peek);
        DPPeekDress(peek, NO);
        if (exit == DPPeekExitSplit) [host setFrame:left display:YES animate:YES];
        [peek setFrame:exit == DPPeekExitSplit ? right : frame display:YES animate:YES];
        [peek makeKeyAndOrderFront:nil];
        return;
    }
    // The page itself shrinks back into the link while the blur clears.
    backdrop.animating = YES;
    [backdrop setChromeAlpha:0 animated:NO];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = DPPeekDuration;
        backdrop.blur.animator.alphaValue = 0;
    }];
    // The shadow would shrink into a dark blot, so it goes, and the page fades over the whole shrink.
    peek.hasShadow = NO;
    DPAnimateWindow(peek, peek.frame, DPPeekSeed(backdrop.origin, peek.frame), DPPeekDuration, NO,
        ^CGFloat(CGFloat t) { return t * t * t; },
        ^CGFloat(CGFloat t) { return pow(1 - t, 1.5); },
        ^{
            peek.alphaValue = 0;
            DPPeekRestoreSidebar(peek, backdrop);
            [peek performClose:nil];
            // A page can refuse to close (beforeunload); bring the Peek back instead of leaving it invisible.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!peek.isVisible || objc_getAssociatedObject(peek, &DPPeekBackdropKey) != backdrop) return;
                peek.alphaValue = backdrop.blur.alphaValue = 1;
                [backdrop setChromeAlpha:1 animated:NO];
                peek.hasShadow = YES;
                DPShowWindowIn(peek, peek.frame);
                DPPeekHideSidebar(peek, 6);
                backdrop.animating = NO;
            });
        });
}

static BOOL DPToggleSidebar(void) { return DPPerformMenuItem(@"s", @"sidebar"); }

// A Peek is just the page, as in Arc: a new Dia window opens with the sidebar as it was last left,
// so it's closed while the Peek is still invisible. Layout can lag the window appearing, hence the retries.
static void DPPeekHideSidebar(NSWindow *peek, int attempts) {
    DPPeekBackdrop *backdrop = objc_getAssociatedObject(peek, &DPPeekBackdropKey);
    if (!backdrop || backdrop.hidSidebar) return;
    if (DPSidebarShownIn(peek)) {
        if (peek.isKeyWindow && DPToggleSidebar()) backdrop.hidSidebar = YES;
        return;
    }
    if (attempts > 0)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DPPeekHideSidebar(peek, attempts - 1);
        });
}

// Dia remembers the sidebar as the last window left it, so the Peek reopens its sidebar before it
// closes or becomes a window of its own; otherwise later windows would open without one.
static void DPPeekRestoreSidebar(NSWindow *peek, DPPeekBackdrop *backdrop) {
    if (!backdrop.hidSidebar || !peek.isKeyWindow) return;
    backdrop.hidSidebar = NO;
    DPToggleSidebar();
}

static void DPPresentPeek(NSWindow *peek, NSWindow *parent) {
    peek.alphaValue = 0;
    DPPeekDress(peek, YES);
    DPPeekBackdrop *backdrop = [[DPPeekBackdrop alloc] initWithPeek:peek host:parent origin:DPPeekOrigin url:DPPeekURL];
    backdrop.knownScriptedWindows = DPPeekKnownScriptedWindows;
    objc_setAssociatedObject(peek, &DPPeekBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DPRelayoutPanesIn(peek);
    backdrop.alphaValue = 0;
    [parent addChildWindow:backdrop ordered:NSWindowAbove];
    [peek setFrame:backdrop.peekFrame display:NO];
    [parent addChildWindow:peek ordered:NSWindowAbove];
    [peek orderWindow:NSWindowAbove relativeTo:backdrop.windowNumber];
    [backdrop layoutPeek];
    DPPeekTintHeader(peek);
    DPPeekHideSidebar(peek, 6);

    // The page itself grows out of the clicked link, settling with a slight ease like Arc's spring.
    backdrop.animating = YES;
    CFTimeInterval grow = DPPeekDuration * 1.4;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = grow;
        backdrop.animator.alphaValue = 1;
    }];
    NSRect card = backdrop.peekFrame;
    DPAnimateWindow(peek, DPPeekSeed(backdrop.origin, card), card, grow, YES,
        ^CGFloat(CGFloat t) { CGFloat omega = 9; return 1 - (1 + omega * t) * exp(-omega * t); },
        ^CGFloat(CGFloat t) { return MIN(1, t * 4); },
        ^{
            backdrop.animating = NO;
            [backdrop layoutPeek];
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.15;
                [backdrop setChromeAlpha:1 animated:YES];
            }];
        });

    // Escape closes Peek, as in Arc.
    __weak NSWindow *weakPeek = peek;
    backdrop.monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        NSWindow *p = weakPeek;
        if (!p || event.window != p || event.keyCode != 53 || event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) return event;
        DPPeekEnd(p, DPPeekExitClose);
        return nil;
    }];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    __weak DPPeekBackdrop *weakBackdrop = backdrop;
    [backdrop.observers addObject:[center addObserverForName:NSWindowWillCloseNotification object:peek queue:nil usingBlock:^(NSNotification *note) {
        DPPeekTearDown(note.object);
    }]];
    for (NSNotificationName name in @[NSWindowDidResizeNotification, NSWindowDidMoveNotification])
        [backdrop.observers addObject:[center addObserverForName:name object:parent queue:nil usingBlock:^(NSNotification *note) {
            [weakBackdrop layoutPeek];
        }]];
    // The Peek stays centred in its window at its card's size: anything that moves or resizes it, it snaps back.
    for (NSNotificationName name in @[NSWindowDidMoveNotification, NSWindowDidResizeNotification])
        [backdrop.observers addObject:[center addObserverForName:name object:peek queue:nil usingBlock:^(NSNotification *note) {
            [weakBackdrop layoutPeek];
        }]];
}

// Dia puts a new window on screen before it becomes key, which is when the Peek is claimed; one that
// may be a Peek starts invisible so it doesn't flash at full size before growing out of the link.
static void DPWindow_orderWindow(NSWindow *self, SEL _cmd, NSWindowOrderingMode place, NSInteger relativeTo) {
    if (place != NSWindowOut && !self.isVisible && DPPeekCandidate(self)) self.alphaValue = 0;
    DPCallOriginal(DPWindow_orderWindow, self, place, relativeTo);
}

static void DPPeekWindowAppeared(NSNotification *note) {
    NSWindow *window = note.object, *parent = DPPeekParent;
    // The first browser window Dia opens for the link becomes the Peek, popup or not.
    if (!DPPeekCandidate(window) || objc_getAssociatedObject(window, &DPPeekBackdropKey)) return;
    DPPeekPendingUntil = 0;
    os_log(DPLog(), "Peek claimed a %{public}@ %.0f ms after the click", NSStringFromClass(window.class), (CACurrentMediaTime() - DPShiftClickAt) * 1000);
    DPPresentPeek(window, parent);
}

static void DPInstallPeek(void) {
    DPHook(DPDiaWebContent, NSSelectorFromString(@"webContents:didCreateNewWebContent:targetURL:disposition:"), (IMP)DPWebContent_didCreate);
    DPHook(DPDiaWebContent, NSSelectorFromString(@"webContents:decidePolicyForNavigationAction:"), (IMP)DPWebContent_decidePolicy);
    DPHook(DPDiaNavigationAction, NSSelectorFromString(@"navigationDisposition"), (IMP)DPNavigationAction_disposition);
    DPHook(DPDiaPlatformWindow, @selector(orderWindow:relativeTo:), (IMP)DPWindow_orderWindow);
    DPHook(DPDiaPopupContent, @selector(layout), (IMP)DPPopupContent_layout);
    DPWebContentsSeen = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaArcWebContents, @selector(setThemeColor:), (IMP)DPWebContents_setThemeColor);
    DPHook(DPDiaArcWebContents, @selector(setRootBackgroundColor:), (IMP)DPWebContents_setRootBackgroundColor);
    DPHookTopBandColor();
    DPPeekWatchClicks();
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) { DPPeekWindowAppeared(note); }];
}

// Hooks check the switch on each click, so turning it on or off needs nothing else.
static void DPApplyPeek(DPPatch *patch) {}

DP_PATCH(DPPeek) {
    .key = @"peek",
    .order = 90,
    .title = @"Peek on Shift-click",
    .detail = @"Shift-click a link to preview it over the current page, like Arc. Click outside or press Escape to close. Experimental.",
    .symbol = @"eye.fill",
    .tint = @"systemGreenColor",
    .classes = DPClasses(DPDiaWebContent, DPDiaNavigationAction, DPDiaPlatformWindow, DPDiaPopupWindow, DPDiaPopupContent, DPDiaArcWebContents),
    .install = DPInstallPeek,
    .apply = DPApplyPeek,
};
