#import "Settings.h"

NSView *DPGroup(NSArray<NSView *> *rows) {
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 0;
    [rows enumerateObjectsUsingBlock:^(NSView *row, NSUInteger i, BOOL *_) {
        if (i > 0) {
            NSBox *line = [NSBox new];
            line.boxType = NSBoxSeparator;
            [stack addArrangedSubview:line];
            [line.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
        }
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }];
    DPFillView *box = [DPFillView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    ]];
    return box;
}

NSView *DPRow(NSView *leading, NSView *trailing) {
    NSView *row = [NSView new];
    for (NSView *v in @[leading, trailing]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:v];
    }
    [trailing setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [leading.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [leading.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [leading.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],
        [trailing.leadingAnchor constraintGreaterThanOrEqualToAnchor:leading.trailingAnchor constant:12],
        [trailing.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [trailing.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

static NSSwitch *DPSwitchIn(NSView *view) {
    if ([view isKindOfClass:NSSwitch.class]) return (NSSwitch *)view;
    for (NSView *subview in view.subviews) {
        NSSwitch *found = DPSwitchIn(subview);
        if (found) return found;
    }
    return nil;
}

@interface DPLinkRowView : NSView
@property (nonatomic, copy) void (^open)(void);
@end

@implementation DPLinkRowView
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    BOOL control = [hit isKindOfClass:NSSwitch.class] || [hit isKindOfClass:NSButton.class];
    return !hit || (control && ((NSControl *)hit).enabled) || hit.toolTip ? hit : self;
}
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, self.bounds)) return;
    NSSwitch *toggle = DPSwitchIn(self);
    NSRect frame = [self convertRect:toggle.bounds fromView:toggle];
    if (toggle.enabled && NSPointInRect(point, frame)) return;  // The switch flipped itself, then passed the click on.
    if (toggle.enabled && NSPointInRect(point, NSInsetRect(frame, -10, -10))) [toggle performClick:nil];
    else self.open();
}
- (BOOL)accessibilityPerformPress {
    self.open();
    return YES;
}
@end

NSView *DPLinkRow(NSView *row, NSString *title, void (^open)(void)) {
    DPLinkRowView *link = [DPLinkRowView new];
    link.open = open;
    link.accessibilityElement = YES;
    link.accessibilityRole = NSAccessibilityButtonRole;
    link.accessibilityLabel = title;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [link addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:link.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:link.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:link.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:link.bottomAnchor],
    ]];
    return link;
}

NSImageView *DPSymbol(NSString *symbol, CGFloat size, NSColor *color) {
    NSImageView *view = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    view.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightSemibold];
    view.contentTintColor = color;
    return view;
}

void DPFillStack(NSStackView *stack, NSArray<NSView *> *views) {
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    for (NSView *view in views) {
        [stack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        // Room after each group, so a section's title sits with the rows under it.
        if ([view isMemberOfClass:DPFillView.class]) [stack setCustomSpacing:20 afterView:view];
    }
}

NSStackView *DPColumn(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    return stack;
}

NSTextField *DPHeader(NSString *text) { return DPLabel(text, 12, NSFontWeightSemibold, NSColor.secondaryLabelColor); }

NSTextField *DPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.lineBreakStrategy = NSLineBreakStrategyStandard;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

NSView *DPIconTile(NSString *symbol, NSColor *color) { return DPIconTileOfSize(symbol, color, 20); }

NSView *DPIconTileOfSize(NSString *symbol, NSColor *color, CGFloat size) {
    NSView *tile = [NSView new];
    tile.wantsLayer = YES;
    tile.layer.backgroundColor = color.CGColor;
    tile.layer.cornerRadius = size / 4;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    NSImageView *glyph = DPSymbol(symbol, size * 0.6, NSColor.whiteColor);
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:glyph];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:size],
        [tile.heightAnchor constraintEqualToConstant:size],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

// An NSBox resolves its fill once, so it kept the dark one in light mode.
@implementation DPFillView
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    return self;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.05].CGColor; }
@end

@implementation DPFlippedView
- (BOOL)isFlipped { return YES; }
@end
