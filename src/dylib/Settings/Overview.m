#import "Settings.h"

@interface DPOverviewView ()
@property (nonatomic, strong) NSMapTable<DPPatchSwitch *, NSTextField *> *notes;
@property (nonatomic, strong) NSMutableArray<NSArray *> *sections;  // header, group, rows
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *sectionHiders;  // "" when its tweaks don't share one
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSImageView *> *sectionEyes;
@property (nonatomic, strong) NSTextField *noResults, *notice;
@end

@implementation DPOverviewView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.searchText = [NSMapTable strongToStrongObjectsMapTable];
    self.notes = [NSMapTable strongToStrongObjectsMapTable];
    self.sections = [NSMutableArray new];
    self.sectionHiders = [NSMutableDictionary new];
    self.sectionEyes = [NSMutableDictionary new];
    [DPPreviewView preload];

    NSMutableArray<NSString *> *titles = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<NSView *> *> *rows = [NSMutableDictionary new];
    void (^add)(NSString *, NSView *) = ^(NSString *title, NSView *row) {
        if (!rows[title]) {
            [titles addObject:title];
            rows[title] = [NSMutableArray new];
        }
        [rows[title] addObject:row];
    };
    if (DPSafeMode) add(@"Safe Mode", [self makeSafeModeRow]);
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        if (DPRequired(patch)) continue;
        NSString *section = patch->section ?: @"Other", *hider = patch->disabledBy ?: @"", *shared = self.sectionHiders[section];
        self.sectionHiders[section] = !shared || [shared isEqual:hider] ? hider : @"";
        add(section, [self rowForPatch:patch]);
    }
    for (NSView *row in [self makeUpdateRows]) add(@"Updates", row);

    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSString *title in titles) {
        NSView *header = DPHeader(title);
        if (self.sectionHiders[title].length) {
            NSImageView *eye = DPSymbol(@"eye.slash", 12, NSColor.secondaryLabelColor);
            self.sectionEyes[title] = eye;
            NSStackView *row = [NSStackView new];
            row.detachesHiddenViews = NO;
            [row addView:header inGravity:NSStackViewGravityLeading];
            [row addView:eye inGravity:NSStackViewGravityTrailing];
            header = row;
        }
        NSView *group = DPGroup(rows[title]);
        [views addObjectsFromArray:@[header, group]];
        [self.sections addObject:@[header, group, rows[title]]];
    }
    self.noResults = DPLabel(@"No Results", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    self.notice = DPLabel(@"DiaPatches is unofficial and not affiliated with The Browser Company.", 11, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    DPFillStack(self, [views arrayByAddingObjectsFromArray:@[self.noResults, self.notice]]);
    [self syncWithQuery:@""];
    return self;
}

- (NSView *)rowForPatch:(DPPatch *)patch {
    NSTextField *note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    note.hidden = YES;
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPIconTile(patch->symbol, [NSColor valueForKey:patch->tint]),
        DPColumn(@[DPLabel(patch->title, 13, NSFontWeightRegular, NSColor.labelColor), note], 2),
    ]];
    leading.spacing = 10;

    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [self.notes setObject:note forKey:toggle];
    NSMutableString *search = [NSMutableString stringWithFormat:@"%@ %@", patch->title, patch->detail];
    DPForEachOption(patch, ^(DPPatch *option) { [search appendFormat:@" %@ %@", option->title, option->detail]; });
    NSStackView *trailing = [NSStackView stackViewWithViews:@[toggle.withHiddenIcon, DPSymbol(@"chevron.right", 11, NSColor.tertiaryLabelColor)]];
    trailing.spacing = 10;

    __weak DPOverviewView *weakSelf = self;
    NSView *row = DPLinkRow(DPRow(leading, trailing), patch->title, ^{ weakSelf.open(patch->title, [[DPPageView alloc] initWithPatch:patch]); });
    [self.searchText setObject:search forKey:row];
    return row;
}

- (void)syncWithQuery:(NSString *)query {
    [self.sectionEyes enumerateKeysAndObjectsUsingBlock:^(NSString *section, NSImageView *eye, BOOL *stop) {
        eye.toolTip = DPWhyHiddenBy(DPPatchNamed(self.sectionHiders[section]));
        eye.hidden = !eye.toolTip;
    }];
    for (DPPatchSwitch *toggle in self.notes) {
        [toggle sync];
        if (self.sectionEyes[toggle.patch->section ?: @"Other"]) toggle.hiddenIcon.hidden = YES;
        NSMutableArray<NSString *> *options = [NSMutableArray new];
        if (toggle.patch->on) DPForEachOption(toggle.patch, ^(DPPatch *option) { if (option->on) [options addObject:option->title]; });
        NSTextField *note = [self.notes objectForKey:toggle];
        note.stringValue = DPWhyDisabled(toggle.patch) ?: [options componentsJoinedByString:@" · "];
        note.hidden = !note.stringValue.length;
    }

    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL anything = NO;
    for (NSArray *section in self.sections) {
        BOOL any = NO;
        for (NSView *row in section[2]) {
            BOOL visible = YES;
            for (NSString *word in words) visible &= !word.length || [[self.searchText objectForKey:row] localizedStandardContainsString:word];
            NSArray<NSView *> *arranged = ((NSStackView *)row.superview).arrangedSubviews;
            NSUInteger index = [arranged indexOfObject:row];
            row.hidden = !visible;
            if (index > 0) arranged[index - 1].hidden = !visible || !any;
            any |= visible;
        }
        for (NSView *view in @[section[0], section[1]]) view.hidden = !any;
        anything |= any;
    }
    self.noResults.hidden = anything;
    self.notice.hidden = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length > 0;
}
@end
