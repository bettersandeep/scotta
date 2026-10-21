#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

// AppleSMC user-client ABI. The struct must stay exactly 80 bytes.
typedef struct { char major, minor, build, reserved; uint16_t release; } Vers;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } PLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Vers vers; PLimit plimit; KeyInfo info;
    uint8_t result, status, cmd; uint32_t data32; uint8_t bytes[32];
} Param;
_Static_assert(sizeof(Param) == 80, "SMC param layout");

enum { kHandleEvent = 2, kRead = 5, kWrite = 6, kGetInfo = 9 };

static io_connect_t conn;

static uint32_t fourcc(const char *k) { return (uint32_t)k[0] << 24 | (uint32_t)k[1] << 16 | (uint32_t)k[2] << 8 | (uint32_t)k[3]; }

static int call(Param *in, Param *out) {
    size_t sz = sizeof(Param);
    kern_return_t kr = IOConnectCallStructMethod(conn, kHandleEvent, in, sz, out, &sz);
    if (kr != KERN_SUCCESS) return kr;
    return out->result ? -(int)out->result : 0;
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return kIOReturnNotFound;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return kr;
}

static int info(const char *key, KeyInfo *ki) {
    Param in = {0}, out = {0};
    in.key = fourcc(key); in.cmd = kGetInfo;
    int r = call(&in, &out);
    if (!r) *ki = out.info;
    return r;
}

int smc_read(const char *key, uint8_t *buf, uint32_t *size) {
    KeyInfo ki; int r = info(key, &ki);
    if (r) return r;
    Param in = {0}, out = {0};
    in.key = fourcc(key); in.info = ki; in.cmd = kRead;
    if ((r = call(&in, &out))) return r;
    *size = ki.size > 32 ? 32 : ki.size;
    memcpy(buf, out.bytes, *size);
    return 0;
}

int smc_write(const char *key, const uint8_t *buf, uint32_t size) {
    KeyInfo ki; int r = info(key, &ki);
    if (r) return r;
    Param in = {0}, out = {0};
    in.key = fourcc(key); in.info = ki; in.cmd = kWrite;
    memcpy(in.bytes, buf, size < ki.size ? size : ki.size);
    return call(&in, &out);
}

// Private IOKit SPI from IOPMLibPrivate.h.
extern IOReturn IOPMSetSystemPowerSetting(CFStringRef key, CFTypeRef value);

int pm_set_sleep_disabled(int disabled) {
    return IOPMSetSystemPowerSetting(CFSTR("SleepDisabled"), disabled ? kCFBooleanTrue : kCFBooleanFalse);
}
