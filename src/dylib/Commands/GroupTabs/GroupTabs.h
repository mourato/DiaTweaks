// Group Tabs by Domain is a one-shot command in the tab context menu and the Tabs menu, shown while its patch is on. The hooks only remember
// live browsers and web contents so the command can read each tab's session ID; nothing is grouped until it's chosen.
#import "StdPatch/StdPatch.h"

void DPInstallGroupTabs(void);

// Tracking.m: what the hooks remembered.
id DPCommandBrowser(void);  // The front window's browser, or the only one.
id DPGroupingDelegate(id browser);
NSArray *DPTrackedContents(id browser);
long long DPSessionOf(id contents);

// Messages.m
long long DPLongID(id value);
id DPMsg(id object, SEL sel);
BOOL DPMsgBool(id object, SEL sel);
NSString *DPText(id value);

// Plan.m: which groups to create and which tabs to add to existing ones.
NSString *DPDomainKey(NSString *urlString);
NSArray<NSDictionary *> *DPOps(NSArray<NSDictionary *> *tabs, NSArray *groups);

// Order.m: where tabs sit, so undo can put them back.
NSDictionary *DPTabPlaces(NSDictionary<NSNumber *, NSString *> *urls);
void DPRestorePlaces(id delegate, id browser, NSDictionary *places);

void DPGroupTabsOnce(void);  // Grouping.m
void DPInstallGroupMenus(void);  // Menu.m
