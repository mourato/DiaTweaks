#import "Settings.h"

// App icons carry their own margin, so Dia's is drawn larger than the tile to look the same size.
static NSView *DPPartIcon(NSString *part) {
    if ([part isEqual:DPTweaks]) return DPIconTileOfSize(@"wand.and.stars", NSColor.systemPurpleColor, 30);
    NSImageView *icon = [NSImageView imageViewWithImage:[NSWorkspace.sharedWorkspace iconForFile:NSBundle.mainBundle.bundlePath]];
    [icon.widthAnchor constraintEqualToConstant:36].active = YES;
    [icon.heightAnchor constraintEqualToConstant:36].active = YES;
    return icon;
}

static NSTextField *DPLine(NSString *text, CGFloat size, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

static NSButton *DPButton(NSString *title, id target, SEL action, NSString *part) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.identifier = part;
    return button;
}

@implementation DPSoftwareUpdateView {
    NSString *_shape;
    NSMapTable<NSString *, NSProgressIndicator *> *_bars;
    NSMapTable<NSString *, NSTextField *> *_details;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _bars = [NSMapTable strongToStrongObjectsMapTable];
    _details = [NSMapTable strongToStrongObjectsMapTable];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:DPUpdatesDidChangeNotification object:nil];
    DPUpdates *updates = DPUpdates.shared;
    if (!updates.checking && ![updates downloading:DPDia] && ![updates downloading:DPTweaks]) [updates check:nil];
    [self sync];
    return self;
}

- (NSArray<NSString *> *)shown {
    DPUpdates *updates = DPUpdates.shared;
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *part in @[DPDia, DPTweaks])
        if ([updates available:part] || [updates staged:part] || [updates downloading:part]) [parts addObject:part];
    return parts;
}

- (NSString *)stateOf:(NSString *)part {
    DPUpdates *updates = DPUpdates.shared;
    return [updates downloading:part] ? @"downloading" : [updates staged:part] ? @"staged" : @"available";
}

// Rebuilds only when something other than download progress changed, so buttons don't move under the pointer.
- (void)sync {
    DPUpdates *updates = DPUpdates.shared;
    NSMutableString *shape = [NSMutableString stringWithFormat:@"%d %d", updates.checking, updates.found != nil];
    for (NSString *part in self.shown)
        [shape appendFormat:@" %@:%@:%@:%d", part, [self stateOf:part], updates.found[part][@"latest"], [updates failed:part]];
    for (NSString *part in @[DPDia, DPTweaks]) [shape appendFormat:@"%ld", DPAutoLevelOf(part)];
    if (![shape isEqual:_shape]) {
        _shape = shape;
        [self rebuild];
    }
    for (NSString *part in _bars) {
        double progress = [updates progress:part];
        NSProgressIndicator *bar = [_bars objectForKey:part];
        bar.indeterminate = progress < 0;
        if (progress < 0) [bar startAnimation:nil];
        else bar.doubleValue = progress;
        [_details objectForKey:part].stringValue = progress < 0 ? @"Preparing…"
            : [NSString stringWithFormat:@"Downloading… %.0f%%", progress * 100];
    }
}

- (void)rebuild {
    for (NSView *view in self.arrangedSubviews) [view removeFromSuperview];
    [_bars removeAllObjects];
    [_details removeAllObjects];
    DPUpdates *updates = DPUpdates.shared;
    NSMutableArray<NSView *> *views = [NSMutableArray new];
    NSArray<NSString *> *shown = self.shown;

    if (updates.checking && !shown.count) {
        NSProgressIndicator *spinner = [NSProgressIndicator new];
        spinner.style = NSProgressIndicatorStyleSpinning;
        spinner.controlSize = NSControlSizeSmall;
        [spinner startAnimation:nil];
        [views addObject:DPGroup(@[DPRow(DPLine(@"Checking for updates…", 13, NSColor.labelColor), spinner)])];
    } else if (!updates.found) {
        [views addObject:DPGroup(@[DPRow(DPLine(@"Couldn’t check for updates", 13, NSColor.labelColor),
                                         [NSButton buttonWithTitle:@"Try Again" target:self action:@selector(checkAgain:)])])];
    } else if (!shown.count) {
        [views addObject:DPGroup(@[DPRow(DPLine(@"Everything is up to date", 13, NSColor.labelColor),
                                         [NSButton buttonWithTitle:@"Check Now" target:self action:@selector(checkAgain:)])])];
    }

    if (shown.count > 1) {
        NSButton *both = [NSButton buttonWithTitle:@"Update Both" target:self action:@selector(updateAll:)];
        both.enabled = ![updates downloading:DPDia] && ![updates downloading:DPTweaks];
        [views addObject:DPGroup(@[DPRow(DPLine(@"Dia and DiaTweaks both have updates", 13, NSColor.labelColor), both)])];
    }
    for (NSString *part in shown) {
        if (part != shown.firstObject) [views addObject:DPHeader(@"Also Available")];
        [views addObject:[self groupFor:part]];
    }

    if (updates.found) {
        NSMutableArray<NSView *> *installed = [NSMutableArray new];
        for (NSString *part in @[DPDia, DPTweaks]) {
            id version = updates.found[part][@"installed"];
            NSString *text = [version isKindOfClass:NSString.class] ? version : [part isEqual:DPDia] ? @"—" : @"Development build";
            [installed addObject:DPRow(DPLine(DPPartName(part), 13, NSColor.labelColor), DPLine(text, 13, NSColor.secondaryLabelColor))];
        }
        [views addObjectsFromArray:@[DPHeader(@"Installed"), DPGroup(installed)]];
    }

    NSMutableArray<NSView *> *automatic = [NSMutableArray new];
    for (NSString *part in @[DPDia, DPTweaks]) {
        NSPopUpButton *menu = [NSPopUpButton new];
        [menu addItemsWithTitles:@[@"Off", @"Show in Software Update", @"Download", @"Download and install on quit"]];
        [menu selectItemAtIndex:DPAutoLevelOf(part)];
        menu.identifier = part;
        menu.target = self;
        menu.action = @selector(automaticChanged:);
        menu.accessibilityLabel = [DPPartName(part) stringByAppendingString:@" updates"];
        NSString *does = @[@"Only checks when you open this page", @"Checks when Dia opens and lists it here",
                           @"Downloads it, then you choose when to install", @"Downloads it and installs when you quit Dia"][DPAutoLevelOf(part)];
        NSView *text = DPColumn(@[DPLine(DPPartName(part), 13, NSColor.labelColor), DPLine(does, 11, NSColor.secondaryLabelColor)], 2);
        [automatic addObject:DPRow(text, menu)];
    }
    [views addObjectsFromArray:@[DPHeader(@"Automatic Updates"), DPGroup(automatic)]];

    DPFillStack(self, views);
    [self setCustomSpacing:14 afterView:views.firstObject];
}

- (NSView *)groupFor:(NSString *)part {
    DPUpdates *updates = DPUpdates.shared;
    NSDictionary *found = updates.found[part];
    NSString *state = [self stateOf:part];
    BOOL installsOnQuit = DPAutoLevelOf(part) == DPAutoInstall;
    NSString *size = [NSByteCountFormatter stringFromByteCount:[found[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    NSTextField *detail = DPLine([state isEqual:@"staged"] ? (installsOnQuit ? @"Installs when you quit" : @"Ready to install")
                                 : [updates failed:part] ? @"Download failed" : size,
                                 11, [updates failed:part] ? NSColor.systemRedColor : NSColor.secondaryLabelColor);
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPPartIcon(part),
        DPColumn(@[DPLine([NSString stringWithFormat:@"%@ %@", DPPartName(part), found[@"latest"]], 13, NSColor.labelColor), detail], 2),
    ]];
    leading.spacing = 10;

    NSView *trailing;
    if ([state isEqual:@"downloading"]) {
        NSProgressIndicator *bar = [NSProgressIndicator new];
        bar.style = NSProgressIndicatorStyleBar;
        bar.indeterminate = NO;
        bar.maxValue = 1;
        [bar.widthAnchor constraintEqualToConstant:140].active = YES;
        [_bars setObject:bar forKey:part];
        [_details setObject:detail forKey:part];
        trailing = bar;
    } else if ([state isEqual:@"staged"]) {
        trailing = DPButton(@"Relaunch", self, @selector(relaunch:), part);
    } else {
        trailing = [NSStackView stackViewWithViews:@[DPButton([updates failed:part] ? @"Try Again" : @"Download", self, @selector(download:), part),
                                                     DPButton(@"Update Now", self, @selector(updateNow:), part)]];
    }
    NSMutableArray *rows = [NSMutableArray arrayWithObject:DPRow(leading, trailing)];
    NSURL *notes = [found[@"releaseNotes"] isKindOfClass:NSString.class] ? [NSURL URLWithString:found[@"releaseNotes"]] : nil;
    if (notes)
        [rows addObject:DPLinkRow(DPRow(DPLine(@"Release Notes", 13, NSColor.labelColor), DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                                  @"Release Notes", ^{ [NSWorkspace.sharedWorkspace openURL:notes]; })];
    return DPGroup(rows);
}

- (void)checkAgain:(id)sender { [DPUpdates.shared check:nil]; }
- (void)download:(NSButton *)sender { [DPUpdates.shared download:sender.identifier then:nil]; }
- (void)relaunch:(NSButton *)sender { [DPUpdates.shared installAndRelaunch:@[sender.identifier]]; }

- (void)updateNow:(NSButton *)sender {
    NSString *part = sender.identifier;
    [DPUpdates.shared download:part then:^{
        if ([DPUpdates.shared staged:part]) [DPUpdates.shared installAndRelaunch:@[part]];
    }];
}

- (void)updateAll:(id)sender {
    DPUpdates *updates = DPUpdates.shared;
    NSArray<NSString *> *parts = self.shown;
    __block NSUInteger left = parts.count;
    void (^ready)(void) = ^{ if (--left == 0) [updates installAndRelaunch:parts]; };
    for (NSString *part in parts) {
        if ([updates staged:part]) ready();
        else [updates download:part then:ready];
    }
}

- (void)automaticChanged:(NSPopUpButton *)sender {
    DPSetAutoLevel(sender.identifier, sender.indexOfSelectedItem);
    [self sync];
}
@end
