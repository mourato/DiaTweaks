#import "Settings.h"

void DPForEachOption(DPPatch *patch, void (^body)(DPPatch *option)) {
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPRequired(DPPatches[i]) == patch) body(DPPatches[i]);
}

NSString *DPWhyDisabled(DPPatch *patch) {
    if (patch->unavailable) return @"Unavailable on this Dia version.";
    DPPatch *required = DPRequired(patch);
    return required && !required->on ? [NSString stringWithFormat:@"Needs %@.", required->title] : nil;
}

// An option on, like showing the hidden toolbar on hover, means it doesn't hide for good.
NSString *DPWhyHiddenBy(DPPatch *disabler) {
    if (!disabler || !disabler->on) return nil;
    __block BOOL shownSometimes = NO;
    DPForEachOption(disabler, ^(DPPatch *option) { shownSometimes |= option->on; });
    return shownSometimes ? nil : [NSString stringWithFormat:@"Hidden while %@ is on", disabler->title];
}

NSString *DPWhyHidden(DPPatch *patch) { return patch->on ? DPWhyHiddenBy(DPPatchNamed(patch->disabledBy)) : nil; }

NSURL *DPWikiURL(DPPatch *patch) {
    NSString *page = [patch->title stringByReplacingOccurrencesOfString:@" " withString:@"-"];
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
    NSStackView *stack = [NSStackView new];
    stack.spacing = 8;
    stack.detachesHiddenViews = NO;  // Before adding the icon, which a stack drops if it's already hidden.
    [stack addArrangedSubview:self.hiddenIcon];
    [stack addArrangedSubview:self];
    return stack;
}

- (void)sync {
    self.state = self.patch->on;
    self.enabled = !DPWhyDisabled(self.patch);
    self.hiddenIcon.toolTip = DPWhyHidden(self.patch);
    self.hiddenIcon.hidden = !self.hiddenIcon.toolTip;
}
@end
