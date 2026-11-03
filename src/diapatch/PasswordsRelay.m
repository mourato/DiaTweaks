// One windowless original Dia, driven over its DevTools pipe, opens a native port to a password manager's helper for each client.
#import <launch.h>
#import <poll.h>
#import <sys/socket.h>
#import "Passwords.h"
#import "PasswordsParts.h"

NSString *const DPPasswordsAgent = @"com.diapatches.passwords";

static const uint32_t kMaxFrame = 64 << 20;  // Chromium's own limit for messages to a host
// Each wake of the iCloud Passwords extension reconnects, so the copy stays warm between them rather than restarting.
static const NSTimeInterval kIdleQuit = 600;

static NSMutableDictionary<NSNumber *, NSNumber *> *gClients;  // id → socket
static NSMutableDictionary<NSNumber *, NSMutableData *> *gPending;
static NSMutableDictionary<NSNumber *, NSValue *> *gServices;
static FILE *gLog;
static volatile sig_atomic_t gStopping;

NSDictionary *DPPasswordsAgentPlist(NSString *home, NSString *diapatch, NSDictionary *environment) {
    return @{
        @"Label" : DPPasswordsAgent,
        @"ProgramArguments" : @[ diapatch, @"passwords-relay" ],
        @"EnvironmentVariables" : environment,
        @"Sockets" : @{
            @(DPPasswordsServices[0].socket) : @{ @"SockPathName" : DPPasswordsSocket(home, &DPPasswordsServices[0]), @"SockPathMode" : @0600 },
            @(DPPasswordsServices[1].socket) : @{ @"SockPathName" : DPPasswordsSocket(home, &DPPasswordsServices[1]), @"SockPathMode" : @0600 },
        },
        @"ProcessType" : @"Interactive",
    };
}

static void logLine(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void logLine(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    char stamp[20];
    time_t now = time(NULL);
    strftime(stamp, sizeof stamp, "%F %T", localtime(&now));
    fprintf(gLog, "%s passwords-relay[%d] %s\n", stamp, getpid(), line.UTF8String);
}

static BOOL writeFrame(int fd, id message) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:NSJSONWritingFragmentsAllowed error:nil];
    uint32_t length = (uint32_t)json.length;
    NSMutableData *frame = [NSMutableData dataWithBytes:&length length:4];
    [frame appendData:json];
    for (NSUInteger sent = 0; sent < frame.length;) {
        ssize_t n = write(fd, (const char *)frame.bytes + sent, frame.length - sent);
        if (n <= 0) return NO;
        sent += n;
    }
    return YES;
}

static const DPPasswordsService *serviceOf(NSNumber *client) { return gServices[client].pointerValue; }

static void drop(NSNumber *client, BOOL tellDia) {
    close(gClients[client].intValue);
    [gClients removeObjectForKey:client];
    if (tellDia) DPCopyEvaluate(serviceOf(client), [NSString stringWithFormat:@"relayClose(%@)", client]);
    [gPending removeObjectForKey:client];
    [gServices removeObjectForKey:client];
}

// Each message is parsed and serialized again before it becomes JavaScript, so it can only ever be a JSON value.
static BOOL forward(NSNumber *client) {
    char chunk[65536];
    ssize_t got = read(gClients[client].intValue, chunk, sizeof chunk);
    if (got <= 0) return NO;
    NSMutableData *pending = gPending[client];
    [pending appendBytes:chunk length:got];
    for (uint32_t length; pending.length >= 4 && (memcpy(&length, pending.bytes, 4), pending.length >= 4 + (NSUInteger)length);) {
        if (length > kMaxFrame) return NO;
        id message = [NSJSONSerialization JSONObjectWithData:[pending subdataWithRange:NSMakeRange(4, length)] options:NSJSONReadingFragmentsAllowed error:nil];
        [pending replaceBytesInRange:NSMakeRange(0, 4 + length) withBytes:NULL length:0];
        NSData *json = message ? [NSJSONSerialization dataWithJSONObject:message options:NSJSONWritingFragmentsAllowed error:nil] : nil;
        if (!json) return NO;
        DPCopyEvaluate(serviceOf(client), [NSString stringWithFormat:@"relayPost(%@, %@)", client, [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]);
    }
    return YES;
}

static BOOL deliver(void) {
    for (NSDictionary *event in DPDevToolsTakeEvents()) {
        if ([event[@"method"] isEqual:@"Target.detachedFromTarget"]) return NO;
        if (![event[@"method"] isEqual:@"Runtime.bindingCalled"] || ![event[@"params"][@"name"] isEqual:@"relayOut"]) continue;
        NSDictionary *out = [NSJSONSerialization JSONObjectWithData:[event[@"params"][@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSNumber *client = out[@"id"];
        if (!gClients[client]) continue;
        if (out[@"closed"] || !writeFrame(gClients[client].intValue, out[@"message"])) drop(client, NO);
    }
    return YES;
}

static void accepted(int fd, const DPPasswordsService *service, NSString *home, NSString *app) {
    static int lastID;
    if (!DPTrustedRelayPeer(fd, app)) return (void)(logLine(@"refused a client that isn't diapatch started by the patched Dia"), close(fd));
    if (DPDevToolsInput() < 0) {
        logLine(@"starting the original Dia");
        if (!DPCopyStart(home)) return (void)(logLine(@"the original Dia didn't start the relay extension"), close(fd), exit(1));
    }
    NSNumber *client = @(++lastID);
    gClients[client] = @(fd);
    gPending[client] = [NSMutableData data];
    gServices[client] = [NSValue valueWithPointer:service];
    DPCopyEvaluate(service, [NSString stringWithFormat:@"relayOpen(%@, '%s')", client, service->host]);
}

static void stop(int signal) { gStopping = 1; }

int DPRunPasswordsRelay(NSString *home, NSString *app) {
    int listeners[2];
    for (int i = 0; i < 2; i++) {
        int *fds = NULL;
        size_t count = 0;
        if (launch_activate_socket(DPPasswordsServices[i].socket, &fds, &count) != 0 || count != 1) return 1;
        listeners[i] = fds[0];
        free(fds);
    }
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, stop);
    gLog = fopen([home stringByAppendingPathComponent:@"diapatch.log"].fileSystemRepresentation, "a") ?: stderr;
    setvbuf(gLog, NULL, _IOLBF, 0);
    atexit(DPCopyQuit);
    gClients = [NSMutableDictionary dictionary];
    gPending = [NSMutableDictionary dictionary];
    gServices = [NSMutableDictionary dictionary];
    NSDate *idleSince = NSDate.date;
    while (!gStopping && (gClients.count || (-idleSince.timeIntervalSinceNow < kIdleQuit && DPPatchedDiaRunning(app)))) {
        NSArray<NSNumber *> *ids = gClients.allKeys;
        struct pollfd fds[3 + ids.count];
        for (int i = 0; i < 2; i++) fds[i] = (struct pollfd){ .fd = listeners[i], .events = POLLIN };
        fds[2] = (struct pollfd){ .fd = DPDevToolsInput(), .events = POLLIN };
        for (NSUInteger i = 0; i < ids.count; i++) fds[3 + i] = (struct pollfd){ .fd = gClients[ids[i]].intValue, .events = POLLIN };
        if (poll(fds, 3 + ids.count, 5000) < 0 && errno != EINTR) break;
        for (int i = 0; i < 2; i++) {
            int fd = fds[i].revents ? accept(listeners[i], NULL, NULL) : -1;
            if (fd >= 0) accepted(fd, &DPPasswordsServices[i], home, app);
        }
        if (fds[2].revents && !DPDevToolsRead()) break;
        if (!deliver()) break;
        for (NSUInteger i = 0; i < ids.count; i++)
            if (gClients[ids[i]] && fds[3 + i].revents && !forward(ids[i])) drop(ids[i], YES);
        if (gClients.count) idleSince = NSDate.date;
    }
    logLine(@"%@", gStopping ? @"stopping" : gClients.count ? @"the original Dia went away" : @"idle, quitting the original Dia");
    for (NSNumber *client in gClients.allKeys) drop(client, NO);
    return 0;
}
