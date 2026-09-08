// Restricted monitor-only transports. Protocol facts: msigd, NEC PD SDK,
// USB HID Monitor Control (usage pages 0x80/0x82). No generic command interface.
#import "MonitorTransport.h"
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDDevice.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <poll.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
static NSDictionary *err(NSString *s) { return @{@"error":s}; }
static NSString *prop(IOHIDDeviceRef d, CFStringRef key) {
    id v=(__bridge id)IOHIDDeviceGetProperty(d,key); return v ? [v description] : @"";
}
static NSArray *devices(void) {
    IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,0);
    // Enumerate metadata only; never open the manager or a keyboard device.
    NSArray *matches=@[@{@"VendorID":@0x1462,@"ProductID":@0x3fa4},@{@"PrimaryUsagePage":@0x80}];
    IOHIDManagerSetDeviceMatchingMultiple(manager,(__bridge CFArrayRef)matches);
    CFSetRef set=IOHIDManagerCopyDevices(manager);
    NSArray *result=set ? [(__bridge NSSet *)set allObjects] : @[];
    if(set) CFRelease(set); CFRelease(manager); return result;
}
static bool msi(IOHIDDeviceRef d) { return [prop(d,CFSTR("VendorID")) intValue]==0x1462 && [prop(d,CFSTR("ProductID")) intValue]==0x3fa4; }
static NSString *key(IOHIDDeviceRef d) {
    NSString *serial=prop(d,CFSTR("SerialNumber"));
    return [NSString stringWithFormat:@"%@:%@:%@:%@",prop(d,CFSTR("VendorID")),prop(d,CFSTR("ProductID")),serial.length ? @"serial" : @"location",serial.length ? serial : prop(d,CFSTR("LocationID"))];
}
NSArray *PerchUSBMonitors(void) {
    NSMutableArray *out=[NSMutableArray array];
    for(id object in devices()) {
        IOHIDDeviceRef d=(__bridge IOHIDDeviceRef)object;
        if(out.count>=32) break;
        if(!msi(d) && [prop(d,CFSTR("PrimaryUsagePage")) intValue]!=0x80) continue;
        [out addObject:@{@"endpoint":key(d),@"kind":msi(d)?@"msi-usb":@"mccs-usb",@"name":prop(d,CFSTR("Product"))}];
    }
    return out;
}
// A report receiver exists only during one explicit monitor transaction.
typedef struct { uint8_t bytes[64]; size_t size; } Receiver;
static void received(void *context, IOReturn result, void *sender, IOHIDReportType type, uint32_t reportID, uint8_t *report, CFIndex length) {
    Receiver *r=context;
    if(result!=kIOReturnSuccess || length<2 || length>64 || r->size) return;
    memcpy(r->bytes,report,(size_t)length); r->size=(size_t)length;
}
static NSString *msiExchange(IOHIDDeviceRef d, NSString *text) {
    NSData *data=[text dataUsingEncoding:NSASCIIStringEncoding]; if(!data || data.length>60) return nil;
    uint8_t output[64]={1}, buffer[64]={0}; memcpy(output+1,data.bytes,data.length); output[data.length+1]=13;
    Receiver r={0};
    IOHIDDeviceRegisterInputReportCallback(d,buffer,sizeof(buffer),received,&r);
    IOHIDDeviceScheduleWithRunLoop(d,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    IOReturn result=IOHIDDeviceSetReport(d,kIOHIDReportTypeOutput,1,output,sizeof(output));
    CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+0.8;
    while(result==kIOReturnSuccess && !r.size && CFAbsoluteTimeGetCurrent()<end) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.02,true);
    IOHIDDeviceUnscheduleFromRunLoop(d,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(d,buffer,sizeof(buffer),NULL,NULL);
    if(!r.size || r.bytes[0]!=1) return nil;
    for(size_t i=1;i<r.size;i++) if(r.bytes[i]==13) return [[NSString alloc] initWithBytes:r.bytes+1 length:i-1 encoding:NSASCIIStringEncoding];
    return nil;
}
static NSString *msiGet(IOHIDDeviceRef d, NSString *code) {
    NSString *prefix=[@"5b" stringByAppendingString:code];
    NSString *reply=msiExchange(d,[@"58" stringByAppendingString:code]);
    return [reply hasPrefix:prefix] ? [reply substringFromIndex:prefix.length] : nil;
}
static NSDictionary *msiProfile(NSString *identity, NSString *version) {
    NSURL *url=[[NSBundle mainBundle] URLForResource:@"msi-input-profiles" withExtension:@"json"];
    // Command line helper lives in Contents/MacOS; NSBundle still resolves its app.
    NSData *data=url ? [NSData dataWithContentsOfURL:url] : nil;
    NSArray *profiles=data.length<=32768 ? [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil] : nil;
    if(![profiles isKindOfClass:[NSArray class]] || profiles.count>64) return nil;
    for(NSDictionary *p in profiles) if([p[@"identity"] isEqual:identity] && [p[@"version"] isEqual:version]) return p;
    return nil;
}
static NSDictionary *usb(NSDictionary *route, NSString *command, unsigned value) {
    IOHIDDeviceRef chosen=NULL; NSArray *all=devices();
    for(id object in all) { IOHIDDeviceRef d=(__bridge IOHIDDeviceRef)object;
        if([key(d) isEqual:route[@"endpoint"]]) { if(chosen) return err(@"USB monitor identity is ambiguous. Reconnect one device and choose it again."); chosen=d; }
    }
    if(!chosen) return err(@"USB control connection is unavailable. Check the monitor’s USB upstream cable.");
    bool isMSI=[route[@"kind"] isEqual:@"msi-usb"];
    if(isMSI!=msi(chosen) || (!isMSI && [prop(chosen,CFSTR("PrimaryUsagePage")) intValue]!=0x80)) return err(@"USB device does not match the selected monitor protocol.");
    if(IOHIDDeviceOpen(chosen,0)!=kIOReturnSuccess) return err(@"macOS could not open this monitor’s USB control interface.");
    NSDictionary *answer=nil;
    if(isMSI) {
        NSDictionary *profile=msiProfile(msiGet(chosen,@"00140"),msiGet(chosen,@"00150"));
        NSArray *names=profile[@"inputs"];
        if(!profile || names.count<2 || names.count>4) answer=err(@"This MSI firmware has no verified input mapping. USB input control is disabled.");
        else if([command isEqual:@"switch"]) {
            // UI codes are one-based, MSI wire values zero-based.
            if(value<1 || value>names.count) answer=err(@"Input is not in this MSI firmware profile.");
            else answer=[msiExchange(chosen,[NSString stringWithFormat:@"5b00500%03u",value-1]) isEqual:@"5600+"] ? @{@"sent":@YES} : err(@"MSI did not acknowledge the input command.");
        } else {
            NSString *s=msiGet(chosen,@"00500"); NSScanner *scan=[NSScanner scannerWithString:s ?: @""]; unsigned n=0;
            bool valid=s.length==3 && [scan scanHexInt:&n] && scan.isAtEnd && n<names.count;
            NSMutableArray *inputs=[NSMutableArray array]; for(NSUInteger i=0;i<names.count;i++) [inputs addObject:@{@"code":@(i+1),@"name":names[i]}];
            answer=@{@"current":valid ? @(n+1) : (id)[NSNull null],@"capabilities":[NSNull null],@"transportInputs":inputs,@"transportModel":profile[@"model"]};
        }
    } else {
        CFArrayRef raw=IOHIDDeviceCopyMatchingElements(chosen,NULL,0); IOHIDElementRef input=NULL;
        for(id object in (__bridge NSArray *)raw) { IOHIDElementRef e=(__bridge IOHIDElementRef)object;
            if(IOHIDElementGetUsagePage(e)==0x82 && IOHIDElementGetUsage(e)==0x60 && IOHIDElementGetType(e)==kIOHIDElementTypeFeature) { if(input) { input=NULL; break; } input=e; }
        }
        if(input && (IOHIDElementGetReportCount(input)!=1 || IOHIDElementGetReportSize(input)>32)) input=NULL;
        if(input) for(id object in (__bridge NSArray *)raw) {
            IOHIDElementRef other=(__bridge IOHIDElementRef)object;
            if(other!=input && IOHIDElementGetType(other)==kIOHIDElementTypeFeature && IOHIDElementGetReportID(other)==IOHIDElementGetReportID(input) && IOHIDElementGetUsage(other)!=0) { input=NULL;break; }
        }
        if(!input) answer=err(@"This USB monitor does not expose one writable MCCS input-source feature.");
        else if([command isEqual:@"switch"]) {
            if(value<1 || value<IOHIDElementGetLogicalMin(input) || value>IOHIDElementGetLogicalMax(input)) answer=err(@"Input is outside the USB descriptor’s supported range.");
            else { IOHIDValueRef v=IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault,input,0,value);
                IOReturn result=IOHIDDeviceSetValue(chosen,input,v); CFRelease(v);
                answer=result==kIOReturnSuccess ? @{@"sent":@YES} : err(@"USB monitor rejected the input-source feature write."); }
        } else { IOHIDValueRef v=NULL; IOReturn result=IOHIDDeviceGetValue(chosen,input,&v);
            answer=result==kIOReturnSuccess && v ? @{@"current":@(IOHIDValueGetIntegerValue(v)),@"capabilities":[NSNull null]} : err(@"USB monitor did not return its current input."); }
        if(raw) CFRelease(raw);
    }
    IOHIDDeviceClose(chosen,0); return answer ?: err(@"Monitor request failed.");
}
static NSData *necFrame(char address, char type, NSString *payload) {
    NSData *p=[payload dataUsingEncoding:NSASCIIStringEncoding]; if(!p || p.length>240) return nil;
    NSMutableData *d=[NSMutableData data]; uint8_t h[]={1,'0',address,'0',type}; [d appendBytes:h length:5];
    [d appendData:[[NSString stringWithFormat:@"%02X",(unsigned)p.length+2] dataUsingEncoding:NSASCIIStringEncoding]];
    uint8_t stx=2,etx=3; [d appendBytes:&stx length:1]; [d appendData:p]; [d appendBytes:&etx length:1];
    uint8_t sum=0; const uint8_t *b=d.bytes; for(NSUInteger i=1;i<d.length;i++) sum^=b[i]; uint8_t tail[]={sum,13}; [d appendBytes:tail length:2]; return d;
}
static NSString *necReply(NSData *data, char address, char type) {
    const uint8_t *b=data.bytes; if(data.length<11 || b[0]!=1 || b[1]!='0' || b[3]!=address || b[4]!=type || b[7]!=2) return nil;
    if(b[2]!='0' && b[2]!=address) return nil;
    char len[3]={(char)b[5],(char)b[6],0}; char *end; unsigned long size=strtoul(len,&end,16);
    if(*end || size<2 || size+9!=data.length || b[data.length-3]!=3 || b[data.length-1]!=13) return nil;
    uint8_t sum=0; for(NSUInteger i=1;i<data.length-2;i++) sum^=b[i]; if(sum!=b[data.length-2]) return nil;
    return [[NSString alloc] initWithBytes:b+8 length:size-2 encoding:NSASCIIStringEncoding];
}
static bool ready(int fd, short events) { struct pollfd p={fd,events,0}; return poll(&p,1,1000)>0 && (p.revents&events); }
static NSString *necExchange(int fd,char address,char type,NSString *payload) {
    NSData *out=necFrame(address,type,payload); const uint8_t *b=out.bytes; size_t n=0;
    while(n<out.length) { if(!ready(fd,POLLOUT)) return nil; ssize_t sent=write(fd,b+n,out.length-n); if(sent<=0) return nil; n+=sent; }
    uint8_t buffer[256]; size_t count=0,expected=0;
    while(count<sizeof(buffer)) { if(!ready(fd,POLLIN)) return nil; ssize_t got=read(fd,buffer+count,1); if(got!=1) return nil; count++;
        if(count==7) { char s[3]={buffer[5],buffer[6],0}; char *end; unsigned long length=strtoul(s,&end,16); if(*end || length<2 || length>247) return nil; expected=length+9; }
        if(expected && count==expected) return necReply([NSData dataWithBytes:buffer length:count],address,type+1);
    } return nil;
}
static void necClose(int fd, bool restore, const struct termios *original) {
    if(restore) tcsetattr(fd,TCSANOW,original);
    close(fd);
}
static NSDictionary *nec(NSDictionary *route,NSString *command,unsigned value) {
    struct termios original={0}; bool restore=false;
    NSString *endpoint=route[@"endpoint"]; int fd=-1; bool serial=[route[@"kind"] isEqual:@"nec-serial"];
    int monitor=[route[@"address"] intValue]; if(monitor<1 || monitor>26) return err(@"NEC monitor ID must be 1–26.");
    if([command isEqual:@"switch"] && ![route[@"model"] length]) return err(@"Check and save the NEC monitor identity before switching inputs.");
    if(serial) {
        if(![endpoint hasPrefix:@"/dev/cu."] || [endpoint containsString:@"/../"]) return err(@"Choose a /dev/cu. serial device.");
        fd=open(endpoint.fileSystemRepresentation,O_RDWR|O_NOCTTY|O_NONBLOCK|O_NOFOLLOW);
        struct stat st; struct termios config;
        if(fd<0 || fstat(fd,&st) || !S_ISCHR(st.st_mode) || tcgetattr(fd,&config)) { if(fd>=0)necClose(fd,restore,&original); return err(@"Serial monitor connection is unavailable."); }
        original=config;
        cfmakeraw(&config); cfsetspeed(&config,B9600); config.c_cflag|=CLOCAL|CREAD; config.c_cflag&=~CRTSCTS;
        if(tcsetattr(fd,TCSANOW,&config)) { necClose(fd,restore,&original); return err(@"Could not configure NEC serial connection."); }
        restore=true;
    } else {
        struct sockaddr_in addr={0}; addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_port=htons(7142);
        if(inet_pton(AF_INET,endpoint.UTF8String,&addr.sin_addr)!=1) return err(@"Enter the monitor’s IPv4 address. Network scanning is not used.");
        fd=socket(AF_INET,SOCK_STREAM,0); if(fd<0) return err(@"Could not create monitor connection.");
        int one=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one)); fcntl(fd,F_SETFL,O_NONBLOCK);
        if(connect(fd,(struct sockaddr *)&addr,sizeof(addr))<0 && errno!=EINPROGRESS) { necClose(fd,restore,&original); return err(@"NEC network connection failed."); }
        int error=0; socklen_t len=sizeof(error);
        if(!ready(fd,POLLOUT) || getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&len) || error) { necClose(fd,restore,&original); return err(@"NEC monitor did not accept a connection on port 7142."); }
    }
    char address='A'+monitor-1;
    NSString *modelReply=necExchange(fd,address,'A',@"C217"); NSMutableString *model=[NSMutableString string];
    if([modelReply hasPrefix:@"C317"] && modelReply.length<=164 && modelReply.length%2==0) {
        for(NSUInteger i=4;i<modelReply.length;i+=2) { unsigned v=0; NSScanner *s=[NSScanner scannerWithString:[modelReply substringWithRange:NSMakeRange(i,2)]]; if(![s scanHexInt:&v] || !s.isAtEnd || v>126) { [model setString:@""]; break; } if(!v)break; if(v<32){[model setString:@""];break;} [model appendFormat:@"%c",v]; }
    }
    if(!model.length || ([route[@"model"] length] && ![route[@"model"] isEqual:model])) {necClose(fd,restore,&original);return err(@"NEC identity was missing or changed. Check the monitor address and set up this connection again.");}
    NSString *reply=necExchange(fd,address,[command isEqual:@"switch"]?'E':'C',[command isEqual:@"switch"]?[NSString stringWithFormat:@"0060%04X",value]:@"0060");
    necClose(fd,restore,&original);
    if(reply.length!=16 || ![reply hasPrefix:@"000060"]) return err(@"NEC monitor rejected the input request.");
    unsigned current=0; NSScanner *s=[NSScanner scannerWithString:[reply substringFromIndex:12]];
    if(![s scanHexInt:&current] || !s.isAtEnd) return err(@"Invalid NEC input response.");
    return [command isEqual:@"switch"] ? @{@"sent":@YES} : @{@"current":@(current),@"capabilities":[NSNull null],@"transportModel":model};
}
NSDictionary *PerchMonitorTransport(NSDictionary *route, NSString *command, unsigned value) {
    if(![route isKindOfClass:[NSDictionary class]] || ![route[@"endpoint"] isKindOfClass:[NSString class]] || [route[@"endpoint"] length]>256 || ![@[@"inspect",@"read",@"switch"] containsObject:command] || ([command isEqual:@"switch"] && (value<1 || value>65535))) return err(@"Invalid monitor transport request.");
    if(![route[@"kind"] isKindOfClass:[NSString class]] || (route[@"model"] && ![route[@"model"] isKindOfClass:[NSString class]]) || ![route[@"address"] isKindOfClass:[NSNumber class]]) return err(@"Invalid monitor connection fields.");
    NSString *kind=route[@"kind"];
    if([kind isEqual:@"msi-usb"] || [kind isEqual:@"mccs-usb"]) return usb(route,command,value);
    if([kind isEqual:@"nec-lan"] || [kind isEqual:@"nec-serial"]) return nec(route,command,value);
    return err(@"Unknown monitor transport.");
}
bool PerchTransportSelfTest(void) {
    if([msiProfile(@"00;",@"V18")[@"inputs"] count]!=4 || msiProfile(@"unknown",@"V18")) return false;
    NSData *frame=necFrame('A','D',@"0000600000120011");
    NSMutableData *reply=[frame mutableCopy]; uint8_t *b=reply.mutableBytes; b[2]='0';b[3]='A'; b[reply.length-2]=0;for(NSUInteger i=1;i<reply.length-2;i++)b[reply.length-2]^=b[i];
    if(![necReply(reply,'A','D') isEqual:@"0000600000120011"])return false;
    for(NSUInteger i=0;i<reply.length;i++){ NSMutableData *bad=[reply mutableCopy];((uint8_t *)bad.mutableBytes)[i]^=0x80;if(necReply(bad,'A','D'))return false; }
    return necReply([reply subdataWithRange:NSMakeRange(0,reply.length-1)],'A','D')==nil;
}
