#ifndef USBBridge_h
#define USBBridge_h
#include <stdint.h>
typedef struct { uint64_t registryID; uint32_t location; uint16_t vendor, product; char name[256]; } PTZUSBIdentity;
typedef struct PTZUSBHandle PTZUSBHandle;
int PTZUSBEnumerate(PTZUSBIdentity *devices, int capacity);
PTZUSBHandle *PTZUSBConnect(uint64_t registryID, int32_t *result);
void PTZUSBDisconnect(PTZUSBHandle *handle);
int PTZUSBDescriptor(PTZUSBHandle *handle, uint8_t *bytes, int capacity);
int32_t PTZUSBRequest(PTZUSBHandle *handle, uint8_t type, uint8_t request, uint16_t value, uint16_t index, uint8_t *bytes, uint16_t length, uint32_t *actual);
#endif
