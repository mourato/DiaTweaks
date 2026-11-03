// The Patches row and pane, added to Dia's Settings window after Dia's own sidebar rows.
#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import "SafeMode/SafeMode.h"

void DPInstallSettings(void);
void DPInstallPreviews(void);

extern NSToolbarItemIdentifier const DPSearchItemIdentifier;

// Controls.m: the pieces the pane is built from, styled like macOS System Settings.
NSView *DPGroup(NSArray<NSView *> *rows);
NSView *DPRow(NSView *leading, NSView *trailing);
NSView *DPLinkRow(NSView *row, NSString *title, void (^open)(void));
NSTextField *DPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
NSTextField *DPHeader(NSString *text);
NSView *DPIconTile(NSString *symbol, NSColor *color);
NSView *DPIconTileOfSize(NSString *symbol, NSColor *color, CGFloat size);
NSImageView *DPSymbol(NSString *symbol, CGFloat size, NSColor *color);
NSStackView *DPColumn(NSArray<NSView *> *views, CGFloat spacing);
void DPFillStack(NSStackView *stack, NSArray<NSView *> *views);

@interface DPFlippedView : NSView
@end

@interface DPFillView : NSView
@end

@interface DPPatchSwitch : NSSwitch
@property (nonatomic, readonly) DPPatch *patch;
@property (nonatomic, readonly) NSImageView *hiddenIcon;
- (NSView *)withHiddenIcon;
- (instancetype)initWithPatch:(DPPatch *)patch;
- (void)sync;
@end

void DPForEachOption(DPPatch *patch, void (^body)(DPPatch *option));
NSString *DPWhyDisabled(DPPatch *patch);
NSString *DPWhyHidden(DPPatch *patch);
NSString *DPWhyHiddenBy(DPPatch *disabler);
NSURL *DPWikiURL(DPPatch *patch);

@interface DPPreviewView : DPFillView
- (instancetype)initWithKey:(NSString *)key;
+ (void)preload;
@end

@interface DPPageView : NSStackView
- (instancetype)initWithPatch:(DPPatch *)patch;
- (void)sync;
@end

@interface DPOverviewView : NSStackView
@property (nonatomic, copy) void (^open)(NSString *title, NSView *page);
@property (nonatomic, strong) NSMapTable<NSView *, NSString *> *searchText;
@property (nonatomic, strong) NSTextField *updateSummary;
- (void)syncWithQuery:(NSString *)query;
@end

@interface DPSoftwareUpdateView : NSStackView
@end

@interface DPOverviewView (Updates)
- (NSArray<NSView *> *)makeUpdateRows;
- (NSView *)makeSafeModeRow;
- (void)refresh;
@end

@interface DPPaneView : NSView <NSSearchFieldDelegate>
@property (nonatomic, strong) NSSearchToolbarItem *searchItem;
@property (nonatomic, strong) DPOverviewView *overview;
@property (nonatomic, copy) void (^titleChanged)(NSString *title, BOOL canGoBack);
@property (nonatomic, readonly) BOOL showsPage;
- (void)goBack;
- (void)reset;
@end
