#import "NetworkInterfaceCounterReader.h"

#import <net/if.h>
#import <net/route.h>
#import <sys/socket.h>
#import <sys/sysctl.h>

NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *CHNetworkInterfaceCounters(void) {
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0) {
        return @{};
    }

    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    if (sysctl(mib, 6, buffer.mutableBytes, &length, NULL, 0) != 0) {
        return @{};
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    uint8_t *cursor = buffer.mutableBytes;
    uint8_t *end = cursor + length;
    while (cursor + sizeof(struct if_msghdr) <= end) {
        struct if_msghdr *header = (struct if_msghdr *)cursor;
        if (header->ifm_msglen == 0 || cursor + header->ifm_msglen > end) {
            break;
        }
        if (header->ifm_type == RTM_IFINFO2
            && header->ifm_msglen >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
            char name[IF_NAMESIZE] = {0};
            if (if_indextoname(info->ifm_index, name) != NULL
                && (info->ifm_flags & IFF_UP) != 0
                && (info->ifm_flags & IFF_LOOPBACK) == 0) {
                NSString *interfaceName = [NSString stringWithUTF8String:name];
                result[interfaceName] = @{
                    @"received": @(info->ifm_data.ifi_ibytes),
                    @"sent": @(info->ifm_data.ifi_obytes)
                };
            }
        }
        cursor += header->ifm_msglen;
    }
    return result;
}
