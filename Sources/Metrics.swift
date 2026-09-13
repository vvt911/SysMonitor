import Foundation
import IOKit

// MARK: - Đọc sysctl

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

func sysctlInt(_ name: String) -> Int64? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    if size == 8 {
        var v: Int64 = 0
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return v
    }
    if size == 4 {
        var v: Int32 = 0
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int64(v)
    }
    return nil
}

// MARK: - Thông tin máy, đọc một lần

struct MachineInfo {
    let cpuBrand: String
    let physicalCores: Int
    let logicalCores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let totalMemory: UInt64
    let pageSize: UInt64
    let hostName: String
    let osVersion: String

    static let shared = MachineInfo()

    private init() {
        cpuBrand = sysctlString("machdep.cpu.brand_string") ?? "CPU"
        physicalCores = Int(sysctlInt("hw.physicalcpu") ?? 0)
        logicalCores = Int(sysctlInt("hw.logicalcpu") ?? 1)
        performanceCores = Int(sysctlInt("hw.perflevel0.logicalcpu") ?? 0)
        efficiencyCores = Int(sysctlInt("hw.perflevel1.logicalcpu") ?? 0)
        totalMemory = UInt64(sysctlInt("hw.memsize") ?? 0)
        pageSize = UInt64(sysctlInt("hw.pagesize") ?? 4096)
        hostName = ProcessInfo.processInfo.hostName
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var bootDate: Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec))
    }
}

// MARK: - CPU

struct CPUSample {
    var usage: Double = 0          // 0...1, toàn máy
    var user: Double = 0
    var system: Double = 0
    var nice: Double = 0
    var idle: Double = 1
    var cores: [Double] = []       // 0...1 cho từng nhân logic
    var loadAverage: (Double, Double, Double) = (0, 0, 0)
    var processCount: Int = 0
    var threadCount: Int = 0
}

final class CPUSampler {
    private var previous: [UInt32] = []
    private var previousCount = 0

    func sample(includeCounts: Bool = false) -> CPUSample {
        var out = CPUSample()

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else {
            out.loadAverage = Self.loadAvg()
            return out
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        let n = Int(cpuCount)
        var ticks = [UInt32](repeating: 0, count: n * states)
        info.withMemoryRebound(to: UInt32.self, capacity: n * states) { p in
            for i in 0 ..< (n * states) { ticks[i] = p[i] }
        }

        guard previousCount == n, previous.count == ticks.count else {
            previous = ticks
            previousCount = n
            out.loadAverage = Self.loadAvg()
            out.cores = [Double](repeating: 0, count: n)
            if includeCounts { (out.processCount, out.threadCount) = Self.taskCounts() }
            return out
        }

        var sumUser = 0.0, sumSys = 0.0, sumNice = 0.0, sumIdle = 0.0
        out.cores.reserveCapacity(n)

        for c in 0 ..< n {
            let base = c * states
            func delta(_ s: Int32) -> Double {
                let i = base + Int(s)
                return Double(ticks[i] &- previous[i])
            }
            let user = delta(CPU_STATE_USER)
            let sys = delta(CPU_STATE_SYSTEM)
            let nice = delta(CPU_STATE_NICE)
            let idle = delta(CPU_STATE_IDLE)
            let total = user + sys + nice + idle
            out.cores.append(total > 0 ? min(1, (user + sys + nice) / total) : 0)
            sumUser += user; sumSys += sys; sumNice += nice; sumIdle += idle
        }

        previous = ticks
        let total = sumUser + sumSys + sumNice + sumIdle
        if total > 0 {
            out.user = sumUser / total
            out.system = sumSys / total
            out.nice = sumNice / total
            out.idle = sumIdle / total
            out.usage = min(1, (sumUser + sumSys + sumNice) / total)
        }
        out.loadAverage = Self.loadAvg()
        if includeCounts { (out.processCount, out.threadCount) = Self.taskCounts() }
        return out
    }

    private static func loadAvg() -> (Double, Double, Double) {
        var l = [Double](repeating: 0, count: 3)
        guard getloadavg(&l, 3) == 3 else { return (0, 0, 0) }
        return (l[0], l[1], l[2])
    }

    static func taskCounts() -> (processes: Int, threads: Int) {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return (0, 0) }
        let capacity = Int(bufferSize) / MemoryLayout<pid_t>.size + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids,
                                    Int32(capacity * MemoryLayout<pid_t>.size))
        guard written > 0 else { return (0, 0) }
        let count = Int(written) / MemoryLayout<pid_t>.size

        var processes = 0
        var threads = 0
        for i in 0 ..< count where pids[i] > 0 {
            processes += 1
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &info, size) == size {
                threads += Int(info.pti_threadnum)
            }
        }
        return (processes, threads)
    }
}

// MARK: - Bộ nhớ

struct MemorySample {
    var total: UInt64 = 0
    var used: UInt64 = 0            // ứng dụng + hệ thống giữ + đã nén, như Activity Monitor
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cachedFiles: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressureLevel: Int = 1      // 1 bình thường, 2 cảnh báo, 4 nguy hiểm
    var pageIns: UInt64 = 0
    var pageOuts: UInt64 = 0

    var percent: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var pressureText: String {
        switch pressureLevel {
        case 4: return "Nguy hiểm"
        case 2: return "Cảnh báo"
        default: return "Bình thường"
        }
    }
}

final class MemorySampler {
    func sample() -> MemorySample {
        var out = MemorySample()
        out.total = MachineInfo.shared.totalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return out }

        let pg = MachineInfo.shared.pageSize
        func bytes<T: BinaryInteger>(_ pages: T) -> UInt64 { UInt64(pages) * pg }

        let purgeable = bytes(stats.purgeable_count)
        let internalPages = bytes(stats.internal_page_count)
        let externalPages = bytes(stats.external_page_count)

        out.wired = bytes(stats.wire_count)
        out.compressed = bytes(stats.compressor_page_count)
        out.app = internalPages > purgeable ? internalPages - purgeable : internalPages
        out.cachedFiles = externalPages + purgeable
        out.free = bytes(stats.free_count) + bytes(stats.speculative_count)
        out.used = out.app + out.wired + out.compressed
        if out.used > out.total { out.used = out.total }
        out.pageIns = bytes(stats.pageins)
        out.pageOuts = bytes(stats.pageouts)

        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 {
            out.swapUsed = xsw.xsu_used
            out.swapTotal = xsw.xsu_total
        }
        out.pressureLevel = Int(sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1)
        return out
    }
}

// MARK: - Ổ đĩa

struct VolumeInfo {
    var name: String
    var path: String
    var total: UInt64
    var available: UInt64       // phần dùng được cho việc quan trọng, như Finder
    var rawFree: UInt64         // trống thô theo hệ thống tập tin
    var isRoot: Bool
    var isInternal: Bool
    var fsType: String

    var used: UInt64 { total > available ? total - available : 0 }
    var percent: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskSample {
    var volumes: [VolumeInfo] = []
    var readBytes: UInt64 = 0
    var writeBytes: UInt64 = 0
    var readRate: Double = 0     // byte mỗi giây
    var writeRate: Double = 0

    var root: VolumeInfo? { volumes.first(where: { $0.isRoot }) ?? volumes.first }
    var percent: Double { root?.percent ?? 0 }
}

final class DiskSampler {
    private var lastRead: UInt64 = 0
    private var lastWrite: UInt64 = 0
    private var lastTime: CFAbsoluteTime = 0
    private var cachedVolumes: [VolumeInfo] = []
    private var lastVolumeScan: CFAbsoluteTime = 0

    func sample() -> DiskSample {
        var out = DiskSample()
        let now = CFAbsoluteTimeGetCurrent()

        if now - lastVolumeScan > 5 || cachedVolumes.isEmpty {
            cachedVolumes = Self.scanVolumes()
            lastVolumeScan = now
        }
        out.volumes = cachedVolumes

        let io = Self.blockStorageBytes()
        out.readBytes = io.read
        out.writeBytes = io.write
        if lastTime > 0, now > lastTime {
            let dt = now - lastTime
            out.readRate = Double(io.read &- lastRead) / dt
            out.writeRate = Double(io.write &- lastWrite) / dt
        }
        lastRead = io.read
        lastWrite = io.write
        lastTime = now
        return out
    }

    private static func scanVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            .volumeIsBrowsableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }

        var result: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable ?? false,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let important = UInt64(v.volumeAvailableCapacityForImportantUsage ?? 0)
            let raw = UInt64(v.volumeAvailableCapacity ?? 0)
            var fsType = ""
            var st = statfs()
            if statfs(url.path, &st) == 0 {
                fsType = withUnsafeBytes(of: st.f_fstypename) { raw in
                    String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
                }.uppercased()
            }
            result.append(VolumeInfo(
                name: v.volumeName ?? url.lastPathComponent,
                path: url.path,
                total: UInt64(total),
                available: important > 0 ? important : raw,
                rawFree: raw,
                isRoot: v.volumeIsRootFileSystem ?? (url.path == "/"),
                isInternal: v.volumeIsInternal ?? true,
                fsType: fsType))
        }
        result.sort { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return result
    }

    private static func blockStorageBytes() -> (read: UInt64, write: UInt64) {
        var read: UInt64 = 0
        var write: UInt64 = 0
        var iter: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOBlockStorageDriver"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        return (read, write)
    }
}

// MARK: - Tiến trình

struct ProcInfo {
    var pid: Int
    var cpu: Double      // phần trăm trên một nhân
    var rss: UInt64      // byte
    var name: String
}

enum ProcSort { case cpu, memory }

enum ProcessLister {
    /// Một lần gọi ps duy nhất, trả về toàn bộ tiến trình, mất khoảng 20 ms.
    static func snapshot() -> [ProcInfo] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid,pcpu,rss,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcInfo] = []
        result.reserveCapacity(600)
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = UInt64(parts[2]) else { continue }
            result.append(ProcInfo(pid: pid, cpu: cpu,
                                   rss: rss * 1024,
                                   name: parts[3...].joined(separator: " ")))
        }
        return result
    }
}

/// Giữ kết quả ps gần nhất để menu mở ra là có số liệu ngay.
///
/// Khi menu đang mở, macOS không chạy các khối DispatchQueue.main.async nhưng
/// Timer ở chế độ .common thì vẫn chạy. Nên luồng nền chỉ ghi kết quả vào đây
/// qua khoá, còn giao diện đọc lại theo nhịp Timer thay vì chờ callback.
final class ProcessCache {
    static let shared = ProcessCache()
    private init() {}

    private let lock = NSLock()
    private var _byCPU: [ProcInfo] = []
    private var _byMemory: [ProcInfo] = []
    private var fetching = false
    private var lastFetch: CFAbsoluteTime = 0
    private let keep = 5

    var byCPU: [ProcInfo] { lock.lock(); defer { lock.unlock() }; return _byCPU }
    var byMemory: [ProcInfo] { lock.lock(); defer { lock.unlock() }; return _byMemory }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return _byCPU.isEmpty }

    private func store(_ all: [ProcInfo]) {
        let cpu = Array(all.sorted { $0.cpu > $1.cpu }.prefix(keep))
        let mem = Array(all.sorted { $0.rss > $1.rss }.prefix(keep))
        lock.lock()
        _byCPU = cpu
        _byMemory = mem
        lastFetch = CFAbsoluteTimeGetCurrent()
        fetching = false
        lock.unlock()
    }

    /// Lấy ngay trên luồng hiện tại, chỉ dùng cho lần mở menu đầu tiên.
    func refreshNow() { store(ProcessLister.snapshot()) }

    func refresh(minimumInterval: Double = 1.5) {
        lock.lock()
        let stale = !fetching && CFAbsoluteTimeGetCurrent() - lastFetch > minimumInterval
        if stale { fetching = true }
        lock.unlock()
        guard stale else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.store(ProcessLister.snapshot())
        }
    }
}
