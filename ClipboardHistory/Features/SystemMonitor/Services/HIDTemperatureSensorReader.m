#import "HIDTemperatureSensorReader.h"
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

#define CHHIDEventFieldBase(type) (type << 16)
#define CHHIDEventTypeTemperature 15

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

NSDictionary<NSString *, NSNumber *> *CHAppleSiliconTemperatureSensors(void) {
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(0xff00),
        @"PrimaryUsage": @(0x0005)
    };
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        return @{};
    }
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return @{};
    }

    NSMutableDictionary<NSString *, NSNumber *> *values = [NSMutableDictionary dictionary];
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex index = 0; index < count; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        CFTypeRef productValue = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        NSString *product = CFBridgingRelease(productValue);
        if (product.length == 0) {
            continue;
        }
        BOOL isVerifiedCPUOrSoC = [product hasPrefix:@"pACC MTR Temp"]
            || [product hasPrefix:@"eACC MTR Temp"]
            || [product hasPrefix:@"SOC MTR Temp"]
            || ([product hasPrefix:@"PMU"] && [product containsString:@" tdie"]);
        if (!isVerifiedCPUOrSoC) {
            continue;
        }
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(
            service,
            CHHIDEventTypeTemperature,
            0,
            0
        );
        if (event == NULL) {
            continue;
        }
        double celsius = IOHIDEventGetFloatValue(
            event,
            CHHIDEventFieldBase(CHHIDEventTypeTemperature)
        );
        CFRelease(event);
        if (isfinite(celsius) && celsius >= 10 && celsius <= 130) {
            values[product] = @(celsius);
        }
    }
    CFRelease(services);
    CFRelease(client);
    return values;
}
