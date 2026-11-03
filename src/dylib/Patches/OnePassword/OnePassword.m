#import "StdPatch/StdPatch.h"
#include <spawn.h>

// 1Password's helper turns the patched Dia away, so diapatch stands in and relays through the original Dia.

extern DPPatch DPOnePassword;

static const char *DPDiapatch(void) {
    static char path[PATH_MAX];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *diapatch = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"DiaPatches/bin/diapatch"];
        strlcpy(path, diapatch.fileSystemRepresentation, sizeof path);
    });
    return path;
}

static int DPSpawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *files, const posix_spawnattr_t *attrs, char *const argv[], char *const envp[]) {
    const char *name = path ? strrchr(path, '/') : NULL;
    if (!DPOnePassword.on || !name || strcmp(name, "/1Password-BrowserSupport")) return posix_spawn(pid, path, files, attrs, argv, envp);
    int argc = 0;
    while (argv[argc]) argc++;
    char *redirected[argc + 1];
    memcpy(redirected, argv, (argc + 1) * sizeof *argv);
    redirected[0] = (char *)DPDiapatch();
    return posix_spawn(pid, redirected[0], files, attrs, redirected, envp);
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSpawn = {
    (const void *)DPSpawn, (const void *)posix_spawn
};

DP_PATCH(DPOnePassword) {
    .key = @"onePassword",
    .order = 102,
    .title = @"Allow 1Password",
    .detail = @"Lets the 1Password extension connect to the 1Password app, which turns away a patched Dia. While the extension is connected, the original Dia that DiaTweaks keeps runs in the background without windows and talks to 1Password for it. Experimental.",
    .symbol = @"lock.shield.fill",
    .tint = @"systemBlueColor",
    .section = @"Passwords",
};
