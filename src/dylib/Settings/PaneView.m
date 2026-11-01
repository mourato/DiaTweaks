#import "Settings.h"

NSToolbarItemIdentifier const DPSearchItemIdentifier = @"DiaPatchesSearch";

@implementation DPPaneView {
    NSScrollView *_overviewScroll, *_pageScroll;
    NSView *_page;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    _searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:DPSearchItemIdentifier];
    _searchItem.searchField.delegate = self;
    [_searchItem.searchField.widthAnchor constraintEqualToConstant:218].active = YES;
    _overview = [DPOverviewView new];
    __weak DPPaneView *weakSelf = self;
    _overview.open = ^(NSString *title, NSView *page) { [weakSelf openPage:page title:title]; };
    _overviewScroll = [self scrollFor:_overview];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(patchesDidChange:) name:DPPatchesDidChangeNotification object:nil];
    return self;
}

- (NSScrollView *)scrollFor:(NSView *)content {
    DPFlippedView *document = [DPFlippedView new];
    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.documentView = document;
    [document addSubview:content];
    [self addSubview:scroll];
    for (NSView *v in @[content, document, scroll]) v.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *fill = [content.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-48];
    fill.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        // Dia's toolbar sits over the top of the pane.
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor constant:52],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-20],
        [content.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],
        [content.widthAnchor constraintLessThanOrEqualToConstant:560],
        fill,
    ]];
    return scroll;
}

- (void)showPage:(NSView *)page {
    [_pageScroll removeFromSuperview];
    _page = page;
    _pageScroll = page ? [self scrollFor:page] : nil;
    _overviewScroll.hidden = page != nil;
}

- (void)openPage:(NSView *)page title:(NSString *)title {
    [self showPage:page];
    self.titleChanged(title, YES);
}

- (BOOL)showsPage { return _page != nil; }

- (void)goBack {
    if (!_page) return;
    [self showPage:nil];
    self.titleChanged(@"Patches", NO);
}

- (void)reset {
    [self showPage:nil];
    self.searchItem.searchField.stringValue = @"";
    [self.overview syncWithQuery:@""];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSString *query = self.searchItem.searchField.stringValue;
    if (query.length) [self goBack];
    [self.overview syncWithQuery:query];
}

- (void)patchesDidChange:(NSNotification *)notification {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.allowsImplicitAnimation = YES;
        [self.overview syncWithQuery:self.searchItem.searchField.stringValue];
        if ([self->_page isKindOfClass:DPPageView.class]) [(DPPageView *)self->_page sync];
        [self layoutSubtreeIfNeeded];
    }];
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor; }

// Unhandled events would reach Dia's pane underneath via the responder chain.
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
- (void)rightMouseDown:(NSEvent *)event {}
- (void)rightMouseUp:(NSEvent *)event {}
- (void)otherMouseDown:(NSEvent *)event {}
- (void)otherMouseUp:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}
- (NSMenu *)menuForEvent:(NSEvent *)event { return nil; }
@end
