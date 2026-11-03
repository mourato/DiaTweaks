// The add-on's entry point: Dia loads this dylib before its own code runs. Patches register themselves with DP_PATCH.
#import "StdPatch/StdPatch.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"
#import "Test/Test.h"
#import "DevTools/DevTools.h"

__attribute__((constructor)) static void DPInit(void) {
    // `make` loads the dylib into diapatch only to list the patches for diatweaks: no patching, prefs or safe mode.
    // Checking the process keeps a DIAPATCH_MANIFEST left in a shell from making Dia quit at launch.
    NSString *manifest = NSProcessInfo.processInfo.environment[@"DIAPATCH_MANIFEST"];
    if (manifest && [NSProcessInfo.processInfo.processName isEqualToString:@"diapatch"]) _exit(DPWriteManifest(manifest) ? 0 : 1);
    DPBeginLaunch();
    if (DPSafeMode == 2) return;
    DPLoadPatches();
    if (!DPSafeMode) DPInstallPatches();
    DPInstallSettings();
    DPInstallUpdates();
    DPInstallDevTools();

    NSString *report = NSProcessInfo.processInfo.environment[@"DIAPATCH_TEST"];
    unsetenv("DIAPATCH_TEST");  // Dia relaunched from Settings would inherit it and test again.
    if (report) DPRunTests(report);
}
