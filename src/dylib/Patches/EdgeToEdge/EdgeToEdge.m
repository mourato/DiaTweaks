#import "EdgeToEdge.h"
#import "Patches/Peek/Peek.h"

const CGFloat DPWindowPadding = 6;
NSHashTable<NSView *> *DPContainers;
static char DPRequestedFrameKey, DPRadiusKey;

NSValue *DPRequestedFrame(NSView *container) {
    return DPGet(container, &DPRequestedFrameKey);
}

// How far each edge of `frame` is from the same edge of the superview.
static NSEdgeInsets DPGaps(NSView *superview, NSRect frame) {
    NSRect bounds = superview.bounds;
    CGFloat low = NSMinY(frame) - NSMinY(bounds), high = NSMaxY(bounds) - NSMaxY(frame);
    return NSEdgeInsetsMake(superview.isFlipped ? low : high, NSMinX(frame) - NSMinX(bounds), superview.isFlipped ? high : low, NSMaxX(bounds) - NSMaxX(frame));
}

// How far the page has grown over the padding: a Peek is always edge to edge, so its card is just the page.
static CGFloat DPEdgeToEdgeProgress(NSView *view) {
    return DPInPeek(view) ? 1 : DPEdgeToEdge.progress;
}

// Grows the page over each side where Dia left the window padding, by `progress` of it.
static NSRect DPEdgeToEdgeFrame(NSView *view, NSRect frame) {
    CGFloat inset = DPEdgeToEdgeProgress(view) * DPWindowPadding;
    NSView *superview = view.superview;
    if (inset == 0 || !superview || DPChatCard(view)) return frame;
    NSEdgeInsets gaps = DPGaps(superview, frame);
    BOOL (^isPadding)(CGFloat) = ^BOOL(CGFloat gap) { return fabs(gap - DPWindowPadding) < 0.5; };
    if (isPadding(gaps.left)) frame.origin.x -= inset, frame.size.width += inset;
    if (isPadding(gaps.right)) frame.size.width += inset;
    if (isPadding(gaps.top)) {
        frame.size.height += inset;
        if (superview.isFlipped) frame.origin.y -= inset;
    }
    if (isPadding(gaps.bottom)) {
        frame.size.height += inset;
        if (!superview.isFlipped) frame.origin.y -= inset;
    }
    return frame;
}

CGFloat DPBaseCornerRadius(NSView *container) {
    CGFloat *radius = DPIvar(container, "cornerRadius");
    return radius ? [DPDiaValue(container, &DPRadiusKey, @(*radius)) doubleValue] : 0;
}

// The corners grow with the page so they stay concentric with the window's.
static void DPSetCornerRadius(NSView *container, CGFloat inset) {
    CGFloat *radius = DPIvar(container, "cornerRadius");
    if (!radius) return;
    CGFloat base = DPBaseCornerRadius(container);
    DPOverride(container, &DPRadiusKey, @(base), @(base + inset));
    if (*radius == base + inset) return;
    *radius = base + inset;
    container.needsLayout = YES;
}

static void DPContainer_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    DPSet(self, &DPRequestedFrameKey, @(frame));
    [DPContainers addObject:self];
    NSRect adjusted = DPEdgeToEdgeFrame(self, frame);
    DPSetCornerRadius(self, NSEqualRects(adjusted, frame) ? 0 : DPEdgeToEdgeProgress(self) * DPWindowPadding);
    DPCallOriginal(DPContainer_setFrame, self, adjusted);
}

static void DPRelayoutContainers(void) {
    for (NSView *container in DPContainers) {
        NSValue *requested = DPRequestedFrame(container);
        if (requested) container.frame = requested.rectValue;
        container.needsLayout = container.needsDisplay = YES;
        DPRestyleContainer(container);
    }
}

static NSString *DPVerifyEdgeToEdge(DPPatch *patch) {
    NSArray<NSView *> *containers = DPFindViews(DPDiaContentContainer);
    if (!containers.count) return @"no web content found";
    for (NSView *container in containers) {
        NSValue *requested = DPRequestedFrame(container);
        if (!requested) return @"never saw Dia place the web content";
        if (!(patch->on || DPInPeek(container)) || DPChatCard(container)) {
            if (!NSEqualRects(container.frame, requested.rectValue)) return @"web content isn't where Dia put it";
            continue;
        }
        NSEdgeInsets gaps = DPGaps(container.superview, container.frame);
        if (fabs(gaps.right) > 0.5 || fabs(gaps.bottom) > 0.5) return @"web content doesn't reach the window's edge";
        if (fabs(gaps.top - DPWindowPadding) < 0.5 || fabs(gaps.left - DPWindowPadding) < 0.5) return @"padding left around web content";
    }
    return nil;
}

static void DPInstallEdgeToEdge(void) {
    DPContainers = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaContentContainer, @selector(setFrame:), (IMP)DPContainer_setFrame);
    DPInstallRestyle();
}

DP_PATCH(DPEdgeToEdge) {
    .key = @"edgeToEdge",
    .defaultOn = YES,
    .order = 10,
    .title = @"Edge-to-edge web content",
    .detail = @"Remove the padding between web pages and the window edge.",
    .symbol = @"squareshape.squareshape.dotted",
    .tint = @"systemBlueColor",
    .classes = DPClasses(DPDiaContentContainer, DPDiaShadowView),
    .install = DPInstallEdgeToEdge,
    .relayout = DPRelayoutContainers,
    .verify = DPVerifyEdgeToEdge,
};
