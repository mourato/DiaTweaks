#import "EdgeToEdge.h"

static char DPPathKey;

// Rounds the page's left and right corners down to square by `left` and `right`, with a two-half mask while they animate.
static void DPMaskCorners(CALayer *layer, CGFloat left, CGFloat right) {
    if ((left == 0 || left == 1) && (right == 0 || right == 1)) {
        layer.mask = nil;
        layer.maskedCorners = (left == 1 ? 0 : DPLeftCorners) | (right == 1 ? 0 : DPRightCorners);
        return;
    }
    CALayer *mask = layer.mask.sublayers.count == 2 ? layer.mask : [CALayer layer];
    if (mask != layer.mask) {
        for (int i = 0; i < 2; i++) {
            CALayer *half = [CALayer layer];
            half.backgroundColor = NSColor.blackColor.CGColor;
            half.cornerCurve = kCACornerCurveContinuous;
            half.maskedCorners = i ? DPRightCorners : DPLeftCorners;
            [mask addSublayer:half];
        }
    }
    CGRect bounds = layer.bounds;
    CGFloat half = CGRectGetWidth(bounds) / 2;
    mask.frame = bounds;
    mask.sublayers[0].frame = CGRectMake(0, 0, half + 1, CGRectGetHeight(bounds));
    mask.sublayers[1].frame = CGRectMake(half - 1, 0, half + 1, CGRectGetHeight(bounds));
    mask.sublayers[0].cornerRadius = layer.cornerRadius * (1 - left);
    mask.sublayers[1].cornerRadius = layer.cornerRadius * (1 - right);
    layer.mask = mask;
    layer.maskedCorners = 0;
}

// Dia draws the page's shadow and border as full-width paths, which get the same corners.
static void DPReshapePaths(NSView *container, CGFloat base, CGFloat grow, CGFloat left, CGFloat right) {
    for (NSView *sub in container.subviews)
        for (CALayer *sublayer in sub.layer.sublayers) {
            CAShapeLayer *shape = [sublayer isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer
                                : [sublayer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer.mask : nil;
            if (!shape.path || CGRectGetWidth(CGPathGetBoundingBox(shape.path)) < NSWidth(container.bounds) * 0.9) continue;
            id current = (__bridge id)shape.path;
            id dia = DPDiaValue(shape, &DPPathKey, current);
            if (dia == current) dia = CFBridgingRelease(CGPathCreateCopy(shape.path));
            CGPathRef path = DPReshapeCorners((__bridge CGPathRef)dia, base * 1.6, grow * (1 - right), grow * (1 - left));
            if (!CGPathEqualToPath(path, shape.path)) shape.path = path;
            DPOverride(shape, &DPPathKey, dia, (__bridge id)shape.path);
        }
}

BOOL DPBesideSidebar(NSView *container) {
    return NSMinX(container.frame) > DPWindowPadding + 1 && !DPChatCard(container);
}

// A full screen window has square corners, so the page squares the ones it shares with the screen.
BOOL DPFullScreen(NSView *container) {
    return (container.window.styleMask & NSWindowStyleMaskFullScreen) && !DPChatCard(container);
}

// How far the page's left and right corners go square: by the sidebar, and wherever they meet a full screen's edges.
static void DPSquareness(NSView *container, CGFloat edgeToEdge, CGFloat squareCorners, CGFloat *left, CGFloat *right) {
    *right = DPFullScreen(container) ? edgeToEdge : 0;
    *left = DPBesideSidebar(container) ? squareCorners * edgeToEdge : *right;
}

void DPApplySquareCorners(NSView *container) {
    CALayer *layer = DPRoundedContent(container).layer;
    if (!layer) return;
    layer.cornerCurve = kCACornerCurveContinuous;
    CGFloat left, right;
    DPSquareness(container, DPEdgeToEdge.progress, DPSquareSidebarCorners.progress, &left, &right);
    CGFloat base = DPBaseCornerRadius(container) ?: layer.cornerRadius;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPMaskCorners(layer, left, right);
    DPReshapePaths(container, base, base > 0 ? layer.cornerRadius / base : 1, left, right);
    [CATransaction commit];
}

static NSString *DPVerifySquareCorners(DPPatch *patch) {
    for (NSView *container in DPFindViews(DPDiaContentContainer)) {
        CALayer *layer = DPRoundedContent(container).layer;
        if (!layer) return @"no rounded web content found";
        if (!DPBesideSidebar(container)) continue;
        BOOL square = patch->on && DPEdgeToEdge.on;
        if (layer.mask || !(layer.maskedCorners & DPLeftCorners) != square) return square ? @"corners by the sidebar are round" : @"corners by the sidebar are square";
    }
    return nil;
}

DP_PATCH(DPSquareSidebarCorners) {
    .key = @"squareSidebarCorners",
    .defaultOn = YES,
    .order = 20,
    .title = @"Square corners by the sidebar",
    .detail = @"Let web pages meet the sidebar with straight edges.",
    .symbol = @"square",
    .tint = @"systemIndigoColor",
    .requires = @"edgeToEdge",
    .verify = DPVerifySquareCorners,
};
