#import "HideToolbar.h"

static const CGFloat DPToolbarHoverHeight = 8;
static char DPHoverKey;

// Eases from `from` to `to` over a quarter second, calling `step` on each frame.
static NSTimer *DPEase(CGFloat from, CGFloat to, void (^step)(CGFloat value, BOOL done)) {
    CFTimeInterval start = CACurrentMediaTime();
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        CGFloat t = MIN(1, (CACurrentMediaTime() - start) / 0.25);
        if (t == 1) [timer invalidate];
        step(from + (to - from) * t * t * (3 - 2 * t), t == 1);
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}

@implementation DPToolbarHover

+ (DPToolbarHover *)forPane:(NSView *)pane {
    return DPGet(pane, &DPHoverKey);
}

+ (DPToolbarHover *)attachToPane:(NSView *)pane {
    DPToolbarHover *hover = [self forPane:pane];
    if (hover) return hover;
    hover = [DPToolbarHover new];
    hover.pane = pane;
    DPSet(pane, &DPHoverKey, hover);
    return hover;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(windowResignedKey:) name:NSWindowDidResignKeyNotification object:nil];
    [center addObserver:self selector:@selector(reset) name:NSApplicationDidResignActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [_animation invalidate];
    [_hideTimer invalidate];
    [_inPlaceAnimation invalidate];
    if (_tracking) [_pane removeTrackingArea:_tracking];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)reset {
    [self.animation invalidate];
    [self.hideTimer invalidate];
    self.animation = self.hideTimer = nil;
    _revealed = NO;
    self.progress = 0;
    if (self.pane) DPApplyToolbar(self.pane);
}

- (void)windowResignedKey:(NSNotification *)notification {
    if (notification.object == self.pane.window) [self reset];
}

- (BOOL)containsPointer {
    NSWindow *window = self.pane.window;
    if (!window.isKeyWindow || !NSApp.isActive || self.pane.hiddenOrHasHiddenAncestor) return NO;
    NSPoint point = [self.pane convertPoint:[window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
    return self.tracking && NSMouseInRect(point, self.tracking.rect, self.pane.isFlipped);
}

- (BOOL)toolbarHasFocus {
    NSResponder *responder = self.pane.window.firstResponder;
    // The shared field editor lives outside the toolbar; its delegate is the edited control.
    if ([responder isKindOfClass:NSTextView.class] && ((NSTextView *)responder).isFieldEditor)
        responder = (NSResponder *)((NSTextView *)responder).delegate;
    return [responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self.bar];
}

- (void)setRevealed:(BOOL)revealed {
    if (_revealed == revealed) return;
    _revealed = revealed;
    [self.animation invalidate];
    __weak DPToolbarHover *weakSelf = self;
    self.animation = DPEase(self.progress, revealed, ^(CGFloat value, BOOL done) {
        DPToolbarHover *me = weakSelf;
        if (!me.pane) return;
        me.progress = value;
        DPApplyToolbarOpacity(me);
        if (!done) return;
        me.animation = nil;
        DPApplyToolbar(me.pane);  // Settle stacking once, after the fade.
    });
    DPApplyToolbar(self.pane);
}

// Unlike a hover reveal, this brings the toolbar back into its place, so the page moves down with each frame.
- (void)setInPlace:(BOOL)inPlace {
    if (_inPlace == inPlace) return;
    _inPlace = inPlace;
    [self.inPlaceAnimation invalidate];
    __weak DPToolbarHover *weakSelf = self;
    self.inPlaceAnimation = DPEase(self.inPlaceProgress, inPlace, ^(CGFloat value, BOOL done) {
        DPToolbarHover *me = weakSelf;
        if (!me.pane) return;
        me.inPlaceProgress = value;
        if (done) me.inPlaceAnimation = nil;
        DPApplyToolbar(me.pane);
    });
}

- (void)mouseEntered:(NSEvent *)event {
    if (!DPHideToolbar.on || !DPRevealToolbarOnHover.on || ![self containsPointer]) return;
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    self.revealed = YES;
}

- (void)mouseExited:(NSEvent *)event {
    // Growing the tracking area on reveal sends an exit from the old, narrow strip.
    if (!self.revealed || [self containsPointer] || self.hideTimer) return;
    __weak DPToolbarHover *weakSelf = self;
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        DPToolbarHover *me = weakSelf;
        if (!me) return [timer invalidate];
        if (![me containsPointer] && ([me toolbarHasFocus] || NSEvent.pressedMouseButtons)) return;
        [timer invalidate];
        me.hideTimer = nil;
        if (![me containsPointer]) me.revealed = NO;
    }];
}

- (void)updateForBar:(NSView *)bar bookmarks:(NSView *)bookmarks {
    self.bar = bar;
    self.bookmarks = bookmarks;
    self.inPlace = DPKeptInPlace(self.pane);
    NSRect rect = NSZeroRect;
    // Nothing to reveal while the toolbar is already in its place.
    if (DPHideToolbar.on && DPRevealToolbarOnHover.on && !self.inPlace && !bar.hiddenOrHasHiddenAncestor) {
        rect = DPLaidOutFrame(bar);
        if (bookmarks) rect = NSUnionRect(rect, DPLaidOutFrame(bookmarks));
        rect = NSIntersectionRect(rect, self.pane.bounds);
        CGFloat height = MIN(DPToolbarHoverHeight, NSHeight(rect));
        if (self.revealed) {
            // A margin below the revealed bar keeps it from flickering at its edge.
            if (!self.pane.isFlipped) rect.origin.y -= DPToolbarHoverHeight;
            rect.size.height += DPToolbarHoverHeight;
            rect = NSIntersectionRect(rect, self.pane.bounds);
        } else {
            if (!self.pane.isFlipped) rect.origin.y = NSMaxY(rect) - height;
            rect.size.height = height;
        }
    } else {
        [self.animation invalidate];
        [self.hideTimer invalidate];
        self.animation = self.hideTimer = nil;
        _revealed = NO;
        self.progress = 0;
    }
    if (self.tracking && NSEqualRects(self.tracking.rect, rect)) return;
    if (self.tracking) [self.pane removeTrackingArea:self.tracking];
    self.tracking = nil;
    if (NSIsEmptyRect(rect)) return;
    self.tracking = [[NSTrackingArea alloc] initWithRect:rect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
                                                   owner:self userInfo:nil];
    [self.pane addTrackingArea:self.tracking];
}
@end
