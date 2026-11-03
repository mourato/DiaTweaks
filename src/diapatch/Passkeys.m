// Each request runs in the unpatched Dia, in a window the size of the passkey sheet so the sheet hides it.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/file.h>
#import <sys/wait.h>
#import "Passkeys.h"

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);  // private: macOS then asks about the copy, not Dia

static const int kSheetWidth = 480, kSheetHeight = 300;

static FILE *gFromHelper, *gToHelper;

static NSDictionary *readFromHelper(void) {
    NSMutableData *data = [NSMutableData data];
    for (int c; (c = fgetc(gFromHelper)) != 0;) {
        if (c == EOF) return nil;
        [data appendBytes:&(char){ c } length:1];
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSDictionary *send(NSString *method, NSDictionary *params, NSString *session) {
    static int lastId;
    int id = ++lastId;
    NSMutableDictionary *message = [@{ @"id" : @(id), @"method" : method, @"params" : params ?: @{} } mutableCopy];
    message[@"sessionId"] = session;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    fwrite(data.bytes, 1, data.length, gToHelper);
    fputc(0, gToHelper);
    fflush(gToHelper);
    for (NSDictionary *reply; (reply = readFromHelper());)
        if ([reply[@"id"] intValue] == id) return reply;
    return nil;
}

static id evaluate(NSString *session, NSString *expression) {
    NSDictionary *params = @{ @"expression" : expression, @"awaitPromise" : @YES, @"returnByValue" : @YES, @"userGesture" : @YES };
    return send(@"Runtime.evaluate", params, session)[@"result"][@"result"][@"value"];
}

static NSDictionary *readMessage(void) {
    uint32_t length;
    if (fread(&length, 4, 1, stdin) != 1) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (fread(data.mutableBytes, 1, length, stdin) != length) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static void writeMessage(NSDictionary *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    uint32_t length = (uint32_t)data.length;
    fwrite(&length, 4, 1, stdout);
    fwrite(data.bytes, 1, length, stdout);
    fflush(stdout);
}

static NSDictionary *failure(NSString *message) { return @{ @"error" : @{ @"name" : @"NotAllowedError", @"message" : message } }; }

static NSArray<NSString *> *const kAccountStore = @[ @"global_key_value_store.db", @"global_key_value_store.db-wal", @"global_key_value_store.db-shm" ];

static NSArray *modificationDates(NSString *folder) {
    NSMutableArray *dates = [NSMutableArray array];
    for (NSString *name in kAccountStore)
        [dates addObject:[NSFileManager.defaultManager attributesOfItemAtPath:[folder stringByAppendingPathComponent:name] error:nil].fileModificationDate ?: NSNull.null];
    return dates;
}

// Dia may be writing to its account store, so it's copied until the files hold still.
static void signInAsDia(NSString *userData) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *dia = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data"];
    [files createDirectoryAtPath:userData withIntermediateDirectories:YES attributes:nil error:nil];
    for (int tries = 0; tries < 5; tries++) {
        NSArray *before = modificationDates(dia);
        for (NSString *name in kAccountStore) {
            [files removeItemAtPath:[userData stringByAppendingPathComponent:name] error:nil];
            [files copyItemAtPath:[dia stringByAppendingPathComponent:name] toPath:[userData stringByAppendingPathComponent:name] error:nil];
        }
        if ([modificationDates(dia) isEqual:before]) return;
    }
}

static void skipIntro(NSString *data) {
    NSString *preferences = [data stringByAppendingPathComponent:@"Library/Preferences/company.thebrowser.dia"];
    [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:@[ @"write", preferences, @"hasPresentedOnboardingIntro", @"-bool", @"YES" ]] waitUntilExit];
}

static void forgetWindows(NSString *userData) {
    for (NSString *saved in @[ @"Sessions", @"Sessions_Encrypted", @"tabs.db", @"tabs.db-wal", @"tabs.db-shm" ])
        [NSFileManager.defaultManager removeItemAtPath:[userData stringByAppendingPathComponent:[@"Default" stringByAppendingPathComponent:saved]] error:nil];
}

static NSDictionary *sheetBounds(void) {
    CGRect screen = CGDisplayBounds(CGMainDisplayID());
    return @{
        @"left" : @((int)(CGRectGetMidX(screen) - kSheetWidth / 2)), @"top" : @((int)(CGRectGetMidY(screen) - kSheetHeight / 2 - 100)),
        @"width" : @(kSheetWidth), @"height" : @(kSheetHeight),
    };
}

static pid_t launchHelper(NSString *home, int toHelper[2], int fromHelper[2]) {
    NSString *data = [home stringByAppendingPathComponent:@"passkey-helper"];
    NSString *userData = [data stringByAppendingPathComponent:@"ud/User Data"];
    signInAsDia(userData);
    skipIntro(data);
    forgetWindows(userData);

    NSString *app = [home stringByAppendingPathComponent:@"pristine/Dia.app/Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[data stringByAppendingPathComponent:@"ud"]];
    NSDictionary *bounds = sheetBounds();
    NSString *size = [NSString stringWithFormat:@"--window-size=%@,%@", bounds[@"width"], bounds[@"height"]];
    NSString *position = [NSString stringWithFormat:@"--window-position=%@,%@", bounds[@"left"], bounds[@"top"]];
    const char *argv[] = { app.fileSystemRepresentation, profile.UTF8String, size.UTF8String, position.UTF8String, "--remote-debugging-pipe", "--mute-audio", NULL };

    NSMutableArray<NSString *> *environment = [NSMutableArray array];
    for (char **e = environ; *e; e++) [environment addObject:@(*e)];
    [environment addObject:[@"CFFIXED_USER_HOME=" stringByAppendingString:data]];
    const char **envp = calloc(environment.count + 1, sizeof *envp);
    for (NSUInteger i = 0; i < environment.count; i++) envp[i] = environment[i].UTF8String;

    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_adddup2(&files, toHelper[0], 3);
    posix_spawn_file_actions_adddup2(&files, fromHelper[1], 4);
    posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&files, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0);
    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    responsibility_spawnattrs_setdisclaim(&attrs, 1);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], &files, &attrs, (char *const *)argv, (char *const *)envp);
    free(envp);
    return status == 0 ? pid : 0;
}

static BOOL hasWindowOnScreen(pid_t pid) {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *window in windows)
        if ([window[(id)kCGWindowOwnerPID] intValue] == pid && [window[(id)kCGWindowLayer] intValue] == 0) return YES;
    return NO;
}

typedef NS_ENUM(int, DPStartup) { DPStartupReady, DPStartupSignedOut, DPStartupFailed };

// Signed out, Dia shows its intro: a window of its own that no tab lives in.
static DPStartup waitForStartupTab(pid_t pid, int seconds, NSString **targetId, NSNumber **windowId) {
    for (int tries = 0, tablessWindow = 0; tries < seconds * 4; tries++, usleep(250000)) {
        NSDictionary *targets = send(@"Target.getTargets", nil, nil);
        if (!targets) return DPStartupFailed;
        for (NSDictionary *target in targets[@"result"][@"targetInfos"]) {
            if (![target[@"type"] isEqualToString:@"page"]) continue;
            NSDictionary *window = send(@"Browser.getWindowForTarget", @{ @"targetId" : target[@"targetId"] }, nil)[@"result"];
            if (![window[@"bounds"][@"width"] intValue]) continue;
            *targetId = target[@"targetId"];
            *windowId = window[@"windowId"];
            return DPStartupReady;
        }
        tablessWindow = hasWindowOnScreen(pid) ? tablessWindow + 1 : 0;
        if (tablessWindow == 8) return DPStartupSignedOut;
    }
    return DPStartupFailed;
}

static NSString *page(NSString *title, NSString *detail) {
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta name=color-scheme content='light dark'><title>Passkey</title>"
         "<style>html,body{height:100%%;margin:0}body{display:grid;place-items:center;text-align:center;font:13px -apple-system,sans-serif;"
         "background:Canvas;color:CanvasText}b{display:block;font-size:15px;margin-bottom:6px}p{margin:0;opacity:.6}</style>"
         "<div><b>%@</b><p>%@</p></div>", title, detail];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[ html ] options:0 error:nil];
    return [NSString stringWithFormat:@"document.open(); document.write(%@[0].replace('{site}', location.host)); document.close()",
                                      [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
}

static BOOL atOrigin(NSString *session, NSString *origin) {
    for (int tries = 0; tries < 50; tries++, usleep(100000)) {
        NSArray *state = evaluate(session, @"[location.origin, document.readyState]");
        if ([state.lastObject isEqual:@"complete"]) return [state.firstObject isEqual:origin];
    }
    return NO;
}

// Only the frontmost app can bring another forward, and that's Dia.
static void tellDia(NSString *what, pid_t helper) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:[@"com.diapatches.passkeys." stringByAppendingString:what]
                                                                 object:@(helper).stringValue
                                                               userInfo:nil
                                                     deliverImmediately:YES];
}

static NSDictionary *runInHelper(pid_t pid, NSString *kind, NSString *origin, id options) {
    NSString *targetId;
    NSNumber *windowId;
    DPStartup startup = waitForStartupTab(pid, 60, &targetId, &windowId);
    if (startup == DPStartupSignedOut) {
        tellDia(@"signIn", pid);
        startup = waitForStartupTab(pid, 600, &targetId, &windowId);
    }
    if (startup != DPStartupReady) return failure(@"The passkey copy of Dia didn't open.");

    send(@"Browser.setWindowBounds", @{ @"windowId" : windowId, @"bounds" : sheetBounds() }, nil);
    NSString *session = send(@"Target.attachToTarget", @{ @"targetId" : targetId, @"flatten" : @YES }, nil)[@"result"][@"sessionId"];
    // Any page at the origin works, and robots.txt runs none of the site's scripts.
    for (NSString *path in @[ @"/robots.txt", @"/" ]) {
        send(@"Page.navigate", @{ @"url" : [origin stringByAppendingString:path] }, session);
        if (atOrigin(session, origin)) break;
    }
    evaluate(session, page(@"Use your passkey for {site}", @"DiaTweaks opened this window to reach Apple Passwords. It closes by itself."));
    tellDia(@"show", pid);
    // WebAuthn refuses a page without focus, which it only gets once Dia has brought the copy forward.
    for (int tries = 0; tries < 30; tries++, usleep(100000))
        if ([evaluate(session, @"document.hasFocus()") boolValue]) break;

    NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"kind" : kind, @"options" : options } options:0 error:nil];
    // The timeout stops a picker left open from blocking every request after it.
    NSString *script = [NSString stringWithFormat:@"(async ({ kind, options }) => {"
                                                    "  const signal = AbortSignal.timeout(Math.min(options.timeout || 300000, 600000));"
                                                    "  try {"
                                                    "    const credential = kind === 'create'"
                                                    "      ? await navigator.credentials.create({ publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options), signal })"
                                                    "      : await navigator.credentials.get({ publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options), signal });"
                                                    "    return { credential: credential.toJSON() };"
                                                    "  } catch (e) { return { error: { name: e.name === 'TimeoutError' ? 'NotAllowedError' : e.name, message: e.message } }; }"
                                                    "})(%@)",
                                                   [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    NSDictionary *result = evaluate(session, script);
    if (result[@"credential"]) evaluate(session, page(@"Done", @"This window closes in a moment. Thanks for waiting."));
    return result ?: failure(@"The passkey copy of Dia quit before answering.");
}

int DPRunPasskeyHost(NSString *home) {
    NSDictionary *request = readMessage();
    if (!request) return 1;
    // A second copy started on the same data hands off to the first and quits.
    flock(open([home stringByAppendingPathComponent:@"passkey-helper.lock"].fileSystemRepresentation, O_CREAT | O_RDWR, 0600), LOCK_EX);

    int toHelper[2], fromHelper[2];
    pid_t pid = 0;
    if (pipe(toHelper) || pipe(fromHelper) || !(pid = launchHelper(home, toHelper, fromHelper)))
        return writeMessage(failure(@"Couldn't start the passkey copy of Dia.")), 1;
    close(toHelper[0]);
    close(fromHelper[1]);

    gFromHelper = fdopen(fromHelper[0], "r");
    gToHelper = fdopen(toHelper[1], "w");
    NSDictionary *result = runInHelper(pid, request[@"kind"], request[@"origin"], request[@"options"]);
    // Dia kills this process once it has the answer, so the copy has to quit before then.
    send(@"Browser.close", nil, nil);
    for (int i = 0; i < 50 && waitpid(pid, NULL, WNOHANG) == 0; i++) usleep(100000);
    kill(pid, SIGKILL);
    writeMessage(result);
    return 0;
}
