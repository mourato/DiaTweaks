#import "Settings.h"

@implementation DPPageView {
    DPPatch *_patch;
    NSMutableArray<DPPatchSwitch *> *_switches;
    NSTextField *_note;
}

- (instancetype)initWithItem:(DPItem)item {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = item.patch;
    _switches = [NSMutableArray new];
    _note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);

    DPPreviewView *preview = [[DPPreviewView alloc] initWithKey:item.key];
    [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:10.0 / 16].active = YES;
    NSStackView *heading = [NSStackView stackViewWithViews:@[
        DPIconTile(item.symbol, [NSColor valueForKey:item.tint]),
        DPColumn(@[DPLabel(item.title, 13, NSFontWeightSemibold, NSColor.labelColor),
                   DPLabel(item.detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), _note], 2),
    ]];
    heading.spacing = 10;
    heading.alignment = NSLayoutAttributeTop;
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:preview, DPGroup(@[DPRow(heading, [self switchFor:item.patch])]), nil];

    NSMutableArray<NSView *> *options = [NSMutableArray new];
    if (item.patch) DPForEachOption(item.patch, ^(DPPatch *option) {
        NSView *text = DPColumn(@[DPLabel(option->title, 13, NSFontWeightRegular, NSColor.labelColor),
                                  DPLabel(option->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor)], 2);
        [options addObject:DPRow(text, [self switchFor:option])];
    });
    if (options.count) [views addObjectsFromArray:@[DPHeader(@"Options"), DPGroup(options)]];

    NSURL *wiki = DPWikiURL(item);
    NSView *wikiRow = DPLinkRow(DPRow(DPLabel(@"Read more on the wiki", 13, NSFontWeightRegular, NSColor.labelColor),
                                      DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                                @"Read more on the wiki", ^{ [NSWorkspace.sharedWorkspace openURL:wiki]; });
    NSTextField *how = DPLabel(item.where ?: [@"diatweaks enable " stringByAppendingString:item.key], 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    if (!item.where) how.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    how.selectable = YES;
    NSView *howRow = DPRow(DPColumn(@[DPLabel(item.where ? @"Use it" : @"Turn on from Terminal", 13, NSFontWeightRegular, NSColor.labelColor), how], 2), [NSStackView new]);
    [views addObject:DPGroup(@[wikiRow, howRow])];

    DPFillStack(self, views);
    [self sync];
    return self;
}

- (NSView *)switchFor:(DPPatch *)patch {
    if (!patch) return [NSStackView new];
    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [_switches addObject:toggle];
    return toggle.withHiddenIcon;
}

- (void)sync {
    for (DPPatchSwitch *toggle in _switches) [toggle sync];
    _note.stringValue = (_patch ? DPWhyDisabled(_patch) : nil) ?: @"";
    _note.hidden = !_note.stringValue.length;
}
@end
