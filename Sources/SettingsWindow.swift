import AppKit
import SwiftUI

/// Trạng thái riêng của cửa sổ. SDK macOS mới biến @State thành macro mà Command Line
/// Tools không kèm plugin, nên trạng thái để trong một ObservableObject.
final class SettingsViewModel: ObservableObject {
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var mounted: [VolumeInfo] = []
    private let volumes: () -> [VolumeInfo]

    init(volumes: @escaping () -> [VolumeInfo]) { self.volumes = volumes }

    func reload() {
        launchAtLogin = LaunchAtLogin.isEnabled
        mounted = volumes()
    }

    func setLaunchAtLogin(_ on: Bool) {
        LaunchAtLogin.set(on)
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

final class SettingsWindowController: NSWindowController {
    private let model: SettingsViewModel

    init(settings: AppSettings, volumes: @escaping () -> [VolumeInfo]) {
        let model = SettingsViewModel(volumes: volumes)
        self.model = model
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateTitle() {
        window?.title = tr("Cài đặt SysMonitor", "SysMonitor Settings")
    }

    func present() {
        model.reload()
        updateTitle()
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // App chỉ nằm trên thanh menu nên macOS có thể từ chối kích hoạt, ví dụ khi mở từ
        // Terminal. Vẫn đưa cửa sổ lên trên cùng để người dùng thấy ngay.
        window?.orderFrontRegardless()
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: SettingsViewModel

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Form {
            Section(tr("Chung", "General")) {
                Picker(tr("Ngôn ngữ", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle(tr("Khởi động cùng máy", "Launch at login"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                Picker(tr("Tốc độ cập nhật", "Update every"), selection: $settings.refreshInterval) {
                    ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { seconds in
                        Text(tr("\(Int(seconds)) giây", "\(Int(seconds)) s")).tag(seconds)
                    }
                }
            }

            Section {
                ForEach(Array(settings.displayOrder.enumerated()), id: \.element) { index, kind in
                    HStack {
                        Toggle(isOn: Binding(get: { settings.enabled.contains(kind) },
                                             set: { settings.setEnabled(kind, $0) })) {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                        .disabled(settings.enabled == [kind])
                        Spacer()
                        MoveButtons(index: index, count: settings.displayOrder.count) {
                            settings.move(kind, by: $0, in: \.displayOrder)
                        }
                    }
                }
            } header: {
                Text(tr("Chỉ số trên thanh menu", "Menu bar items"))
            } footer: {
                Text(tr("Mũi tên đổi thứ tự từ trái sang phải. Luôn giữ ít nhất một chỉ số.",
                        "Arrows change the left-to-right order. At least one item stays on."))
            }

            Section(tr("Cách hiển thị", "Appearance")) {
                Toggle(tr("Hiện biểu tượng", "Show icons"), isOn: $settings.showIcons)
                Picker(tr("Số chữ số thập phân", "Decimal places"), selection: $settings.decimals) {
                    Text("42%").tag(0)
                    Text("42.0%").tag(1)
                }
                .pickerStyle(.segmented)
                Toggle(tr("Tô màu con số khi vượt ngưỡng cảnh báo", "Color the number above the warning level"),
                       isOn: $settings.colorMenuBar)
                Picker(tr("Ổ đĩa trên thanh menu", "Disk in menu bar"), selection: $settings.diskVolumePath) {
                    Text(tr("Ổ khởi động", "Startup disk")).tag("")
                    ForEach(model.mounted.filter { !$0.isRoot }, id: \.path) { Text($0.name).tag($0.path) }
                    if !settings.diskVolumePath.isEmpty,
                       !model.mounted.contains(where: { $0.path == settings.diskVolumePath }) {
                        Text(tr("Ổ đã chọn không còn gắn", "Selected disk is not mounted"))
                            .tag(settings.diskVolumePath)
                    }
                }
            }

            Section {
                Toggle(tr("Tự bớt chỉ số để macOS không ẩn mất", "Drop items myself so macOS doesn't hide them"),
                       isOn: $settings.autoFit)
                ForEach(Array(settings.priority.enumerated()), id: \.element) { index, kind in
                    HStack {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Label(kind.title, systemImage: kind.symbol)
                        Spacer()
                        MoveButtons(index: index, count: settings.priority.count) {
                            settings.move(kind, by: $0, in: \.priority)
                        }
                    }
                    .disabled(!settings.autoFit)
                }
            } header: {
                Text(tr("Khi thanh menu đầy", "When the menu bar is full"))
            } footer: {
                Text(tr("Thiếu chỗ thì bớt từ cuối danh sách lên, chỉ số đầu tiên được giữ tới cùng.",
                        "When space runs out, items are dropped from the bottom up. The first one stays."))
            }

            Section(tr("Bảng chi tiết", "Detail panels")) {
                Picker(tr("Số tiến trình liệt kê", "Processes listed"), selection: $settings.processRows) {
                    ForEach([3, 5, 8], id: \.self) { Text("\($0)").tag($0) }
                }
                Stepper(value: $settings.warningPercent, in: 30 ... (settings.criticalPercent - 5), step: 5) {
                    ThresholdLabel(title: tr("Ngưỡng cảnh báo", "Warning level"),
                                   value: settings.warningPercent, color: .orange)
                }
                Stepper(value: $settings.criticalPercent, in: (settings.warningPercent + 5) ... 95, step: 5) {
                    ThresholdLabel(title: tr("Ngưỡng nguy hiểm", "Critical level"),
                                   value: settings.criticalPercent, color: .red)
                }
            }

            Section(tr("Giới thiệu", "About")) {
                LabeledContent(tr("Phiên bản", "Version"), value: version)
                if let url = URL(string: "https://github.com/vvt911/SysMonitor") {
                    Link(tr("Mã nguồn trên GitHub", "Source code on GitHub"), destination: url)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 700)
    }
}

private struct MoveButtons: View {
    let index: Int
    let count: Int
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
        }
        .buttonStyle(.borderless)
    }
}

private struct ThresholdLabel: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text("\(value)%").monospacedDigit()
        }
    }
}
