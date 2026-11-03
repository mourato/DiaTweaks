// Shared between the iCloud Passwords host and relay; Passwords.h is what the rest of diapatch uses.
#import <Foundation/Foundation.h>

// `key` gives the relay extension the manager's extension ID, as each helper only answers its own extension.
typedef struct {
    const char *origins[3];
    const char *host;
    const char *key;
    const char *socket;
} DPPasswordsService;

extern const DPPasswordsService DPPasswordsServices[2];
const DPPasswordsService *DPPasswordsServiceFor(const char *origin);
NSString *DPPasswordsSocket(NSString *home, const DPPasswordsService *service);

BOOL DPRunsPatchedDia(pid_t pid, NSString *app);
BOOL DPPatchedDiaRunning(NSString *app);
BOOL DPTrustedRelayPeer(int fd, NSString *app);

// The DevTools pipe to the original Dia.
void DPDevToolsAttach(int toDia, int fromDia);
void DPDevToolsCall(NSString *method, NSDictionary *params, NSString *session);
NSDictionary *DPDevToolsAsk(NSString *method, NSDictionary *params, NSString *session);
BOOL DPDevToolsRead(void);  // NO once Dia has closed the pipe
NSArray<NSDictionary *> *DPDevToolsTakeEvents(void);
int DPDevToolsInput(void);

// The original Dia, windowless, with the relay extension in it.
BOOL DPCopyStart(NSString *home);
void DPCopyEvaluate(const DPPasswordsService *service, NSString *expression);
void DPCopyQuit(void);
