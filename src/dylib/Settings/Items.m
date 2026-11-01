#import "Settings.h"

DPItem DPPatchItem(DPPatch *patch) {
    return (DPItem){patch, patch->key, patch->title, patch->detail, patch->symbol, patch->tint, nil};
}

void DPForEachOption(DPPatch *patch, void (^body)(DPPatch *option)) {
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPRequired(DPPatches[i]) == patch) body(DPPatches[i]);
}

NSString *DPWhyDisabled(DPPatch *patch) {
    if (patch->unavailable) return @"Unavailable on this Dia version.";
    DPPatch *required = DPRequired(patch);
    return required && !required->on ? [NSString stringWithFormat:@"Needs %@.", required->title] : nil;
}

NSString *DPWhyHidden(DPPatch *patch) {
    DPPatch *disabler = DPPatchNamed(patch->disabledBy);
    return patch->on && disabler && disabler->on ? [NSString stringWithFormat:@"Hidden while %@ is on", disabler->title] : nil;
}

NSURL *DPWikiURL(DPItem item) {
    NSString *page = [item.title stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    return [NSURL URLWithString:[@"https://github.com/JaceThings/DiaTweaks/wiki/" stringByAppendingString:page]];
}

@implementation DPPatchSwitch

- (instancetype)initWithPatch:(DPPatch *)patch {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _hiddenIcon = DPSymbol(@"eye.slash", 12, NSColor.secondaryLabelColor);
    self.controlSize = NSControlSizeSmall;
    self.accessibilityLabel = patch->title;
    self.target = self;
    self.action = @selector(flip);
    [self sync];
    return self;
}

- (void)flip {
    DPSetPatch(self.patch, self.state == NSControlStateValueOn, YES);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

- (NSView *)withHiddenIcon {
    NSStackView *stack = [NSStackView stackViewWithViews:@[self.hiddenIcon, self]];
    stack.spacing = 8;
    return stack;
}

- (void)sync {
    self.state = self.patch->on;
    self.enabled = !DPWhyDisabled(self.patch);
    self.hiddenIcon.toolTip = DPWhyHidden(self.patch);
    self.hiddenIcon.hidden = !self.hiddenIcon.toolTip;
}
@end
