#import <poll.h>
#import "PasswordsParts.h"

static int gToDia = -1, gFromDia = -1, gLastCall;
static NSMutableData *gBuffer;
static NSMutableArray<NSDictionary *> *gMessages;

void DPDevToolsAttach(int toDia, int fromDia) {
    gToDia = toDia;
    gFromDia = fromDia;
    gBuffer = [NSMutableData data];
    gMessages = [NSMutableArray array];
}

int DPDevToolsInput(void) { return gFromDia; }

void DPDevToolsCall(NSString *method, NSDictionary *params, NSString *session) {
    NSMutableDictionary *message = [@{ @"id" : @(++gLastCall), @"method" : method, @"params" : params ?: @{} } mutableCopy];
    message[@"sessionId"] = session;
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
    [data appendBytes:"" length:1];
    for (NSUInteger sent = 0; sent < data.length;) {
        ssize_t n = write(gToDia, (const char *)data.bytes + sent, data.length - sent);
        if (n <= 0) return;
        sent += n;
    }
}

BOOL DPDevToolsRead(void) {
    char chunk[65536];
    ssize_t got = read(gFromDia, chunk, sizeof chunk);
    if (got <= 0) return NO;
    [gBuffer appendBytes:chunk length:got];
    NSData *end = [NSData dataWithBytes:"" length:1];
    for (NSRange found; (found = [gBuffer rangeOfData:end options:0 range:NSMakeRange(0, gBuffer.length)]).location != NSNotFound;) {
        id message = [NSJSONSerialization JSONObjectWithData:[gBuffer subdataWithRange:NSMakeRange(0, found.location)] options:0 error:nil];
        [gBuffer replaceBytesInRange:NSMakeRange(0, found.location + 1) withBytes:NULL length:0];
        if ([message isKindOfClass:NSDictionary.class]) [gMessages addObject:message];
    }
    return YES;
}

NSDictionary *DPDevToolsAsk(NSString *method, NSDictionary *params, NSString *session) {
    DPDevToolsCall(method, params, session);
    int call = gLastCall;
    for (NSDate *until = [NSDate dateWithTimeIntervalSinceNow:15]; until.timeIntervalSinceNow > 0;) {
        for (NSDictionary *message in gMessages)
            if ([message[@"id"] intValue] == call) {
                [gMessages removeObject:message];
                return message;
            }
        struct pollfd fd = { .fd = gFromDia, .events = POLLIN };
        if (poll(&fd, 1, 250) > 0 && !DPDevToolsRead()) return nil;
    }
    return nil;
}

// Replies to calls nobody waits for are dropped with them.
NSArray<NSDictionary *> *DPDevToolsTakeEvents(void) {
    NSIndexSet *events = [gMessages indexesOfObjectsPassingTest:^BOOL(NSDictionary *message, NSUInteger i, BOOL *stop) { return message[@"method"] != nil; }];
    NSArray *taken = [gMessages objectsAtIndexes:events];
    [gMessages removeAllObjects];
    return taken;
}
