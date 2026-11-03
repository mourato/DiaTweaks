#import "Settings.h"

@implementation DPPageView {
    DPPatch *_patch;
    NSMutableArray<DPPatchSwitch *> *_switches;
    NSTextField *_note;
}

- (instancetype)initWithPatch:(DPPatch *)patch {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _switches = [NSMutableArray new];
    _note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);

    DPPreviewView *preview = [[DPPreviewView alloc] initWithKey:patch->key];
    [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:10.0 / 16].active = YES;
    NSStackView *heading = [NSStackView stackViewWithViews:@[
        DPIconTile(patch->symbol, [NSColor valueForKey:patch->tint]),
        DPColumn(@[DPLabel(patch->title, 13, NSFontWeightSemibold, NSColor.labelColor),
                   DPLabel(patch->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), _note], 2),
    ]];
    heading.spacing = 10;
    heading.alignment = NSLayoutAttributeTop;
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:preview, DPGroup(@[DPRow(heading, [self switchFor:patch])]), nil];

    NSMutableArray<NSView *> *options = [NSMutableArray new];
    DPForEachOption(patch, ^(DPPatch *option) {
        NSView *text = DPColumn(@[DPLabel(option->title, 13, NSFontWeightRegular, NSColor.labelColor),
                                  DPLabel(option->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor)], 2);
        [options addObject:DPRow(text, [self switchFor:option])];
    });
    if (patch->choices) {
        NSMenu *menu = patch->choices();
        NSPopUpButton *picker = [NSPopUpButton new];
        picker.menu = menu;
        picker.controlSize = NSControlSizeSmall;
        picker.target = self;
        picker.action = @selector(choose:);
        for (NSMenuItem *item in menu.itemArray) if ([item.representedObject isEqual:DPChoice(patch)]) [picker selectItem:item];
        [options insertObject:DPRow(DPLabel(menu.title, 13, NSFontWeightRegular, NSColor.labelColor), picker) atIndex:0];
    }
    if (options.count) [views addObjectsFromArray:@[DPHeader(@"Options"), DPGroup(options)]];

    NSURL *wiki = DPWikiURL(patch);
    NSView *wikiRow = DPLinkRow(DPRow(DPLabel(@"Read more on the wiki", 13, NSFontWeightRegular, NSColor.labelColor),
                                      DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                                @"Read more on the wiki", ^{ [NSWorkspace.sharedWorkspace openURL:wiki]; });
    NSTextField *how = DPLabel([@"diatweaks enable " stringByAppendingString:patch->key], 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    how.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    how.selectable = YES;
    NSView *howRow = DPRow(DPColumn(@[DPLabel(@"Turn on from Terminal", 13, NSFontWeightRegular, NSColor.labelColor), how], 2), [NSStackView new]);
    [views addObject:DPGroup(@[wikiRow, howRow])];

    DPFillStack(self, views);
    [self sync];
    return self;
}

- (NSView *)switchFor:(DPPatch *)patch {
    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [_switches addObject:toggle];
    return toggle.withHiddenIcon;
}

- (void)choose:(NSPopUpButton *)picker {
    DPSetChoice(_patch, picker.selectedItem.representedObject);
}

- (void)sync {
    for (DPPatchSwitch *toggle in _switches) [toggle sync];
    _note.stringValue = DPWhyDisabled(_patch) ?: @"";
    _note.hidden = !_note.stringValue.length;
}
@end
