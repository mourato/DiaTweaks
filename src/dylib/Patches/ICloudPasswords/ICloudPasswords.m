#import "StdPatch/StdPatch.h"
#include <libproc.h>

// Apple's iCloud Passwords extension asks for this host by name, and Chromium prefers a user's copy of a host over the
// system's, so registering it here sends the extension to diapatch, which relays it through the original Dia.

extern DPPatch DPICloudPasswords;

static NSString *DPHostManifestPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"];
}

static NSString *DPDiapatchPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DiaPatches/bin/diapatch"];
}

// Another app's override of Apple's host stays as it is.
static BOOL DPHostIsOursOrAbsent(void) {
    NSData *data = [NSData dataWithContentsOfFile:DPHostManifestPath()];
    if (!data) return YES;
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] && [host[@"path"] isEqual:DPDiapatchPath()];
}

static void DPRegisterHost(BOOL on) {
    if (!DPHostIsOursOrAbsent()) return (void)NSLog(@"DiaPatches: another app has replaced the iCloud Passwords host, so it stays");
    if (!on) return (void)[NSFileManager.defaultManager removeItemAtPath:DPHostManifestPath() error:nil];
    NSDictionary *manifest = @{
        @"name" : @"com.apple.passwordmanager",
        @"description" : @"DiaTweaks relay to iCloud Passwords",
        @"path" : DPDiapatchPath(),
        @"type" : @"stdio",
        @"allowed_origins" : @[ @"chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/", @"chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" ],
    };
    [NSFileManager.defaultManager createDirectoryAtPath:DPHostManifestPath().stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:DPHostManifestPath() atomically:YES];
}

// The relay quits the original Dia a few seconds after this one quits. Opened again before then, Dia would find it
// still running and refuse to start ("Dia is already open"), so it's stopped first; this runs before Dia checks.
static void DPStopOriginalDia(void) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    NSString *pristine = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia"];
    NSArray<NSString *> *originals = @[ pristine.stringByResolvingSymlinksInPath, @"/Applications/.DiaTweaks/Dia.app/Contents/MacOS/Dia" ];
    int capacity = proc_listallpids(NULL, 0) + 64;
    pid_t pids[capacity];
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids);
    for (int i = 0; i < count; i++) {
        if (proc_pidpath(pids[i], path, sizeof path) <= 0 || ![originals containsObject:@(path)]) continue;
        kill(pids[i], SIGKILL);
        for (int tries = 0; tries < 50 && kill(pids[i], 0) == 0; tries++) usleep(20000);
    }
}

static void DPInstallICloudPasswords(void) {
    DPStopOriginalDia();
    DPRegisterHost(DPICloudPasswords.on);
}

static void DPApplyICloudPasswords(DPPatch *patch) { DPRegisterHost(patch->on); }

DP_PATCH(DPICloudPasswords) {
    .key = @"icloudPasswords",
    .order = 101,
    .title = @"Allow iCloud Passwords",
    .detail = @"Lets the iCloud Passwords extension fill passwords from Apple Passwords, which a patched Dia can't reach. While the extension is connected, the original Dia that DiaTweaks keeps runs in the background without windows and talks to Apple Passwords for it. Experimental.",
    .symbol = @"key.fill",
    .tint = @"systemBlueColor",
    .section = @"Passwords",
    .install = DPInstallICloudPasswords,
    .apply = DPApplyICloudPasswords,
};
