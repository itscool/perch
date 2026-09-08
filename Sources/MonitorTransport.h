#import <Foundation/Foundation.h>
NSArray *PerchUSBMonitors(void);
NSDictionary *PerchMonitorTransport(NSDictionary *route, NSString *command, unsigned value);
bool PerchTransportSelfTest(void);
