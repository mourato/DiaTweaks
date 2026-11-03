#import "EdgeToEdge.h"

static char DPPathKey, DPShadowPathKey, DPPastPathsKey;
static NSMapTable<CALayer *, NSView *> *DPPathOwners;  // masks have no superlayer to find their page by

// Private, in on-screen order from the top left. Dia crossfades a masked page as it resizes, so radii beat a mask.
typedef struct CACornerRadii { CGSize topLeft, topRight, bottomRight, bottomLeft; } CACornerRadii;

@interface CALayer (DPCornerRadii)
@property CACornerRadii cornerRadii;
@property(readonly) BOOL _usesCornerRadii;
@end

// Rounds the page's left and right corners down to square by `left` and `right`, with a two-half mask while they animate.
static void DPMaskCorners(NSView *container, CALayer *layer, CGFloat left, CGFloat right) {
    if ([layer respondsToSelector:@selector(setCornerRadii:)]) {
        layer.mask = nil;
        layer.maskedCorners = DPLeftCorners | DPRightCorners;
        CGFloat l = layer.cornerRadius * (1 - left), r = layer.cornerRadius * (1 - right);
        CACornerRadii radii = { { l, l }, { r, r }, { r, r }, { l, l } };
        DPAnimateLayer(container, layer, @"cornerRadii", [NSValue valueWithBytes:&radii objCType:@encode(CACornerRadii)]);
        return;
    }
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

static CGPathRef DPReshapePath(id owner, char *key, CGPathRef current, NSView *container, CGFloat base, CGFloat grow, CGFloat left, CGFloat right) {
    if (!current || CGRectGetWidth(CGPathGetBoundingBox(current)) < NSWidth(container.bounds) * 0.9) return NULL;
    id dia = DPDiaValue(owner, key, (__bridge id)current);
    if (dia == (__bridge id)current) dia = CFBridgingRelease(CGPathCreateCopy(current));
    CGPathRef path = DPReshapeCorners((__bridge CGPathRef)dia, base * 1.6, grow * (1 - right), grow * (1 - left));
    DPOverride(owner, key, dia, (__bridge id)path);
    if (!DPPathOwners) DPPathOwners = [NSMapTable weakToWeakObjectsMapTable];
    [DPPathOwners setObject:container forKey:owner];
    // Dia's next animation may start from a path we set, so each maps back to Dia's.
    NSMapTable *past = DPGet(owner, &DPPastPathsKey) ?: [NSMapTable strongToStrongObjectsMapTable];
    if (past.count > 8) [past removeAllObjects];
    [past setObject:dia forKey:(__bridge id)path];
    DPSet(owner, &DPPastPathsKey, past);
    return CGPathEqualToPath(path, current) ? NULL : path;
}

// Dia draws the page's shadow and border as full-width paths, which get the same corners.
static void DPSetPath(CALayer *layer, NSString *key, CGPathRef path) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setValue:(__bridge id)path forKey:key];
    [CATransaction commit];
}

static void DPReshapePaths(NSView *container, CGFloat base, CGFloat grow, CGFloat left, CGFloat right) {
    for (NSView *sub in container.subviews)
        for (CALayer *sublayer in sub.layer.sublayers) {
            CAShapeLayer *shape = [sublayer isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer
                                : [sublayer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)sublayer.mask : nil;
            CGPathRef path = DPReshapePath(shape, &DPPathKey, shape.path, container, base, grow, left, right);
            if (path) DPSetPath(shape, @"path", path);
            CGPathRef shadow = DPReshapePath(sublayer, &DPShadowPathKey, sublayer.shadowPath, container, base, grow, left, right);
            if (shadow) DPSetPath(sublayer, @"shadowPath", shadow);
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

// `base` is Dia's radius, `grow` how much rounder the page is, `left` and `right` how far each side has gone square.
static CALayer *DPCornerShape(NSView *container, CGFloat *base, CGFloat *grow, CGFloat *left, CGFloat *right) {
    CALayer *layer = DPRoundedContent(container).layer;
    if (!layer) return nil;
    DPSquareness(container, DPEdgeToEdge.progress, DPSquareSidebarCorners.progress, left, right);
    // Rounder window corners don't reach the corners by the sidebar.
    CGFloat growth = DPWindowCornerGrowth(container.window);
    if (growth > 0 && layer.cornerRadius > 0 && DPBesideSidebar(container)) *left = 1 - (1 - *left) * (layer.cornerRadius - growth) / layer.cornerRadius;
    *base = DPBaseCornerRadius(container) ?: layer.cornerRadius;
    *grow = *base > 0 ? layer.cornerRadius / *base : 1;
    return layer;
}

void DPRoundCornerControls(NSView *container) {
    NSView *content = DPRoundedContent(container);
    NSView *bar = DPFindView(content, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaNavigationBar); });
    if (!bar || ![content.layer respondsToSelector:@selector(cornerRadii)]) return;
    CACornerRadii page = content.layer.cornerRadii;
    CGFloat width = NSWidth(content.bounds);
    DPFindView(bar, ^BOOL(NSView *view) {
        CALayer *layer = view.layer;
        CGFloat dia = layer.cornerRadius;
        if (view == bar || dia <= 0 || view.isHiddenOrHasHiddenAncestor) return NO;
        NSRect rect = [view convertRect:view.bounds toView:content];
        CGFloat top = content.isFlipped ? NSMinY(rect) : NSHeight(content.bounds) - NSMaxY(rect), left = NSMinX(rect), right = width - NSMaxX(rect);
        CGFloat topLeft = top < 12 && left < 12 ? MAX(dia, page.topLeft.width - MAX(top, left)) : dia;
        CGFloat topRight = top < 12 && right < 12 ? MAX(dia, page.topRight.width - MAX(top, right)) : dia;
        if (topLeft == dia && topRight == dia && !layer._usesCornerRadii) return NO;
        CGSize l = CGSizeMake(topLeft, topLeft), r = CGSizeMake(topRight, topRight), d = CGSizeMake(dia, dia);
        CACornerRadii radii = layer.contentsAreFlipped ? (CACornerRadii){ d, d, r, l } : (CACornerRadii){ l, r, d, d };
        DPAnimateLayer(container, layer, @"cornerRadii", [NSValue valueWithBytes:&radii objCType:@encode(CACornerRadii)]);
        return NO;
    });
}

void DPApplySquareCorners(NSView *container) {
    CGFloat base, grow, left, right;
    CALayer *layer = DPCornerShape(container, &base, &grow, &left, &right);
    if (!layer) return;
    layer.cornerCurve = kCACornerCurveContinuous;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPMaskCorners(container, layer, left, right);
    DPReshapePaths(container, base, grow, left, right);
    [CATransaction commit];
    DPRoundCornerControls(container);
}

// Reshaped as Dia sets them, or its corners show for a frame before layout.
CGPathRef DPReshapeSetPath(CALayer *layer, BOOL shadow, CGPathRef path) {
    NSView *container = [DPPathOwners objectForKey:layer];
    if (!container || !path || [DPGet(layer, &DPPastPathsKey) objectForKey:(__bridge id)path]) return path;
    CGFloat base, grow, left, right;
    if (!DPCornerShape(container, &base, &grow, &left, &right)) return path;
    return DPReshapePath(layer, shadow ? &DPShadowPathKey : &DPPathKey, path, container, base, grow, left, right) ?: path;
}

CAAnimation *DPReshapeDiaAnimation(CALayer *layer, CAAnimation *animation) {
    CABasicAnimation *move = (CABasicAnimation *)animation;
    if (![move isKindOfClass:CABasicAnimation.class] || !([move.keyPath isEqual:@"path"] || [move.keyPath isEqual:@"shadowPath"])) return animation;
    NSView *container = [DPPathOwners objectForKey:layer];
    if (!container || DPWindowCornerGrowth(container.window) <= 0) return animation;
    CGFloat base, grow, left, right;
    if (!DPCornerShape(container, &base, &grow, &left, &right)) return animation;
    CABasicAnimation *reshaped = [move copy];
    NSMapTable *past = DPGet(layer, &DPPastPathsKey);
    for (NSString *end in @[ @"fromValue", @"toValue" ]) {
        id value = [move valueForKey:end];
        CGPathRef path = (__bridge CGPathRef)([past objectForKey:value] ?: value);
        if (path && CGRectGetWidth(CGPathGetBoundingBox(path)) >= NSWidth(container.bounds) * 0.9)
            [reshaped setValue:(__bridge id)DPReshapeCorners(path, base * 1.6, grow * (1 - right), grow * (1 - left)) forKey:end];
    }
    return reshaped;
}

static NSString *DPVerifySquareCorners(DPPatch *patch) {
    for (NSView *container in DPFindViews(DPDiaContentContainer)) {
        CALayer *layer = DPRoundedContent(container).layer;
        if (!layer) return @"no rounded web content found";
        if (!DPBesideSidebar(container)) continue;
        BOOL square = patch->on && DPEdgeToEdge.on;
        BOOL round = [layer respondsToSelector:@selector(cornerRadii)] ? layer.cornerRadii.topLeft.width > 0
                   : layer.mask ? layer.mask.sublayers.firstObject.cornerRadius > 0 : (layer.maskedCorners & DPLeftCorners) != 0;
        if (round == square) return square ? @"corners by the sidebar are round" : @"corners by the sidebar are square";
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
