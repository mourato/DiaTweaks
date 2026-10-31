// Shared with hide toolbar, which leaves the toolbar to the Peek's header in a Peek window.
#import "StdPatch/StdPatch.h"

extern DPPatch DPPeek;
extern const CGFloat DPPeekHeaderHeight;
BOOL DPInPeek(NSView *view);  // Whether the view's window is shown as a Peek.
