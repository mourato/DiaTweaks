#import <Foundation/Foundation.h>

extern NSString *const DPPasswordsAgent;
extern NSString *const DPCopyFolder;  // where the original Dia runs from while it relays

BOOL DPIsPasswordsOrigin(const char *origin);
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]);  // Started by a browser for iCloud Passwords.
int DPRunPasswordsRelay(NSString *home, NSString *app);                              // Started by launchd on the relay's socket.
NSDictionary *DPPasswordsAgentPlist(NSString *home, NSString *diapatch, NSDictionary *environment);
