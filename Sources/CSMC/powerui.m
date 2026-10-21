#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "smc.h"

// Private PowerUI SPI, as listed by the ObjC runtime on macOS 27.
@interface PowerUISmartChargeClient : NSObject
- (instancetype)initWithClientName:(NSString *)name;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)e;
- (unsigned char)getMCLLimitWithError:(NSError **)e;
- (BOOL)enableMCL:(NSError **)e;
- (BOOL)disableMCL:(NSError **)e;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)e;
@end

static PowerUISmartChargeClient *client(void) {
    static PowerUISmartChargeClient *c;
    if (!c && dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW)) {
        Class cls = NSClassFromString(@"PowerUISmartChargeClient");
        c = [[cls alloc] initWithClientName:@"com.scotta.daemon"];   // kept for the process lifetime
    }
    return c;
}

int pui_get(int *enabled, int *limit) {
    @autoreleasepool {
        PowerUISmartChargeClient *c = client();
        if (!c) return -1;
        NSError *e = nil;
        *enabled = (int)[c isMCLCurrentlyEnabled:&e];
        if (e) return -2;
        *limit = [c getMCLLimitWithError:&e];
        return e ? -2 : 0;
    }
}

int pui_set_limit(int pct) {
    @autoreleasepool {
        PowerUISmartChargeClient *c = client();
        if (!c) return -1;
        NSError *e = nil;
        if (![c isMCLCurrentlyEnabled:&e] && ![c enableMCL:&e]) return -2;
        return [c setMCLLimit:(unsigned char)pct error:&e] ? 0 : -3;
    }
}

int pui_disable(void) {
    @autoreleasepool {
        PowerUISmartChargeClient *c = client();
        if (!c) return -1;
        NSError *e = nil;
        return [c disableMCL:&e] ? 0 : -2;
    }
}
