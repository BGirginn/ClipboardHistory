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
        var devices: [String: (read: UInt64, written: UInt64, name: String, isExternal: Bool)]
    }

    private let temperatureProvider: any TemperatureSensorProviding
    private var previousCPU: CPUTicks?
    private var previousNetwork: [String: ByteCounters]?
    private var previousDiskDevices: [String: (read: UInt64, written: UInt64)]?
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
        previousDiskDevices = nil
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
        guard current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice else { return .empty }
        let user = current.user - previous.user
        let system = current.system - previous.system
        let idle = current.idle - previous.idle
        let nice = current.nice - previous.nice
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
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS,
              hostPageSize > 0 else { return .empty }
        let pageSize = UInt64(hostPageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let active = UInt64(statistics.active_count) * pageSize
        let inactive = UInt64(statistics.inactive_count) * pageSize
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let cached = UInt64(statistics.external_page_count) * pageSize
        let free = UInt64(statistics.free_count + statistics.speculative_count) * pageSize
        let internalBytes = UInt64(statistics.internal_page_count) * pageSize
        let purgeable = UInt64(statistics.purgeable_count) * pageSize
        let application = internalBytes >= purgeable ? internalBytes - purgeable : 0
        let used = Self.usedMemoryBytes(
            total: total,
            internalBytes: internalBytes,
            purgeableBytes: purgeable,
            wiredBytes: wired,
            compressedBytes: compressed
        )
        return MemoryUsageSnapshot(
            totalBytes: total,
            usedBytes: used,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free,
            applicationBytes: application,
            purgeableBytes: purgeable,
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
            receivedBytesPerSecond: aggregateNetworkRate(
                current: counters,
                previous: previousNetwork,
                interval: interval,
                keyPath: \.first
            ),
            sentBytesPerSecond: aggregateNetworkRate(
                current: counters,
                previous: previousNetwork,
                interval: interval,
                keyPath: \.second
            ),
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

    private func networkCounters(interfaceName: String?) -> [String: ByteCounters] {
        Dictionary(uniqueKeysWithValues: CHNetworkInterfaceCounters().compactMap { name, values in
            guard (interfaceName == nil || name == interfaceName),
                  (interfaceName != nil || isPhysicalNetworkInterface(name)),
                  let received = values["received"]?.uint64Value,
                  let sent = values["sent"]?.uint64Value else { return nil }
            return (name, ByteCounters(first: received, second: sent))
        })
    }

    private func aggregateNetworkRate(
        current: [String: ByteCounters],
        previous: [String: ByteCounters],
        interval: TimeInterval,
        keyPath: KeyPath<ByteCounters, UInt64>
    ) -> Double {
        current.reduce(into: 0) { total, entry in
            guard let old = previous[entry.key] else { return }
            total += Self.rate(
                current: entry.value[keyPath: keyPath],
                previous: old[keyPath: keyPath],
                interval: interval
            )
        }
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
        let previousDevices = previousDiskDevices
        defer {
            previousDiskDevices = counters.devices.mapValues { ($0.read, $0.written) }
        }
        let devices: [DiskDeviceRate] = counters.devices.map { id, current in
            let previous = previousDevices?[id]
            let readRate = previous.map {
                Self.rate(current: current.read, previous: $0.read, interval: interval)
            } ?? 0
            let writeRate = previous.map {
                Self.rate(current: current.written, previous: $0.written, interval: interval)
            } ?? 0
            return DiskDeviceRate(
                id: id,
                name: current.name,
                isExternal: current.isExternal,
                readBytesPerSecond: readRate,
                writtenBytesPerSecond: writeRate
            )
        }.sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame
                ? $0.id < $1.id
                : nameOrder == .orderedAscending
        }
        return DiskRateSnapshot(
            readBytesPerSecond: devices.reduce(0) { $0 + $1.readBytesPerSecond },
            writtenBytesPerSecond: devices.reduce(0) { $0 + $1.writtenBytesPerSecond },
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
            return DiskCounters(devices: [:])
        }
        defer { IOObjectRelease(iterator) }
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
            guard let name = registryString("BSD Name", service: service),
                  !name.isEmpty,
                  let identifier = registryIdentifier(service: service) else { continue }
            let interconnect = registryString("Physical Interconnect", service: service) ?? ""
            guard !interconnect.localizedCaseInsensitiveContains("virtual") else { continue }
            let location = registryString("Physical Interconnect Location", service: service) ?? "Internal"
            devices[identifier] = (
                read: deviceRead,
                written: deviceWritten,
                name: name,
                isExternal: location.localizedCaseInsensitiveContains("external")
            )
        }
        return DiskCounters(devices: devices)
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

    private func registryIdentifier(service: io_registry_entry_t) -> String? {
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS else {
            return nil
        }
        return String(identifier)
    }

    nonisolated static func rate(
        current: UInt64,
        previous: UInt64,
        interval: TimeInterval
    ) -> Double {
        guard current >= previous, interval > 0 else { return 0 }
        return Double(current - previous) / interval
    }

    nonisolated static func usedMemoryBytes(
        total: UInt64,
        internalBytes: UInt64,
        purgeableBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64
    ) -> UInt64 {
        let application = internalBytes >= purgeableBytes
            ? internalBytes - purgeableBytes
            : 0
        let (applicationAndWired, firstOverflow) = application.addingReportingOverflow(wiredBytes)
        let (calculated, secondOverflow) = applicationAndWired.addingReportingOverflow(compressedBytes)
        guard !firstOverflow, !secondOverflow else { return total }
        return min(total, calculated)
    }
}
