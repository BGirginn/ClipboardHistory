#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary<NSString *, NSNumber *> *CHAppleSiliconTemperatureSensors(void);
mach_port_t CHMachTaskSelf(void);

NS_ASSUME_NONNULL_END
