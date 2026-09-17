#include "USBBridge.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
struct PTZUSBHandle { IOUSBDeviceInterface320 **device; };
static uint32_t number(io_service_t s, CFStringRef key) {
    CFTypeRef v = IORegistryEntryCreateCFProperty(s, key, kCFAllocatorDefault, 0);
    int64_t n = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberSInt64Type, &n);
    if (v) CFRelease(v);
    return (uint32_t)n;
}
int PTZUSBEnumerate(PTZUSBIdentity *out, int capacity) {
    io_iterator_t it = 0;
    IOReturn r = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it);
    fprintf(stderr, "[USB] enumerate IOReturn=0x%08x\n", r);
    if (r) return 0;
    int count = 0; io_service_t s;
    while ((s = IOIteratorNext(it))) {
        PTZUSBIdentity d = {0};
        IORegistryEntryGetRegistryEntryID(s, &d.registryID);
        d.vendor = number(s, CFSTR("idVendor")); d.product = number(s, CFSTR("idProduct"));
        d.location = number(s, CFSTR("locationID"));
        CFTypeRef n = IORegistryEntryCreateCFProperty(s, CFSTR("USB Product Name"), kCFAllocatorDefault, 0);
        if (n && CFGetTypeID(n) == CFStringGetTypeID()) CFStringGetCString(n, d.name, sizeof(d.name), kCFStringEncodingUTF8);
        if (n) CFRelease(n);
        fprintf(stderr, "[USB] VID=%04x PID=%04x location=%08x registry=%llu name=%s\n", d.vendor, d.product, d.location, d.registryID, d.name);
        if (d.vendor == 0x046d && count < capacity) out[count++] = d;
        IOObjectRelease(s);
    }
    IOObjectRelease(it); return count;
}
PTZUSBHandle *PTZUSBConnect(uint64_t id, int32_t *result) {
    *result = kIOReturnNoDevice;
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id));
    if (!s) return NULL;
    IOCFPlugInInterface **plugin = NULL; SInt32 score = 0;
    IOReturn r = IOCreatePlugInInterfaceForService(s, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(s);
    fprintf(stderr, "[USB] CreatePlugIn registry=%llu IOReturn=0x%08x\n", id, r);
    *result = r;
    if (r || !plugin) return NULL;
    IOUSBDeviceInterface320 **device = NULL;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), (LPVOID *)&device);
    (*plugin)->Release(plugin);
    fprintf(stderr, "[USB] QueryInterface320 HRESULT=0x%08x\n", (unsigned)hr);
    *result = hr;
    if (hr || !device) return NULL;
    PTZUSBHandle *h = calloc(1, sizeof(*h));
    if (!h) { *result = kIOReturnNoMemory; (*device)->Release(device); return NULL; }
    h->device = device;
    // DeviceRequestTO is documented to work without exclusive open. Do not seize,
    // reset, change configuration, or claim Apple's video streaming interface.
    return h;
}
void PTZUSBDisconnect(PTZUSBHandle *h) { if (h) { (*h->device)->Release(h->device); free(h); } }
int PTZUSBDescriptor(PTZUSBHandle *h, uint8_t *bytes, int capacity) {
    if (!h) return 0;
    UInt8 active = 0, count = 0;
    IOReturn r = (*h->device)->GetConfiguration(h->device, &active);
    fprintf(stderr, "[USB] GetConfiguration value=%u IOReturn=0x%08x\n", active, r);
    if (r) return 0;
    r = (*h->device)->GetNumberOfConfigurations(h->device, &count);
    if (r) return 0;
    for (UInt8 i = 0; i < count; i++) {
        IOUSBConfigurationDescriptorPtr d = NULL;
        r = (*h->device)->GetConfigurationDescriptorPtr(h->device, i, &d);
        fprintf(stderr, "[USB] ConfigurationDescriptor index=%u IOReturn=0x%08x\n", i, r);
        if (r || !d || d->bConfigurationValue != active) continue;
        const uint8_t *raw = (const uint8_t *)d;
        int length = raw[2] | (raw[3] << 8);
        if (length < 9 || length > capacity) return 0;
        memcpy(bytes, raw, length); return length;
    }
    return 0;
}
int32_t PTZUSBRequest(PTZUSBHandle *h, uint8_t type, uint8_t request, uint16_t value, uint16_t index, uint8_t *bytes, uint16_t length, uint32_t *actual) {
    if (!h) return kIOReturnNoDevice;
    IOUSBDevRequestTO q = {0};
    q.bmRequestType = type; q.bRequest = request; q.wValue = value; q.wIndex = index;
    q.pData = bytes; q.wLength = length; q.noDataTimeout = 500; q.completionTimeout = 1000;
    IOReturn r = (*h->device)->DeviceRequestTO(h->device, &q);
    *actual = q.wLenDone; return r;
}
