#import "StdPatch/StdPatch.h"

extern DPPatch DPWindowMaterial, DPTranslucentSidebar;
static char DPHiddenKey, DPDiaHiddenKey, DPMaterialKey, DPGlassKey, DPOpaqueKey;

static NSString *const DPMaterials[] = {
    [NSVisualEffectMaterialSidebar] = @"Sidebar",
    [NSVisualEffectMaterialUnderWindowBackground] = @"Under Window Background",
    [NSVisualEffectMaterialHeaderView] = @"Header",
    [NSVisualEffectMaterialTitlebar] = @"Titlebar",
    [NSVisualEffectMaterialMenu] = @"Menu",
    [NSVisualEffectMaterialPopover] = @"Popover",
    [NSVisualEffectMaterialHUDWindow] = @"HUD Window",
    [NSVisualEffectMaterialFullScreenUI] = @"Full Screen UI",
    [NSVisualEffectMaterialToolTip] = @"Tooltip",
};

// NSGlassEffectView's `_variant`s, in AppKit's order.
static NSString *const DPGlasses[] = {
    @"Regular", @"Clear", @"Dock", @"App Icons", @"Widgets", @"Text", @"AV Player", @"FaceTime", @"Control Center",
    @"Notification Center", @"Monogram", @"Bubbles", @"Identity", @"Focus Border", @"Focus Platter", @"Keyboard",
    @"Sidebar", @"Abutted Sidebar", @"Inspector", @"Control", @"Loupe", @"Slider", @"Camera", @"Cartouche Popover",
};

static NSMenu *DPMaterialChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Material"];
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"Materials"]];
    for (NSUInteger i = 0; i < sizeof DPMaterials / sizeof *DPMaterials; i++)
        if (DPMaterials[i]) [menu addItemWithTitle:DPMaterials[i] action:nil keyEquivalent:@""].representedObject = [NSString stringWithFormat:@"material.%lu", i];
    if (!NSClassFromString(@"NSGlassEffectView")) return menu;
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"Liquid Glass"]];
    for (NSUInteger i = 0; i < sizeof DPGlasses / sizeof *DPGlasses; i++)
        [menu addItemWithTitle:DPGlasses[i] action:nil keyEquivalent:@""].representedObject = [NSString stringWithFormat:@"glass.%lu", i];
    return menu;
}

// Dia shows and hides these views too, so its last say is kept for when the patch lets go.
static void DPView_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPSet(self, &DPDiaHiddenKey, @(hidden));
    DPCallOriginal(DPView_setHidden, self, hidden || [DPGet(self, &DPHiddenKey) boolValue]);
}

static void DPHide(NSView *view, BOOL hide) {
    if (!DPGet(view, &DPDiaHiddenKey)) DPSet(view, &DPDiaHiddenKey, @(view.hidden));
    DPHookClass(view.class, @selector(setHidden:), (IMP)DPView_setHidden);
    DPSet(view, &DPHiddenKey, @(hide));
    view.hidden = [DPGet(view, &DPDiaHiddenKey) boolValue];
}

static void DPCollectEffects(NSView *view, NSMutableArray<NSVisualEffectView *> *effects) {
    if ([view isKindOfClass:NSVisualEffectView.class]) [effects addObject:(NSVisualEffectView *)view];
    for (NSView *sub in view.subviews) DPCollectEffects(sub, effects);
}

static NSView *DPTintIn(NSView *view);

static NSVisualEffectMaterial DPWindowBackgroundMaterial(NSWindow *window) {
    NSView *effect = DPFindView(DPTintIn(window.contentView.superview).superview, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSVisualEffectView.class] && !view.isHiddenOrHasHiddenAncestor;
    });
    return effect ? ((NSVisualEffectView *)effect).material : NSVisualEffectMaterialUnderWindowBackground;
}

// The window and the floating sidebar each stack effect views under a theme tint.
static void DPApplyMaterialUnder(NSView *tint, BOOL floating) {
    NSView *content = tint.superview;
    if (!content) return;
    NSString *choice = DPWindowMaterial.on ? DPChoice(&DPWindowMaterial) : nil;
    BOOL translucent = choice || (floating && DPTranslucentSidebar.on), glass = [choice hasPrefix:@"glass."];
    NSInteger value = choice.pathExtension.integerValue;

    NSMutableArray<NSView *> *backgrounds = [NSMutableArray array];
    if (!floating) for (NSView *view in content.superview.subviews) if ([view isKindOfClass:NSVisualEffectView.class]) [backgrounds addObject:view];
    NSView *glassView = DPGet(content, &DPGlassKey);
    for (NSView *view in content.subviews) {
        if (view == tint) break;
        if (view != glassView) [backgrounds addObject:view];
    }
    NSMutableArray<NSVisualEffectView *> *effects = [NSMutableArray array];
    for (NSView *view in backgrounds) DPCollectEffects(view, effects);
    NSVisualEffectBlendingMode blending = floating ? NSVisualEffectBlendingModeWithinWindow : NSVisualEffectBlendingModeBehindWindow;
    for (NSVisualEffectView *effect in effects) {
        NSArray *dia = DPDiaValue(effect, &DPMaterialKey, @[ @(effect.material), @(effect.blendingMode), @(effect.state) ]);
        NSArray *ours = translucent && !glass ? @[ @(choice ? value : DPWindowBackgroundMaterial(tint.window)), @(blending), @(NSVisualEffectStateActive) ] : dia;
        DPOverride(effect, &DPMaterialKey, dia, ours);
        effect.material = [ours[0] integerValue];
        effect.blendingMode = [ours[1] integerValue];
        effect.state = [ours[2] integerValue];
    }
    DPHide(tint, translucent);
    for (NSView *view in backgrounds) DPHide(view, glass);

    // A drawn glass view ignores a new variant.
    if (glassView && (!glass || [[glassView valueForKey:@"_variant"] integerValue] != value)) {
        [glassView removeFromSuperview];
        DPSet(content, &DPGlassKey, glassView = nil);
    }
    if (glass && !glassView) {
        glassView = [[NSClassFromString(@"NSGlassEffectView") alloc] initWithFrame:content.bounds];
        glassView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [glassView setValue:@(content.layer.cornerRadius) forKey:@"cornerRadius"];
        [content addSubview:glassView positioned:NSWindowBelow relativeTo:nil];
        DPSet(content, &DPGlassKey, glassView);
        [glassView setValue:@(value) forKey:@"_variant"];
    }
    if (floating) return;

    NSWindow *window = tint.window;
    NSArray *dia = DPDiaValue(window, &DPOpaqueKey, @[ @(window.opaque), window.backgroundColor ]);
    NSArray *ours = translucent ? @[ @NO, NSColor.clearColor ] : dia;
    DPOverride(window, &DPOpaqueKey, dia, ours);
    if (window.opaque != [ours[0] boolValue]) window.opaque = [ours[0] boolValue];
    if (![window.backgroundColor isEqual:ours[1]]) window.backgroundColor = ours[1];
}

// Not the selected tab's own copy, which sits deeper.
static NSView *DPTintIn(NSView *view) {
    for (NSView *sub in view.subviews)
        for (NSView *inner in sub.subviews) if (DPIsKind(inner, DPDiaWindowTint)) return inner;
    return nil;
}

static NSArray<NSView *> *DPWindowFrames(void) {
    NSMutableArray *frames = [NSMutableArray array];
    for (NSWindow *window in NSApp.windows) if (DPIsKind(window.contentView.superview, DPDiaWindowFrame)) [frames addObject:window.contentView.superview];
    return frames;
}

// A hidden tint stops laying out, the theme frame doesn't.
static void DPWindowFrame_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPWindowFrame_layout, self);
    DPApplyMaterialUnder(DPTintIn(self), NO);
}

static void DPFloatingSidebar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFloatingSidebar_layout, self);
    DPApplyMaterialUnder(DPTintIn(self), YES);
}

// Dia sets its own material again whenever a background redraws.
static void DPBackgroundTile_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBackgroundTile_updateLayer, self);
    for (NSView *host = self.superview; host; host = host.superview) {
        NSView *tint = DPTintIn(host);
        if (tint) return DPApplyMaterialUnder(tint, DPIsKind(host, DPDiaFloatingSidebar));
    }
}

void DPApplyWindowMaterial(DPPatch *patch) {
    for (NSView *frame in DPWindowFrames()) DPApplyMaterialUnder(DPTintIn(frame), NO);
    for (NSView *sidebar in DPFindViews(DPDiaFloatingSidebar)) DPApplyMaterialUnder(DPTintIn(sidebar), YES);
}

NSString *DPVerifyWindowMaterial(DPPatch *patch) {
    BOOL glass = DPWindowMaterial.on && [DPChoice(&DPWindowMaterial) hasPrefix:@"glass."];
    NSArray<NSView *> *floating = DPFindViews(DPDiaFloatingSidebar);
    for (NSView *host in [DPWindowFrames() arrayByAddingObjectsFromArray:floating]) {
        NSView *tint = DPTintIn(host);
        BOOL translucent = DPWindowMaterial.on || (DPTranslucentSidebar.on && [floating containsObject:host]);
        if (!tint) return @"no theme color to replace";
        if (tint.hidden != translucent) return translucent ? @"theme color still shows" : @"theme color still hidden";
        if ((DPGet(tint.superview, &DPGlassKey) != nil) != glass) return glass ? @"no glass behind the window" : @"glass left behind";
        NSVisualEffectView *effect = (NSVisualEffectView *)DPFindView(tint.superview, ^BOOL(NSView *view) {
            return [view isKindOfClass:NSVisualEffectView.class] && !view.isHiddenOrHasHiddenAncestor;
        });
        if (DPWindowMaterial.on && !glass && effect.material != DPChoice(&DPWindowMaterial).pathExtension.integerValue) return @"Dia's material came back";
    }
    return nil;
}

static void DPInstallWindowMaterial(void) {
    DPHook(DPDiaWindowFrame, @selector(layout), (IMP)DPWindowFrame_layout);
    DPHook(DPDiaFloatingSidebar, @selector(layout), (IMP)DPFloatingSidebar_layout);
    DPHook(DPDiaWindowBackgroundTile, @selector(updateLayer), (IMP)DPBackgroundTile_updateLayer);
}

DP_PATCH(DPWindowMaterial) {
    .key = @"windowMaterial",
    .order = 93,
    .title = @"Window material",
    .detail = @"Show a material or Liquid Glass behind the tabs and sidebar instead of the theme color.",
    .symbol = @"square.on.square.intersection.dashed",
    .tint = @"systemCyanColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaWindowFrame, DPDiaWindowTint, DPDiaWindowBackgroundTile, DPDiaFloatingSidebar),
    .choice = @"windowMaterialChoice",
    .defaultChoice = @"glass.17",
    .choices = DPMaterialChoices,
    .install = DPInstallWindowMaterial,
    .apply = DPApplyWindowMaterial,
    .verify = DPVerifyWindowMaterial,
};
