// Shared by edge-to-edge and square corners, which only works on top of it.
#import "StdPatch/StdPatch.h"

extern DPPatch DPEdgeToEdge, DPSquareSidebarCorners;
extern const CGFloat DPWindowPadding;
extern NSHashTable<NSView *> *DPContainers;  // Every web content container Dia placed.
static const CACornerMask DPLeftCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
static const CACornerMask DPRightCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;

NSValue *DPRequestedFrame(NSView *container);   // Where Dia put the container, before edge-to-edge grew it.
NSView *DPRoundedContent(NSView *container);    // The view inside the container that clips the page to rounded corners.
NSView *DPChatCard(NSView *container);          // The page's card while Chat is open beside it, else nil.
CGFloat DPBaseCornerRadius(NSView *container);  // Dia's radius for the container, before edge-to-edge grows it.
void DPInstallRestyle(void);
void DPRestyleContainer(NSView *container);
void DPApplySquareCorners(NSView *container);
BOOL DPBesideSidebar(NSView *container);
BOOL DPFullScreen(NSView *container);  // In a full screen window, with edge-to-edge not stepping aside for Chat.
CGPathRef DPReshapeCorners(CGPathRef path, CGFloat extent, CGFloat rightScale, CGFloat leftScale);
