#import "StdPatch/StdPatch.h"

extern DPPatch DPProfileEmoji;

@interface NSObject (DPSwiftFields)
- (id)safeSwiftValueForKey:(NSString *)key;  // AXCoreUtilities, in every AppKit app
@end

static NSString *const DPEmojisKey = @"profileEmojis";
// The gap is between what's drawn, so emoji and dots sit the same distance apart in any mix.
static const CGFloat DPSidebarEmojiSize = 13.5, DPSidebarEmojiWidth = 16, DPSidebarDotWidth = 6, DPSidebarGap = 10;
static NSUserDefaults *DPEmojiDefaults;
static char DPLabelKey, DPFieldKey;

static NSString *DPEmoji(NSString *spaceID) {
    return DPProfileEmoji.on && spaceID ? [DPEmojiDefaults dictionaryForKey:DPEmojisKey][spaceID] : nil;
}

// Keys are Swift SpaceIDs, which describe themselves as the ID.
static NSString *DPSpaceIDOf(NSView *view, NSDictionary *views) {
    for (id key in views) if (views[key] == view) return [key description];
    return nil;
}

static void DPShowEmoji(NSView *host, NSView *dot, NSString *emoji, CGFloat size, CGFloat alpha) {
    NSTextField *label = DPGet(host, &DPLabelKey);
    if (!emoji) {
        if (!label) return;
        dot.hidden = NO;
        [label removeFromSuperview];
        DPSet(host, &DPLabelKey, nil);
        return;
    }
    dot.hidden = YES;
    if (!label) {
        label = [NSTextField labelWithString:@""];
        label.alignment = NSTextAlignmentCenter;
        [host addSubview:label];
        DPSet(host, &DPLabelKey, label);
    }
    label.stringValue = emoji;
    label.font = [NSFont systemFontOfSize:size];
    label.alphaValue = alpha;
    [label sizeToFit];
    label.frame = (NSRect){ { NSMidX(host.bounds) - label.frame.size.width / 2, NSMidY(host.bounds) - label.frame.size.height / 2 }, label.frame.size };
}

static void DPShowSidebarItem(NSView *item) {
    NSString *emoji = DPEmoji(DPSpaceIDOf(item, [item.superview safeSwiftValueForKey:@"itemViews"]));
    BOOL selected = [[item safeSwiftValueForKey:@"isSelected"] boolValue];
    NSView *dot = [item safeSwiftValueForKey:@"$__lazy_storage_$_dotView"];
    [dot setFrameOrigin:NSMakePoint(round(NSMidX(item.bounds) - NSWidth(dot.frame) / 2), NSMinY(dot.frame))];
    DPShowEmoji(item, dot, emoji, DPSidebarEmojiSize, selected ? 1 : 0.45);
}

static CGFloat DPSidebarItemWidth(NSView *item, NSDictionary *views) {
    return (DPEmoji(DPSpaceIDOf(item, views)) ? DPSidebarEmojiWidth : DPSidebarDotWidth) + DPSidebarGap;
}

// Dia packs items 12 points apart, which crowds emoji, so each item gets its own width and the row stays centered.
// Dia also places items outside layout, such as after switching profiles.
static void DPSidebarItem_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSView *switcher = self.superview;
    NSDictionary *views = [switcher safeSwiftValueForKey:@"itemViews"];
    BOOL anyEmoji = NO;
    for (id key in views) anyEmoji = anyEmoji || DPEmoji([key description]);
    if (anyEmoji && NSWidth(frame) > 0 && NSWidth(frame) < DPSidebarDotWidth + DPSidebarGap) {
        CGFloat middle = NSMidX(switcher.bounds);
        NSInteger index = lround((NSMinX(frame) - (middle - views.count * NSWidth(frame) / 2)) / NSWidth(frame));
        NSMutableArray<NSView *> *row = [[views.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self != %@", self]] mutableCopy];
        [row sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) { return [@(NSMidX(a.frame)) compare:@(NSMidX(b.frame))]; }];
        [row insertObject:self atIndex:MIN(MAX(index, 0), (NSInteger)row.count)];
        CGFloat total = 0, x = 0;
        for (NSView *item in row) total += DPSidebarItemWidth(item, views);
        for (NSView *item in row) {
            if (item == self) break;
            x += DPSidebarItemWidth(item, views);
        }
        frame = NSMakeRect(round(middle - total / 2 + x), NSMinY(frame), DPSidebarItemWidth(self, views), NSHeight(frame));
    }
    DPCallOriginal(DPSidebarItem_setFrame, self, frame);
}

static void DPSidebarItem_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarItem_layout, self);
    DPShowSidebarItem(self);
}

static void DPSidebarItem_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarItem_updateLayer, self);
    DPShowSidebarItem(self);
}

static void DPTopDot_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTopDot_layout, self);
    NSView *indicator = self.superview;
    NSString *spaceID = DPSpaceIDOf(self, [indicator safeSwiftValueForKey:@"dotViews"]);
    BOOL focused = [[[indicator safeSwiftValueForKey:@"focusedSpaceID"] description] isEqual:spaceID];
    DPShowEmoji(self, self.subviews.firstObject, DPEmoji(spaceID), 8, focused ? 1 : 0.45);
}

static void DPRefresh(DPPatch *patch) {
    for (NSString *name in @[ @DPDiaSpaceSwitcher, @DPDiaSpaceSwitcherItem, @DPDiaPageIndicatorDot ])
        for (NSView *view in DPFindViews(name.UTF8String)) view.needsLayout = YES;
}

@interface DPEmojiField : NSTextField <NSTextFieldDelegate>
@property(copy) NSString *spaceID;
@end

@implementation DPEmojiField
- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    if (became) dispatch_async(dispatch_get_main_queue(), ^{ [NSApp orderFrontCharacterPalette:self]; });
    return became;
}

- (void)controlTextDidChange:(NSNotification *)note {
    __block NSString *last = @"";
    [self.stringValue enumerateSubstringsInRange:NSMakeRange(0, self.stringValue.length) options:NSStringEnumerationByComposedCharacterSequences
                                      usingBlock:^(NSString *character, NSRange _, NSRange __, BOOL *___) { last = character; }];
    last = [last stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self.stringValue isEqual:last]) self.stringValue = last;
    NSMutableDictionary *emoji = [[DPEmojiDefaults dictionaryForKey:DPEmojisKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    emoji[self.spaceID] = last.length ? last : nil;
    [DPEmojiDefaults setObject:emoji forKey:DPEmojisKey];
    DPRefresh(&DPProfileEmoji);
}
@end

static void DPAddEmojiRow(NSViewController *pane) {
    NSView *group = DPFindView(pane.view, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSettingsFormGroup); });
    NSStackView *rows = (NSStackView *)DPSubview(group, "NSStackView");
    NSTextField *title = (NSTextField *)DPFindView(rows.arrangedSubviews.firstObject, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    NSString *spaceID = [[pane safeSwiftValueForKey:@"spaceID"] description];
    if (!rows || !title || !spaceID || DPGet(pane, &DPFieldKey)) return;

    NSTextField *label = [NSTextField labelWithString:@"Emoji"];
    label.font = title.font;
    label.textColor = title.textColor;
    DPEmojiField *field = [DPEmojiField textFieldWithString:[DPEmojiDefaults dictionaryForKey:DPEmojisKey][spaceID] ?: @""];
    field.spaceID = spaceID;
    field.delegate = field;
    field.alignment = NSTextAlignmentCenter;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.placeholderString = @"None";
    NSView *row = [NSView new];
    for (NSView *view in @[ label, field ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:view];
    }
    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;
    [rows addArrangedSubview:line];
    [rows addArrangedSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:42], [row.widthAnchor constraintEqualToAnchor:rows.widthAnchor],
        [line.widthAnchor constraintEqualToAnchor:rows.widthAnchor],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor], [field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.widthAnchor constraintEqualToConstant:64],
    ]];
    DPSet(pane, &DPFieldKey, field);
}

static void DPProfilePane_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPProfilePane_viewDidLoad, self);
    if (DPProfileEmoji.on) DPAddEmojiRow(self);
}

static void DPInstallProfileEmoji(void) {
    DPEmojiDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPHookClass(objc_getClass(DPDiaSpaceSwitcherItem), @selector(setFrame:), (IMP)DPSidebarItem_setFrame);
    DPHook(DPDiaSpaceSwitcherItem, @selector(layout), (IMP)DPSidebarItem_layout);
    DPHook(DPDiaSpaceSwitcherItem, @selector(updateLayer), (IMP)DPSidebarItem_updateLayer);
    DPHook(DPDiaPageIndicatorDot, @selector(layout), (IMP)DPTopDot_layout);
    DPHook(DPDiaProfilePane, @selector(viewDidLoad), (IMP)DPProfilePane_viewDidLoad);
}

DP_PATCH(DPProfileEmoji) {
    .key = @"profileEmoji",
    .order = 78,
    .defaultOn = YES,
    .title = @"Profile emoji",
    .detail = @"Adds an emoji to each profile in Settings → Profiles, shown in place of the profile's dot in the profile switcher.",
    .symbol = @"face.smiling",
    .tint = @"systemYellowColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaSpaceSwitcher, DPDiaSpaceSwitcherItem, DPDiaPageIndicatorDot, DPDiaProfilePane, DPDiaSettingsFormGroup),
    .install = DPInstallProfileEmoji,
    .apply = DPRefresh,
};
