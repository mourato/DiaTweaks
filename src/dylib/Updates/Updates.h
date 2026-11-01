// Updates go through the diapatch CLI: `check` finds them, `update` and `self-update` stage them, `apply` installs them.
#import "StdPatch/StdPatch.h"

void DPInstallUpdates(void);
void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output));
void DPHandOffAndQuit(NSArray<NSString *> *args);  // Quits Dia while the CLI runs `args`, then relaunches it.

extern NSString *const DPDia, *const DPTweaks;
NSString *DPPartName(NSString *part);

// Each level also does everything the ones before it do.
typedef NS_ENUM(NSInteger, DPAutoLevel) { DPAutoOff, DPAutoNotify, DPAutoDownload, DPAutoInstall };
DPAutoLevel DPAutoLevelOf(NSString *part);
void DPSetAutoLevel(NSString *part, DPAutoLevel level);

extern NSNotificationName const DPUpdatesDidChangeNotification;

@interface DPUpdates : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSDictionary *found;
@property (nonatomic, readonly) BOOL checking;
- (void)check:(void (^)(void))done;
- (BOOL)available:(NSString *)part;
- (BOOL)staged:(NSString *)part;
- (BOOL)downloading:(NSString *)part;
- (BOOL)failed:(NSString *)part;
- (double)progress:(NSString *)part;  // 0–1 while downloading, then -1 while it's verified and patched.
- (void)download:(NSString *)part then:(void (^)(void))done;
- (void)installAndRelaunch:(NSArray<NSString *> *)parts;

// For the Debug menu: shows a made-up update for `part` that downloads in a few seconds and installs without relaunching.
- (void)pretend:(NSString *)part;
- (void)stopPretending;
@end
