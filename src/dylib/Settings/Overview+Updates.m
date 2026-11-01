#import "Settings.h"

@implementation DPOverviewView (Updates)

- (NSArray<NSView *> *)makeUpdateRows {
    self.updateSummary = DPLabel(@"", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSStackView *leading = [NSStackView stackViewWithViews:@[
        DPIconTile(@"gearshape.arrow.triangle.2.circlepath", NSColor.systemGrayColor),
        DPLabel(@"Software Update", 13, NSFontWeightRegular, NSColor.labelColor),
    ]];
    leading.spacing = 10;
    NSStackView *trailing = [NSStackView stackViewWithViews:@[self.updateSummary, DPSymbol(@"chevron.right", 11, NSColor.tertiaryLabelColor)]];
    trailing.spacing = 10;
    __weak DPOverviewView *weakSelf = self;
    NSView *updateRow = DPLinkRow(DPRow(leading, trailing), @"Software Update", ^{
        weakSelf.open(@"Software Update", [DPSoftwareUpdateView new]);
    });
    NSView *restoreRow = DPRow(DPLabel(@"Restore the original Dia without patches.", 13, NSFontWeightRegular, NSColor.labelColor),
                               [NSButton buttonWithTitle:@"Restore…" target:self action:@selector(restore:)]);
    [self.searchText setObject:@"Software update check for updates download install automatic version" forKey:updateRow];
    [self.searchText setObject:@"Restore the original Dia without patches uninstall" forKey:restoreRow];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatesDidChange) name:DPUpdatesDidChangeNotification object:nil];
    return @[updateRow, restoreRow];
}

- (NSView *)makeSafeModeRow {
    NSView *row = DPRow(DPLabel(@"Patches are off because Dia quit unexpectedly twice right after opening.", 13, NSFontWeightRegular, NSColor.labelColor),
                        [NSButton buttonWithTitle:@"Turn Patches Back On" target:self action:@selector(leaveSafeMode:)]);
    [self.searchText setObject:@"Safe mode patches off crashed quit unexpectedly turn back on" forKey:row];
    return row;
}

- (void)updatesDidChange {
    DPUpdates *updates = DPUpdates.shared;
    NSUInteger available = 0, staged = 0;
    for (NSString *part in @[DPDia, DPTweaks]) {
        available += [updates available:part];
        staged += [updates staged:part];
    }
    self.updateSummary.stringValue = staged ? @"Ready to install"
        : available ? [NSString stringWithFormat:@"%lu update%@", available, available == 1 ? @"" : @"s"]
        : updates.checking ? @"Checking…"
        : updates.found ? @"Up to date" : @"";
}

- (void)refresh {
    [self updatesDidChange];
    [DPUpdates.shared check:nil];
}

- (void)leaveSafeMode:(id)sender {
    DPLeaveSafeMode();
    DPHandOffAndQuit(@[@"apply"]);
}

- (void)restore:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Restore the original Dia?";
    alert.informativeText = @"Dia will relaunch without patches, and its own updater takes over again. Run the installer to patch it again later.";
    [alert addButtonWithTitle:@"Restore and Relaunch"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[@"uninstall"]);
    }];
}
@end
