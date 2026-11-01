#import "Settings.h"

static const DPItem DPGroupTabsItem = {
    NULL, @"groupTabsByDomain", @"Group Tabs by Domain", @"Group a window’s tabs by site.", @"rectangle.3.group", @"systemGreenColor",
    @"Right-click a tab, or choose Tabs → Group Tabs by Domain.",
};

@interface DPOverviewView ()
@property (nonatomic, strong) NSMapTable<DPPatchSwitch *, NSTextField *> *notes;
@property (nonatomic, strong) NSMutableArray<NSArray *> *sections;  // header, group, rows
@property (nonatomic, strong) NSTextField *noResults, *notice;
@end

@implementation DPOverviewView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.searchText = [NSMapTable strongToStrongObjectsMapTable];
    self.notes = [NSMapTable strongToStrongObjectsMapTable];
    self.sections = [NSMutableArray new];

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
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (!DPRequired(DPPatches[i])) add(DPPatches[i]->section ?: @"Other", [self rowForItem:DPPatchItem(DPPatches[i])]);
    add(@"Commands", [self rowForItem:DPGroupTabsItem]);
    for (NSView *row in [self makeUpdateRows]) add(@"Updates", row);

    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSString *title in titles) {
        NSTextField *header = DPHeader(title);
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

- (NSView *)rowForItem:(DPItem)item {
    NSTextField *note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    note.hidden = YES;
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPIconTile(item.symbol, [NSColor valueForKey:item.tint]),
        DPColumn(@[DPLabel(item.title, 13, NSFontWeightRegular, NSColor.labelColor), note], 2),
    ]];
    leading.spacing = 10;

    NSView *control = DPLabel(@"Tabs menu", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSMutableString *search = [NSMutableString stringWithFormat:@"%@ %@", item.title, item.detail];
    if (item.patch) {
        DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:item.patch];
        [self.notes setObject:note forKey:toggle];
        control = toggle.withHiddenIcon;
        DPForEachOption(item.patch, ^(DPPatch *option) { [search appendFormat:@" %@ %@", option->title, option->detail]; });
    }
    NSStackView *trailing = [NSStackView stackViewWithViews:@[control, DPSymbol(@"chevron.right", 11, NSColor.tertiaryLabelColor)]];
    trailing.spacing = 10;

    __weak DPOverviewView *weakSelf = self;
    NSView *row = DPLinkRow(DPRow(leading, trailing), item.title, ^{ weakSelf.open(item.title, [[DPPageView alloc] initWithItem:item]); });
    [self.searchText setObject:search forKey:row];
    return row;
}

- (void)syncWithQuery:(NSString *)query {
    for (DPPatchSwitch *toggle in self.notes) {
        [toggle sync];
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
