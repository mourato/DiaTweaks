#import "Patches/EdgeToEdge/EdgeToEdge.h"

NSHashTable<NSView *> *DPContainers;
static NSUInteger restyles, frameWrites;
static BOOL chatVisible;
static NSView *chatCard;
static NSValue *requested;
void DPApplySquareCorners(NSView *view) { restyles++; }
NSView *DPChatCard(NSView *view) { return chatVisible ? chatCard : nil; }
NSValue *DPRequestedFrame(NSView *view) { return requested; }
#import "Patches/EdgeToEdge/Restyle.m"

@interface CountingContainer : NSView
@end
@implementation CountingContainer
- (void)layout {}  // Dia's own work is outside this fixture.
- (void)updateLayer {}
- (void)setFrame:(NSRect)frame { frameWrites++; [super setFrame:frame]; }
@end
static void drain(void) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}
int main(void) {
    @autoreleasepool {
        Class container = objc_allocateClassPair(CountingContainer.class, DPDiaContentContainer, 0);
        Class shadowClass = objc_allocateClassPair(CountingContainer.class, DPDiaShadowView, 0);
        objc_registerClassPair(container); objc_registerClassPair(shadowClass);
        DPInstallRestyle();
        NSView *first = [container new], *second = [container new], *shadow = [shadowClass new];
        [first addSubview:shadow]; chatCard = [NSView new];
        for (int i = 0; i < 1000; i++) {
            if (i % 2) [first layout]; else [first updateLayer];
        }
        NSCAssert(restyles == 1000, @"every hook preserves its immediate restyle");
        drain();
        NSUInteger followups = restyles - 1000;
#ifdef DP_OPTIMIZED
        NSCAssert(followups == 1, @"same-turn layout and layer hooks share one follow-up");
#else
        NSCAssert(followups == 1000, @"baseline queues every follow-up");
#endif
        printf("deferred_restyles=%lu for 1000 layout/layer events\n", (unsigned long)followups);
        NSUInteger before = restyles;
        chatVisible = YES; requested = [NSValue valueWithRect:NSMakeRect(10, 20, 300, 400)];
        [first layout]; [shadow layout]; [second layout]; drain();
#ifdef DP_OPTIMIZED
        NSCAssert(restyles == before + 4, @"two immediate and one deferred restyle per container");
#endif
        NSCAssert([DPGet(first, &DPChatKey) boolValue], @"Chat transition survives shared scheduling");
        NSCAssert(NSEqualRects(first.frame, requested.rectValue), @"opening Chat restores Dia's frame");
        chatVisible = NO; frameWrites = 0;
        [shadow layout]; drain();
        NSCAssert(![DPGet(first, &DPChatKey) boolValue], @"closing Chat is detected");
        NSCAssert(frameWrites == 1, @"closing Chat restores its frame");
        before = restyles; [first layout]; drain();
        NSCAssert(restyles == before + 2, @"later turns still update");
        puts("PASS: real hooks, immediate styling, independent views, later turns, Chat open/close frames");
    }
}
