import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()

    private var controllers: [MetricController] = []
    private var timer: Timer?
    private(set) var lastStats = Stats()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Chi cho phep mot ban chay, tranh hien trung muc tren thanh menu
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        // NSStatusBar chen muc moi vao ben trai, nen tao nguoc lai
        // de thu tu hien ra la CPU - Bo nho - O dia.
        let disk = DiskController()
        let memory = MemoryController()
        let cpu = CPUController()
        controllers = [cpu, memory, disk]
        controllers.forEach { $0.build() }

        // Mau dau tien chi de lam moc tinh chenh lech
        _ = cpuSampler.sample()
        _ = diskSampler.sample()

        restartTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.tick() }

        // Cho viec kiem tra giao dien: SysMonitor --appearance light|dark
        if let idx = CommandLine.arguments.firstIndex(of: "--appearance"),
           idx + 1 < CommandLine.arguments.count {
            NSApp.appearance = NSAppearance(
                named: CommandLine.arguments[idx + 1] == "light" ? .aqua : .darkAqua)
        }

        // Cho viec kiem tra giao dien: SysMonitor --open cpu|memory|disk
        if let idx = CommandLine.arguments.firstIndex(of: "--open"),
           idx + 1 < CommandLine.arguments.count,
           let kind = MetricKind(rawValue: CommandLine.arguments[idx + 1]),
           let target = controllers.first(where: { $0.kind == kind }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                target.statusItem.button?.performClick(nil)
            }
        }
    }

    func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: Settings.interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common de van chay khi menu dang mo
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let cpuMenuOpen = controllers.first?.isOpen ?? false
        var s = Stats()
        s.cpu = cpuSampler.sample(includeCounts: cpuMenuOpen)
        s.memory = memorySampler.sample()
        s.disk = diskSampler.sample()
        lastStats = s

        var needsProcesses = false
        for c in controllers {
            c.updateStatusItem(s)
            if c.isOpen {
                c.refresh(s)
                if c.wantsProcesses {
                    c.refreshProcesses()
                    needsProcesses = true
                }
            }
        }
        if needsProcesses { ProcessCache.shared.refresh() }
    }
}
