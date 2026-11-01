// Dia restyles the page's layers after its own layout and when Chat opens, so the patches restyle after it.
#import "EdgeToEdge.h"

static char DPChatKey;

void DPRestyleContainer(NSView *container) {
    DPApplySquareCorners(container);
    CALayer *card = DPChatCard(container).layer;
    if (!card) return;
    if (card.cornerCurve != kCACornerCurveContinuous) card.cornerCurve = kCACornerCurveContinuous;
    NSValue *requested = DPRequestedFrame(container);
    if (requested && !NSEqualRects(container.frame, requested.rectValue)) container.frame = requested.rectValue;
}

static void DPContainer_layoutOrUpdateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContainer_layoutOrUpdateLayer, self);
    DPRestyleContainer(self);
    dispatch_async(dispatch_get_main_queue(), ^{ DPRestyleContainer(self); });
}

// Opening or closing Chat reshapes the content without resizing the container.
static void DPShadow_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPShadow_layout, self);
    NSView *container = self;
    while (container && !DPIsKind(container, DPDiaContentContainer)) container = container.superview;
    if (!container) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL chat = DPChatCard(container) != nil;
        if ([DPGet(container, &DPChatKey) boolValue] != chat) {
            DPSet(container, &DPChatKey, @(chat));
            NSValue *requested = DPRequestedFrame(container);
            if (requested) container.frame = requested.rectValue;
        }
        DPRestyleContainer(container);
    });
}

void DPInstallRestyle(void) {
    DPHook(DPDiaContentContainer, @selector(layout), (IMP)DPContainer_layoutOrUpdateLayer);
    DPHook(DPDiaContentContainer, @selector(updateLayer), (IMP)DPContainer_layoutOrUpdateLayer);
    DPHook(DPDiaShadowView, @selector(layout), (IMP)DPShadow_layout);
    // Full screen squares the page's corners, but a window already the screen's size doesn't lay out on the way in or out.
    // AppKit flips the style mask just after each will notification, so restyle then, and again once it's done.
    NSArray<NSNotificationName> *names = @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                                           NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification];
    for (NSNotificationName name in names)
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *_) {
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSView *container in DPContainers.allObjects) DPRestyleContainer(container);
            });
        }];
}
