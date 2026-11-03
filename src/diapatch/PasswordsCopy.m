#import <AppKit/AppKit.h>
#import <spawn.h>
#import <sys/clonefile.h>
#import <sys/wait.h>
#import "Passwords.h"
#import "PasswordsParts.h"

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);  // private: macOS then asks about the copy, not Dia

static NSString *const kRelayScript =
    @"const ports = new Map();\n"
     "globalThis.relayOpen = (id, host) => {\n"
     "  const port = chrome.runtime.connectNative(host);\n"
     "  ports.set(id, port);\n"
     "  port.onMessage.addListener((message) => relayOut(JSON.stringify({ id, message })));\n"
     "  port.onDisconnect.addListener(() => { ports.delete(id); relayOut(JSON.stringify({ id, closed: true })); });\n"
     "};\n"
     "globalThis.relayPost = (id, message) => ports.get(id)?.postMessage(message);\n"
     "globalThis.relayClose = (id) => { ports.get(id)?.disconnect(); ports.delete(id); };\n";

NSString *const DPCopyFolder = @"/Applications/.DiaTweaks";

static pid_t gDia;
static NSString *gSessions[2];

static BOOL writeExtension(NSString *folder, const DPPasswordsService *service) {
    NSDictionary *manifest = @{
        @"manifest_version" : @3, @"name" : @"DiaTweaks passwords relay", @"version" : @"1", @"key" : @(service->key),
        @"permissions" : @[ @"nativeMessaging" ], @"background" : @{ @"service_worker" : @"relay.js" },
    };
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToFile:[folder stringByAppendingPathComponent:@"manifest.json"] atomically:YES]
        && [kRelayScript writeToFile:[folder stringByAppendingPathComponent:@"relay.js"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Its preferences live under CFFIXED_USER_HOME, so the copy never offers to update itself or shows its intro.
static void quieten(NSString *data) {
    NSString *preferences = [data stringByAppendingPathComponent:@"Library/Preferences/company.thebrowser.dia"];
    for (NSArray *setting in @[ @[ @"SUEnableAutomaticChecks", @"NO" ], @[ @"SUAutomaticallyUpdate", @"NO" ], @[ @"hasPresentedOnboardingIntro", @"YES" ] ])
        [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:@[ @"write", preferences, setting[0], @"-bool", setting[1] ]] waitUntilExit];
}

static int highFD(int fd) {
    int moved = fcntl(fd, F_DUPFD_CLOEXEC, 10);
    close(fd);
    return moved;
}

// 1Password's helper checks its browser's signature, and its sandbox can only read apps under /Applications.
static NSString *runnableCopy(NSString *home) {
    NSString *pristine = [home stringByAppendingPathComponent:@"pristine/Dia.app"], *clone = [DPCopyFolder stringByAppendingPathComponent:@"Dia.app"];
    [NSFileManager.defaultManager removeItemAtPath:clone error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:DPCopyFolder withIntermediateDirectories:YES attributes:nil error:nil];
    return clonefile(pristine.fileSystemRepresentation, clone.fileSystemRepresentation, 0) == 0 ? clone : pristine;
}

// Chromium looks for native hosts under the copy's home, its data folder.
static void linkOnePasswordHost(NSString *data) {
    NSString *path = @"Library/Application Support/Google/Chrome/NativeMessagingHosts/com.1password.1password.json";
    NSString *link = [data stringByAppendingPathComponent:path];
    [NSFileManager.defaultManager createDirectoryAtPath:link.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtPath:link error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:[NSHomeDirectory() stringByAppendingPathComponent:path] error:nil];
}

static pid_t launch(NSString *home) {
    NSString *data = [home stringByAppendingPathComponent:@"passwords-helper"];
    [NSFileManager.defaultManager createDirectoryAtPath:data withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:nil];
    NSMutableArray<NSString *> *extensions = [NSMutableArray array];
    for (const DPPasswordsService *service = DPPasswordsServices; service < DPPasswordsServices + 2; service++) {
        NSString *extension = [data stringByAppendingPathComponent:[@"extension-" stringByAppendingString:@(service->host)]];
        if (!writeExtension(extension, service)) return 0;
        [extensions addObject:extension];
    }
    linkOnePasswordHost(data);
    quieten(data);
    int toDia[2], fromDia[2];
    if (pipe(toDia) || pipe(fromDia)) return 0;
    toDia[0] = highFD(toDia[0]), toDia[1] = highFD(toDia[1]), fromDia[0] = highFD(fromDia[0]), fromDia[1] = highFD(fromDia[1]);

    NSString *app = [runnableCopy(home) stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[data stringByAppendingPathComponent:@"ud"]];
    NSString *load = [@"--load-extension=" stringByAppendingString:[extensions componentsJoinedByString:@","]];
    const char *argv[] = { app.fileSystemRepresentation, profile.UTF8String, load.UTF8String, "--remote-debugging-pipe", "--no-startup-window", "--mute-audio", NULL };
    NSMutableArray<NSString *> *environment = [NSMutableArray arrayWithObject:[@"CFFIXED_USER_HOME=" stringByAppendingString:data]];
    for (char **e = environ; *e; e++) [environment addObject:@(*e)];
    const char **envp = calloc(environment.count + 1, sizeof *envp);
    for (NSUInteger i = 0; i < environment.count; i++) envp[i] = environment[i].UTF8String;

    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&files, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_adddup2(&files, toDia[0], 3);
    posix_spawn_file_actions_adddup2(&files, fromDia[1], 4);
    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_CLOEXEC_DEFAULT);  // keeps the relay's sockets out of Dia
    responsibility_spawnattrs_setdisclaim(&attrs, 1);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], &files, &attrs, (char *const *)argv, (char *const *)envp);
    free(envp);
    close(toDia[0]);
    close(fromDia[1]);
    if (status != 0) return 0;
    DPDevToolsAttach(toDia[1], fromDia[0]);
    // --no-startup-window still leaves it a window (Dia's sign-in on a new profile), which opens a few seconds in and
    // shows the app again, so it's hidden until then.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (int tries = 0; tries < 200; tries++, usleep(100000)) {
            NSRunningApplication *copy = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            if (copy && !copy.hidden) [copy hide];
        }
    });
    return pid;
}

static NSString *relayWorker(const DPPasswordsService *service) {
    for (int tries = 0; tries < 120; tries++, usleep(250000))
        for (NSDictionary *target in DPDevToolsAsk(@"Target.getTargets", nil, nil)[@"result"][@"targetInfos"])
            if ([target[@"type"] isEqual:@"service_worker"] && [target[@"url"] hasPrefix:@(service->origins[0])]) return target[@"targetId"];
    return nil;
}

static NSString *attach(const DPPasswordsService *service) {
    NSString *worker = relayWorker(service);
    NSString *session = worker ? DPDevToolsAsk(@"Target.attachToTarget", @{ @"targetId" : worker, @"flatten" : @YES }, nil)[@"result"][@"sessionId"] : nil;
    return session && DPDevToolsAsk(@"Runtime.addBinding", @{ @"name" : @"relayOut" }, session) ? session : nil;
}

// Launch Services would send links and "open Dia" to the windowless copy.
static void unregister(void) {
    NSTask *task = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"]
                                               arguments:@[ @"-u", [DPCopyFolder stringByAppendingPathComponent:@"Dia.app"] ] error:nil terminationHandler:nil];
    [task waitUntilExit];
}

BOOL DPCopyStart(NSString *home) {
    gDia = launch(home);
    for (int i = 0; i < 2; i++) gSessions[i] = gDia ? attach(&DPPasswordsServices[i]) : nil;
    unregister();
    return gSessions[0] && gSessions[1];
}

void DPCopyEvaluate(const DPPasswordsService *service, NSString *expression) {
    DPDevToolsCall(@"Runtime.evaluate", @{ @"expression" : expression }, gSessions[service - DPPasswordsServices]);
}

void DPCopyQuit(void) {
    if (!gDia) return;
    DPDevToolsCall(@"Browser.close", nil, nil);
    for (int i = 0; i < 50 && waitpid(gDia, NULL, WNOHANG) == 0; i++) usleep(100000);
    kill(gDia, SIGKILL);
    gDia = 0;
}
