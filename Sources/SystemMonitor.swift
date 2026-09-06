import AppKit
import IOKit
import Darwin

final class SystemMonitor {
    static let bytesPerMemoryGB = 1_073_741_824.0
    static func memoryGB(_ bytes: Double) -> Double { bytes / bytesPerMemoryGB }
    static let chip: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Unavailable" }
        var text = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &text, &size, nil, 0) == 0 else { return "Unavailable" }
        return String(cString: text)
    }()
    let processCPU = ProcessCPUSampler()
    var previous: [UInt32]?
    private var cpuBaseText = "Measuring…"
    static let cpuExplanation = "System-wide busy time across logical CPUs. All percentages use total CPU capacity (100% = all cores). Top process and combined Perch usage refresh every 10 seconds while this menu is open; the first reading takes about one second. Perch includes the menu app, both helpers, their completed utilities, and its eslogger collector. Top compares live user-space processes; kernel_task and processes that exited between samples are not included. Performance and efficiency cores differ."
    var cpuReading: (String, String, String) {
        ("CPU", cpuBaseText + (CPUDisplaySettings.enabled() ? " · " + processCPU.text : ""), Self.cpuExplanation)
    }
    func menuClosed() { previous = nil; processCPU.setActive(false) }
    static func usage(_ old: [UInt32], _ new: [UInt32]) -> Double? {
        guard old.count == 4, new.count == 4 else { return nil }
        let delta = zip(new, old).map { Double($0 &- $1) }
        let total = delta.reduce(0,+)
        return total > 0 ? 100 * (total - delta[Int(CPU_STATE_IDLE)]) / total : nil
    }
    static func pressure(_ value: Int32) -> String {
        switch value { case 1: return "Normal"; case 2: return "Elevated"; case 4: return "Critical"; default: return "Unavailable" }
    }
    func read() -> [(String,String,String)] {
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &cpu) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) } }
        var cpuText = "Measuring…"
        if result == KERN_SUCCESS {
            let now = [cpu.cpu_ticks.0,cpu.cpu_ticks.1,cpu.cpu_ticks.2,cpu.cpu_ticks.3]
            if let old = previous, let value = Self.usage(old,now) { cpuText = String(format:"%.0f%%",value) }
            previous = now
        } else { cpuText = "Unavailable" }
        cpuText = "\(ProcessInfo.processInfo.processorCount) cores · " + cpuText
        let showProcesses = CPUDisplaySettings.enabled()
        processCPU.setActive(showProcesses)
        if showProcesses { processCPU.refresh() }
        cpuBaseText = cpuText
        var gpu = "Unavailable"
        var gpuCores: Int?
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            if service != 0 {
                defer { IOObjectRelease(service) }
                if let cores = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber, cores.intValue > 0 { gpuCores = cores.intValue }
                if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String:Any], let percent = stats["Device Utilization %"] as? NSNumber, (0...100).contains(percent.doubleValue) {
                    gpu = String(format:"%.0f%%",percent.doubleValue)
                    if let allocated = stats["Alloc system memory"] as? NSNumber {
                        gpu += String(format:" · %.1f GiB allocated",Self.memoryGB(allocated.doubleValue))
                    }
                }
            }
        }
        if let cores = gpuCores { gpu = "\(cores) cores · " + gpu }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { p in p.withMemoryRebound(to: integer_t.self, capacity:Int(vmCount)) { host_statistics64(host, HOST_VM_INFO64, $0, &vmCount) } }
        var memory = "Unavailable"
        if vmResult == KERN_SUCCESS {
            let pages = Double(vm.active_count) + Double(vm.inactive_count) + Double(vm.wire_count) + Double(vm.compressor_page_count) - Double(vm.purgeable_count) - Double(vm.external_page_count)
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            let used = min(total,max(0,pages * Double(vm_kernel_page_size)))
            memory = String(format:"%.1f / %.1f GiB · %.0f%%",Self.memoryGB(used),Self.memoryGB(total),used/total*100)
        }
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let pressureResult = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0)
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm · OK · Keep ventilated"
        case .serious: thermal = "High · Reduce heavy work"
        case .critical: thermal = "Critical · Let Mac cool"
        @unknown default: thermal = "Unavailable"
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let hardware = Self.chip + " · " + os
        return [("Mac", hardware, "Installed processor and macOS version. Total RAM is shown on the Memory line."),
                cpuReading,
                ("GPU",gpu,"Driver-reported utilization and allocations, not exclusive resident RAM. Do not add GPU allocations to system memory. CPU/GPU overlap is unavailable."),
                ("Memory",memory + " · " + (pressureResult == 0 && [1,2,4].contains(pressure) ? Self.pressure(pressure) + " pressure" : "Pressure unavailable"),"Estimated physical memory used, including compressed memory and excluding file cache and purgeable pages. GiB uses 1,073,741,824 bytes, matching installed RAM. Pressure is macOS’s assessment of memory demand, not bandwidth or percentage full."),
                ("Thermal",thermal,"macOS thermal pressure. Critical does not predict imminent hardware damage. A reliably identified temperature sensor is unavailable. Never put an awake Mac in a bag.")]
    }
}
func runSystemTests() throws {
    guard SystemMonitor.memoryGB(137_438_953_472) == 128,
          SystemMonitor.usage([0,0,0,0],[25,0,75,0]) == 25,
          SystemMonitor.usage([1,1,1,1],[1,1,1,1]) == nil,
          SystemMonitor.pressure(4) == "Critical", SystemMonitor.pressure(99) == "Unavailable" else { throw AppError(message:"System metric conversion failed") }
    print("PASS: CPU interval calculation, empty interval, pressure mapping and unsupported values")
}
