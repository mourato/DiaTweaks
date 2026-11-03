#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import <objc/message.h>

extern DPPatch DPWindowCorners;
static const CGFloat DPRadius = 26;
static char DPRadiusKey, DPPathKey, DPMaskPathKey, DPShadowPathKey;
#define DPCornerBars (@[ @DPDiaTabStrip, @DPDiaSidebarHeader, @DPDiaSidebarFooter ])

static CGFloat DPCornerRadius(NSWindow *window) { return ((CGFloat (*)(id, SEL))objc_msgSend)(window, @selector(_cornerRadius)); }

CGFloat DPWindowCornerGrowth(NSWindow *window) {
    if (!DPWindowCorners.on || !DPIsKind(window, DPDiaWindow)) return 0;
    CGFloat current = DPCornerRadius(window);
    return DPRadius - [DPDiaValue(window, &DPRadiusKey, @(current)) doubleValue];
}

static void DPRoundWindow(NSWindow *window) {
    CGFloat current = DPCornerRadius(window), dia = [DPDiaValue(window, &DPRadiusKey, @(current)) doubleValue];
    CGFloat target = DPWindowCorners.on ? DPRadius : dia;
    DPOverride(window, &DPRadiusKey, @(dia), @(target));
    if (current == target) return;
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(window, @selector(_setCornerRadius:), target);
    ((void (*)(id, SEL))objc_msgSend)(window, @selector(_updateWindowCornerMask));
    [window invalidateShadow];
}

// Icons, under 10 points, keep their corners.
static void DPRoundLayers(CALayer *layer, CGFloat growth) {
    CGFloat dia = [DPDiaValue(layer, &DPRadiusKey, @(layer.cornerRadius)) doubleValue];
    if (dia >= 10) {
        CGFloat target = MIN(dia + growth, MAX(dia, MIN(CGRectGetWidth(layer.bounds), CGRectGetHeight(layer.bounds)) / 2));
        DPOverride(layer, &DPRadiusKey, @(dia), @(target));
        if (layer.cornerRadius != target) layer.cornerRadius = target;
    }
    for (CALayer *sublayer in layer.sublayers) DPRoundLayers(sublayer, growth);
}

static void DPRoundCornerItems(NSView *root) {
    NSView *frame = root.window.contentView.superview;
    CGFloat growth = DPWindowCornerGrowth(root.window);
    if (!frame) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPFindView(root, ^BOOL(NSView *view) {
        if (view == root || view.layer.cornerRadius < 10) return NO;
        NSRect rect = [view convertRect:view.bounds toView:frame], bounds = frame.bounds;
        BOOL side = NSMinX(rect) < DPRadius || NSMaxX(rect) > NSMaxX(bounds) - DPRadius;
        BOOL end = NSMinY(rect) < DPRadius || NSMaxY(rect) > NSMaxY(bounds) - DPRadius;
        DPRoundLayers(view.layer, side && end ? growth : 0);
        return NO;
    });
    [CATransaction commit];
}

static CGPathRef DPScaledPath(id owner, char *key, CGPathRef current, CGSize size, CGFloat base, CGFloat scale) {
    CGRect box = CGPathGetBoundingBox(current);
    if (!current || fabs(box.size.width - size.width) > 1 || fabs(box.size.height - size.height) > 1) return NULL;
    id dia = DPDiaValue(owner, key, (__bridge id)current);
    if (dia == (__bridge id)current) dia = CFBridgingRelease(CGPathCreateCopy(current));
    CGPathRef path = DPReshapeCorners((__bridge CGPathRef)dia, base * 1.6, scale, scale);
    DPOverride(owner, key, dia, (__bridge id)path);
    return CGPathEqualToPath(path, current) ? NULL : path;
}

static void DPRoundFloatingLayers(CALayer *layer, CGSize size, CGFloat base, CGFloat growth) {
    if (fabs(layer.bounds.size.width - size.width) < 1 && fabs(layer.bounds.size.height - size.height) < 1 && layer.cornerRadius > 0) {
        CGFloat dia = [DPDiaValue(layer, &DPRadiusKey, @(layer.cornerRadius)) doubleValue];
        DPOverride(layer, &DPRadiusKey, @(dia), @(dia + growth));
        if (layer.cornerRadius != dia + growth) layer.cornerRadius = dia + growth;
    }
    CGFloat scale = (base + growth) / base;
    CAShapeLayer *shape = [layer isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)layer : nil;
    CAShapeLayer *mask = [layer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)layer.mask : nil;
    CGPathRef path;
    if ((path = DPScaledPath(shape, &DPPathKey, shape.path, size, base, scale))) shape.path = path;
    if ((path = DPScaledPath(mask, &DPMaskPathKey, mask.path, size, base, scale))) mask.path = path;
    if ((path = DPScaledPath(layer, &DPShadowPathKey, layer.shadowPath, size, base, scale))) layer.shadowPath = path;
    for (CALayer *sublayer in layer.sublayers) DPRoundFloatingLayers(sublayer, size, base, growth);
}

// Dia also rounds the floating sidebar outside layout, so its corner radius is watched.
static void DPRoundFloatingSidebar(NSView *self);

@interface DPFloatingCornerWatch : NSObject
@end

@implementation DPFloatingCornerWatch
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(CALayer *)layer change:(NSDictionary *)change context:(void *)context {
    __weak NSView *sidebar = (NSView *)layer.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{ if (sidebar.layer == layer) DPRoundFloatingSidebar(sidebar); });
}
@end

static DPFloatingCornerWatch *DPCornerWatch;
static char DPWatchedKey;

static void DPRoundFloatingSidebar(NSView *self) {
    if (self.layer && DPGet(self, &DPWatchedKey) != self.layer) {
        [self.layer addObserver:DPCornerWatch forKeyPath:@"cornerRadius" options:0 context:NULL];
        DPSet(self, &DPWatchedKey, self.layer);
    }
    CGFloat base = [DPDiaValue(self.layer, &DPRadiusKey, @(self.layer.cornerRadius)) doubleValue];
    if (base <= 0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPRoundFloatingLayers(self.layer, self.bounds.size, base, DPWindowCornerGrowth(self.window));
    [CATransaction commit];
}

static void DPFloatingSidebar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFloatingSidebar_layout, self);
    DPRoundFloatingSidebar(self);
}

static void DPBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBar_layout, self);
    DPRoundCornerItems(self);
}

static void DPLayer_addAnimation(CALayer *self, SEL _cmd, CAAnimation *animation, NSString *key) {
    DPCallOriginal(DPLayer_addAnimation, self, DPWindowCorners.on ? DPReshapeDiaAnimation(self, animation) : animation, key);
}

static void DPShapeLayer_setPath(CAShapeLayer *self, SEL _cmd, CGPathRef path) {
    DPCallOriginal(DPShapeLayer_setPath, self, DPWindowCorners.on ? DPReshapeSetPath(self, NO, path) : path);
}

static void DPLayer_setShadowPath(CALayer *self, SEL _cmd, CGPathRef path) {
    DPCallOriginal(DPLayer_setShadowPath, self, DPWindowCorners.on ? DPReshapeSetPath(self, YES, path) : path);
}

// Dia tiles the blurred background around the page. Rounder corners expose the seams, which flash as the sidebar slides.
static void DPBackgroundTile_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSView *background = self.superview;
    BOOL whole = DPWindowCorners.on && DPIsKind(background, DPDiaWindowBackground);
    DPCallOriginal(DPBackgroundTile_setFrame, self, whole ? background.bounds : frame);
}

static void DPNavigationBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNavigationBar_layout, self);
    NSView *container = self;
    while (container && !DPIsKind(container, DPDiaContentContainer)) container = container.superview;
    if (container) DPRoundCornerControls(container);
}

static void DPWindow_becomeKey(NSWindow *self, SEL _cmd) {
    DPCallOriginal(DPWindow_becomeKey, self);
    DPRoundWindow(self);
}

static void DPApplyWindowCorners(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) if (DPIsKind(window, DPDiaWindow)) DPRoundWindow(window);
    for (NSString *bar in DPCornerBars) for (NSView *view in DPFindViews(bar.UTF8String)) DPRoundCornerItems(view);
    for (NSView *view in DPFindViews(DPDiaFloatingSidebar)) view.needsLayout = YES;
    for (NSView *background in DPFindViews(DPDiaWindowBackground)) {
        background.needsLayout = YES;
        for (NSView *tile in background.subviews) tile.frame = tile.frame;
    }
    DPEdgeToEdge.relayout();
}

static NSString *DPVerifyWindowCorners(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows)
        if (DPIsKind(window, DPDiaWindow) && window.isVisible && (DPCornerRadius(window) == DPRadius) != patch->on)
            return patch->on ? @"window corners aren't 26 points" : @"window corners stay 26 points";
    return nil;
}

static void DPInstallWindowCorners(void) {
    DPCornerWatch = [DPFloatingCornerWatch new];
    DPHook(DPDiaWindow, @selector(becomeKeyWindow), (IMP)DPWindow_becomeKey);
    DPHook(DPDiaFloatingSidebar, @selector(layout), (IMP)DPFloatingSidebar_layout);
    DPHook(DPDiaWindowBackgroundTile, @selector(setFrame:), (IMP)DPBackgroundTile_setFrame);
    DPHook(DPDiaNavigationBar, @selector(layout), (IMP)DPNavigationBar_layout);
    DPHookClass(CALayer.class, @selector(addAnimation:forKey:), (IMP)DPLayer_addAnimation);
    DPHookClass(CALayer.class, @selector(setShadowPath:), (IMP)DPLayer_setShadowPath);
    DPHookClass(CAShapeLayer.class, @selector(setPath:), (IMP)DPShapeLayer_setPath);
    for (NSString *bar in DPCornerBars) DPHook(bar.UTF8String, @selector(layout), (IMP)DPBar_layout);
    DPOnLaunch(^{ DPApplyWindowCorners(&DPWindowCorners); });
}

DP_PATCH(DPWindowCorners) {
    .key = @"windowCorners",
    .order = 91,
    .title = @"macOS 26 window corners",
    .detail = @"Round browser windows to 26 points like other apps on macOS 26, with the page's corners rounded to match.",
    .symbol = @"macwindow",
    .tint = @"systemTealColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaWindow, DPDiaNavigationBar, DPDiaFloatingSidebar, DPDiaWindowBackgroundTile, DPDiaWindowBackground, DPDiaTabStrip, DPDiaSidebarHeader, DPDiaSidebarFooter),
    .install = DPInstallWindowCorners,
    .apply = DPApplyWindowCorners,
    .verify = DPVerifyWindowCorners,
};
