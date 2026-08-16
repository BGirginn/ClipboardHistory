import Darwin
import Foundation
import IOKit
import SystemConfiguration

actor SystemMetricsProvider: SystemMetricsProviding {
    private struct CPUTicks: Sendable {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
    }

    private struct ByteCounters: Sendable {
        var first: UInt64
        var second: UInt64
    }

    private struct DiskCounters: Sendable {
        var total: ByteCounters
        var devices: [String: (read: UInt64, written: UInt64, name: String, isExternal: Bool)]
    }

    private let temperatureProvider: any TemperatureSensorProviding
    private var previousCPU: CPUTicks?
    private var previousNetwork: ByteCounters?
    private var previousDisk: ByteCounters?
    private var previousDiskDevices: [String: (read: UInt64, written: UInt64)] = [:]
    private var previousDate: Date?
    private var networkInterfaceScope: NetworkInterfaceScope = .primaryWiFi

    init(temperatureProvider: any TemperatureSensorProviding = AppleTemperatureSensorProvider()) {
        self.temperatureProvider = temperatureProvider
    }

    func setNetworkInterfaceScope(_ scope: NetworkInterfaceScope) {
        guard networkInterfaceScope != scope else { return }
        networkInterfaceScope = scope
        previousNetwork = nil
    }

    func resetBaselines() {
        previousCPU = nil
        previousNetwork = nil
        previousDisk = nil
        previousDiskDevices = [:]
        previousDate = nil
    }

    func sample(at date: Date = .now) async -> SystemMetricSnapshot {
        let interval = max(date.timeIntervalSince(previousDate ?? date), 0)
        let cpu = readCPUUsage()
        let memory = readMemoryUsage()
        let network = readNetworkRate(interval: interval)
        let disk = readDiskRate(interval: interval)
        let temperatures = temperatureProvider.readings()
        previousDate = date
        return SystemMetricSnapshot(
            timestamp: date,
            cpu: cpu,
            memory: memory,
            network: network,
            disk: disk,
            temperatures: temperatures,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private func readCPUUsage() -> CPUUsageSnapshot {
        guard let current = hostCPUTicks() else { return .empty }
        let total = percentageSnapshot(previous: previousCPU, current: current)
        previousCPU = current
        return CPUUsageSnapshot(
            totalPercent: total.totalPercent,
            userPercent: total.userPercent,
            systemPercent: total.systemPercent,
            idlePercent: total.idlePercent
        )
    }

    private func percentageSnapshot(previous: CPUTicks?, current: CPUTicks) -> CPUUsageSnapshot {
        guard let previous else { return .empty }
        let user = current.user >= previous.user ? current.user - previous.user : 0
        let system = current.system >= previous.system ? current.system - previous.system : 0
        let idle = current.idle >= previous.idle ? current.idle - previous.idle : 0
        let nice = current.nice >= previous.nice ? current.nice - previous.nice : 0
        let total = user + system + idle + nice
        guard total > 0 else { return .empty }
        let divisor = Double(total)
        return CPUUsageSnapshot(
            totalPercent: Double(user + system + nice) / divisor * 100,
            userPercent: Double(user + nice) / divisor * 100,
            systemPercent: Double(system) / divisor * 100,
            idlePercent: Double(idle) / divisor * 100
        )
    }

    private func hostCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return ticks(from: info.cpu_ticks)
    }

    private func ticks(from tuple: (UInt32, UInt32, UInt32, UInt32)) -> CPUTicks {
        CPUTicks(
            user: UInt64(tuple.0),
            system: UInt64(tuple.1),
            idle: UInt64(tuple.2),
            nice: UInt64(tuple.3)
        )
    }

    private func readMemoryUsage() -> MemoryUsageSnapshot {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .empty }
        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        let pageSize = UInt64(hostPageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let active = UInt64(statistics.active_count) * pageSize
        let inactive = UInt64(statistics.inactive_count) * pageSize
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let cached = UInt64(statistics.external_page_count) * pageSize
        let free = UInt64(statistics.free_count + statistics.speculative_count) * pageSize
        let used = min(total, active + wired + compressed)
        return MemoryUsageSnapshot(
            totalBytes: total,
            usedBytes: used,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free,
            pressure: memoryPressureLevel()
        )
    }

    private func memoryPressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        if level >= 4 { return .critical }
        if level >= 2 { return .warning }
        return .normal
    }

    private func readNetworkRate(interval: TimeInterval) -> NetworkRateSnapshot {
        let interface = networkInterfaceScope == .primaryWiFi ? primaryInterfaceName() : nil
        let counters = networkCounters(interfaceName: interface)
        defer { previousNetwork = counters }
        guard interval > 0, let previousNetwork else {
            return NetworkRateSnapshot(
                receivedBytesPerSecond: 0,
                sentBytesPerSecond: 0,
                interfaceName: networkInterfaceScope == .allPhysical
                    ? String(localized: "All physical interfaces")
                    : interface
            )
        }
        return NetworkRateSnapshot(
            receivedBytesPerSecond: rate(current: counters.first, previous: previousNetwork.first, interval: interval),
            sentBytesPerSecond: rate(current: counters.second, previous: previousNetwork.second, interval: interval),
            interfaceName: networkInterfaceScope == .allPhysical
                ? String(localized: "All physical interfaces")
                : interface
        )
    }

    private func primaryInterfaceName() -> String? {
        guard let value = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString),
              let dictionary = value as? [String: Any] else { return nil }
        return dictionary["PrimaryInterface"] as? String
    }

    private func networkCounters(interfaceName: String?) -> ByteCounters {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return ByteCounters(first: 0, second: 0) }
        defer { freeifaddrs(head) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            let isEligible = (flags & IFF_UP) != 0
                && (flags & IFF_LOOPBACK) == 0
                && (interfaceName == nil || name == interfaceName)
                && (interfaceName != nil || isPhysicalNetworkInterface(name))
            if isEligible, let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received &+= UInt64(data.pointee.ifi_ibytes)
                sent &+= UInt64(data.pointee.ifi_obytes)
            }
            cursor = entry.ifa_next
        }
        return ByteCounters(first: received, second: sent)
    }

    private func isPhysicalNetworkInterface(_ name: String) -> Bool {
        name.hasPrefix("en")
            && !name.hasPrefix("awdl")
            && !name.hasPrefix("llw")
            && !name.hasPrefix("utun")
            && !name.hasPrefix("bridge")
    }

    private func readDiskRate(interval: TimeInterval) -> DiskRateSnapshot {
        let counters = diskCounters()
        defer {
            previousDisk = counters.total
            previousDiskDevices = counters.devices.mapValues { ($0.read, $0.written) }
        }
        guard interval > 0, let previousDisk else { return .empty }
        let devices: [DiskDeviceRate] = counters.devices.map { id, current in
            let previous = previousDiskDevices[id]
            return DiskDeviceRate(
                id: id,
                name: current.name,
                isExternal: current.isExternal,
                readBytesPerSecond: previous.map {
                    rate(current: current.read, previous: $0.read, interval: interval)
                } ?? 0,
                writtenBytesPerSecond: previous.map {
                    rate(current: current.written, previous: $0.written, interval: interval)
                } ?? 0
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DiskRateSnapshot(
            readBytesPerSecond: rate(current: counters.total.first, previous: previousDisk.first, interval: interval),
            writtenBytesPerSecond: rate(current: counters.total.second, previous: previousDisk.second, interval: interval),
            devices: devices
        )
    }

    private func diskCounters() -> DiskCounters {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else {
            return DiskCounters(total: ByteCounters(first: 0, second: 0), devices: [:])
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var written: UInt64 = 0
        var devices: [String: (read: UInt64, written: UInt64, name: String, isExternal: Bool)] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            let deviceRead = (property["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let deviceWritten = (property["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            read &+= deviceRead
            written &+= deviceWritten
            let name = registryString("BSD Name", service: service) ?? "Storage \(service)"
            let location = registryString("Physical Interconnect Location", service: service) ?? "Internal"
            devices[name] = (
                read: deviceRead,
                written: deviceWritten,
                name: name,
                isExternal: location.localizedCaseInsensitiveContains("external")
            )
        }
        return DiskCounters(total: ByteCounters(first: read, second: written), devices: devices)
    }

    private func registryString(_ key: String, service: io_registry_entry_t) -> String? {
        IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) as? String
    }

    private func rate(current: UInt64, previous: UInt64, interval: TimeInterval) -> Double {
        guard current >= previous, interval > 0 else { return 0 }
        return Double(current - previous) / interval
    }
}
