// DShMenu — DeepSeek Harness 菜单栏控制器
// 左键点击图标 = 在浏览器打开 dsh Web UI；右键 = 控制菜单

import AppKit
import Foundation
import Darwin

private let prefersChinese = Locale.preferredLanguages.first?
    .lowercased().hasPrefix("zh") ?? false

func tr(_ chinese: String, _ english: String) -> String {
    prefersChinese ? chinese : english
}

// MARK: - 路径与日志

let label = "com.zjr.dsh-web"
let uid = getuid()
let launchdDomain = "gui/\(uid)"
let launchdTarget = "\(launchdDomain)/\(label)"
let homeURL = FileManager.default.homeDirectoryForCurrentUser
let defaultDshHomeURL = homeURL.appendingPathComponent(".dsh", isDirectory: true)
let dshHomeURL: URL = {
    guard let configured = ProcessInfo.processInfo.environment["DSH_HOME"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !configured.isEmpty else {
        return defaultDshHomeURL
    }
    let expanded = (configured as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
}()
let logsURL = dshHomeURL.appendingPathComponent("logs", isDirectory: true)
let configURL = dshHomeURL.appendingPathComponent("DShMenu.config.plist")
// 单实例锁有意固定在默认目录；否则不同 DSH_HOME 的启动入口会各自持有一把锁。
let lockDirectoryURL = defaultDshHomeURL
let lockPath = lockDirectoryURL.appendingPathComponent("DShMenu.lock").path
let controllerLogPath = logsURL.appendingPathComponent("DShMenu.log").path
let outLogPath = logsURL.appendingPathComponent("dsh-web.out.log").path
let errLogPath = logsURL.appendingPathComponent("dsh-web.err.log").path
let plistPath = homeURL
    .appendingPathComponent("Library/LaunchAgents/com.zjr.dsh-web.plist").path

private let logLock = NSLock()

func writeControllerLog(_ message: String) {
    logLock.lock()
    defer { logLock.unlock() }

    let formatter = ISO8601DateFormatter()
    let line = "\(formatter.string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    do {
        try FileManager.default.createDirectory(
            at: logsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        if !FileManager.default.fileExists(atPath: controllerLogPath) {
            guard FileManager.default.createFile(atPath: controllerLogPath, contents: nil) else {
                return
            }
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: controllerLogPath))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    } catch {
        // 日志本身不可写时不能递归记录；保留 stderr 作为最后诊断渠道。
        fputs("DShMenu logging failed: \(error)\n", stderr)
    }
}

// MARK: - 配置

func loadConfiguredPort() -> Int {
    let defaultPort = 3080
    guard FileManager.default.fileExists(atPath: configURL.path) else {
        return defaultPort
    }

    do {
        let data = try Data(contentsOf: configURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any], let value = dictionary["Port"] else {
            writeControllerLog("配置缺少整数键 Port，使用默认端口 \(defaultPort)：\(configURL.path)")
            return defaultPort
        }

        // PropertyListSerialization 会把整数桥接为 NSNumber；显式排除同样桥接为 NSNumber 的 Bool。
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              Double(number.intValue) == number.doubleValue,
              (1...65535).contains(number.intValue) else {
            writeControllerLog("配置 Port 不是 1...65535 范围内的整数，使用默认端口 \(defaultPort)：\(value)")
            return defaultPort
        }
        return number.intValue
    } catch {
        writeControllerLog("读取配置失败，使用默认端口 \(defaultPort)：\(error)")
        return defaultPort
    }
}

let port = loadConfiguredPort()
let baseURL = URL(string: "http://127.0.0.1:\(port)")!
let healthURL = baseURL.appendingPathComponent("manifest.webmanifest")

// MARK: - 命令与 launchd 状态

struct CommandResult: Sendable {
    let executable: String
    let arguments: [String]
    let code: Int32
    let output: String
    let launchError: String?

    var command: String {
        ([executable] + arguments).joined(separator: " ")
    }

    var succeeded: Bool { code == 0 && launchError == nil }

    var diagnostic: String {
        var parts = [tr("命令：\(command)", "Command: \(command)"), tr("退出码：\(code)", "Exit code: \(code)")]
        if let launchError = launchError {
            parts.append(tr("启动错误：\(launchError)", "Launch error: \(launchError)"))
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(tr("输出：\n\(trimmed)", "Output:\n\(trimmed)")) }
        return parts.joined(separator: "\n")
    }
}

@discardableResult
func exec(_ executable: String, _ args: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        return CommandResult(
            executable: executable,
            arguments: args,
            code: -1,
            output: "",
            launchError: error.localizedDescription
        )
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(
        executable: executable,
        arguments: args,
        code: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? "",
        launchError: nil
    )
}

struct ServiceActionError: LocalizedError {
    let summary: String
    let details: String

    var errorDescription: String? { summary }
}

func requireSuccess(_ result: CommandResult, _ summary: String) throws {
    guard result.succeeded else {
        throw ServiceActionError(summary: summary, details: result.diagnostic)
    }
}

enum LaunchPreference: String, Sendable {
    case enabled
    case disabled
    case unknown
}

struct ServiceState: Sendable {
    let loaded: Bool
    let running: Bool
    let preference: LaunchPreference
    let preferenceDiagnostic: String?
}

func parseLaunchPreference(_ output: String) -> LaunchPreference? {
    let quotedLabel = "\"\(label)\""
    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(quotedLabel), let arrow = trimmed.range(of: "=>") else { continue }
        let value = trimmed[arrow.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;\t").union(.whitespacesAndNewlines))
            .lowercased()
        if value == "true" || value == "disabled" { return .disabled }
        if value == "false" || value == "enabled" { return .enabled }
        return .unknown
    }
    // print-disabled 只列出 override；命令成功且没有本 label 即采用 launchd 默认 enabled。
    return .enabled
}

func serviceState() -> ServiceState {
    let printResult = exec("/bin/launchctl", ["print", launchdTarget])
    let loaded = printResult.succeeded
    let running = loaded && printResult.output.components(separatedBy: .newlines).contains {
        $0.trimmingCharacters(in: .whitespaces) == "state = running"
    }

    let disabledResult = exec("/bin/launchctl", ["print-disabled", launchdDomain])
    guard disabledResult.succeeded, let preference = parseLaunchPreference(disabledResult.output) else {
        return ServiceState(
            loaded: loaded,
            running: running,
            preference: .unknown,
            preferenceDiagnostic: disabledResult.diagnostic
        )
    }
    return ServiceState(loaded: loaded, running: running, preference: preference, preferenceDiagnostic: nil)
}

// MARK: - 健康检查

enum HealthResult: Sendable {
    case noResponse(String?)
    case dsh
    case otherHTTP(status: Int, description: String)
}

private final class HealthResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: HealthResult = .noResponse(tr("请求超时", "Request timed out"))

    func set(_ newValue: HealthResult) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> HealthResult {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

func checkHealth() -> HealthResult {
    let semaphore = DispatchSemaphore(value: 0)
    let box = HealthResultBox()
    var request = URLRequest(url: healthURL, timeoutInterval: 1.5)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData

    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error = error {
            box.set(.noResponse(error.localizedDescription))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            box.set(.noResponse(tr("没有 HTTP 响应", "No HTTP response")))
            return
        }
        guard http.statusCode == 200 else {
            box.set(.otherHTTP(
                status: http.statusCode,
                description: tr("manifest 返回 HTTP \(http.statusCode)", "manifest returned HTTP \(http.statusCode)")
            ))
            return
        }
        guard let data = data else {
            box.set(.otherHTTP(status: 200, description: tr("manifest 响应为空", "Empty manifest response")))
            return
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                box.set(.otherHTTP(status: 200, description: tr("manifest 不是 JSON 对象", "Manifest is not a JSON object")))
                return
            }
            let name = object["name"] as? String
            let shortName = object["short_name"] as? String
            if name == "DeepSeek Harness" || shortName == "DSH" {
                box.set(.dsh)
            } else {
                box.set(.otherHTTP(status: 200, description: tr("manifest 身份不匹配", "Manifest identity mismatch")))
            }
        } catch {
            box.set(.otherHTTP(status: 200, description: tr("manifest JSON 无法解析", "Manifest JSON could not be parsed")))
        }
    }.resume()

    if semaphore.wait(timeout: .now() + 2.0) == .timedOut {
        return .noResponse(tr("请求超时", "Request timed out"))
    }
    return box.get()
}

// MARK: - 服务控制

func startService() throws {
    let state = serviceState()
    if !state.loaded {
        switch state.preference {
        case .disabled:
            try requireSuccess(
                exec("/bin/launchctl", ["enable", launchdTarget]),
                tr("无法临时启用服务以完成加载", "Could not temporarily enable the service for loading")
            )

            var bootstrapError: Error?
            var restoreResult: CommandResult?
            do {
                defer {
                    restoreResult = exec("/bin/launchctl", ["disable", launchdTarget])
                }
                do {
                    try requireSuccess(
                        exec("/bin/launchctl", ["bootstrap", launchdDomain, plistPath]),
                        tr("无法加载 Web 服务", "Could not load the Web service")
                    )
                } catch {
                    bootstrapError = error
                }
            }

            if let restoreResult = restoreResult, !restoreResult.succeeded {
                let original = bootstrapError.map {
                    tr("\n原始错误：\($0.localizedDescription)", "\nOriginal error: \($0.localizedDescription)")
                } ?? ""
                throw ServiceActionError(
                    summary: tr("无法恢复“关闭自启”偏好", "Could not restore the disabled login-start preference"),
                    details: restoreResult.diagnostic + original
                )
            }
            if let bootstrapError = bootstrapError { throw bootstrapError }

        case .enabled:
            try requireSuccess(
                exec("/bin/launchctl", ["bootstrap", launchdDomain, plistPath]),
                tr("无法加载 Web 服务", "Could not load the Web service")
            )

        case .unknown:
            let diagnostic = state.preferenceDiagnostic ?? tr(
                "launchctl 未返回可识别的自启状态",
                "launchctl did not return a recognizable login-start state"
            )
            throw ServiceActionError(
                summary: tr("无法确认自启偏好，已取消启动", "Could not verify the login-start preference; start was cancelled"),
                details: diagnostic
            )
        }
    }

    try requireSuccess(
        exec("/bin/launchctl", ["kickstart", "-k", launchdTarget]),
        tr("无法启动 Web 服务", "Could not start the Web service")
    )
}

func stopService() throws {
    try requireSuccess(
        exec("/bin/launchctl", ["kill", "SIGTERM", launchdTarget]),
        tr("无法停止 Web 服务", "Could not stop the Web service")
    )
}

func toggleLaunchAtLogin() throws {
    let state = serviceState()
    let arguments: [String]
    let summary: String
    switch state.preference {
    case .enabled:
        arguments = ["disable", launchdTarget]
        summary = tr("无法关闭登录自启", "Could not disable start at login")
    case .disabled:
        arguments = ["enable", launchdTarget]
        summary = tr("无法开启登录自启", "Could not enable start at login")
    case .unknown:
        throw ServiceActionError(
            summary: tr("无法确认当前自启状态，未执行更改", "Could not verify the login-start state; nothing was changed"),
            details: state.preferenceDiagnostic ?? tr(
                "launchctl 未返回可识别的自启状态",
                "launchctl did not return a recognizable login-start state"
            )
        )
    }
    try requireSuccess(exec("/bin/launchctl", arguments), summary)
}

// MARK: - 单实例锁

func acquireSingletonLock() -> Bool {
    do {
        try FileManager.default.createDirectory(
            at: lockDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    } catch {
        writeControllerLog("无法创建固定锁目录 \(lockDirectoryURL.path)，单实例锁失败：\(error)")
        return false
    }

    let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else {
        writeControllerLog("无法打开单实例锁 \(lockPath)：errno=\(errno) \(String(cString: strerror(errno)))")
        return false
    }
    guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
        writeControllerLog("无法为单实例锁设置 FD_CLOEXEC：errno=\(errno) \(String(cString: strerror(errno)))")
        close(fd)
        return false
    }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        writeControllerLog("另一个 DShMenu 实例已持有单实例锁，本实例退出")
        close(fd)
        return false
    }
    // fd 故意保持打开；FD_CLOEXEC 防止子进程继承，进程退出时内核自动释放 flock。
    return true
}

// MARK: - 日志窗口

func tailText(atPath path: String, maximumBytes: UInt64 = 256 * 1024) -> String {
    guard FileManager.default.fileExists(atPath: path) else {
        return tr("（文件不存在）", "(File does not exist)")
    }
    do {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        try handle.seek(toOffset: length > maximumBytes ? length - maximumBytes : 0)
        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    } catch {
        return tr("（读取失败：\(error.localizedDescription)）", "(Read failed: \(error.localizedDescription))")
    }
}

@MainActor
final class LogWindowController: NSWindowController {
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = tr("DShMenu 日志", "DShMenu Logs")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        scrollView.documentView = textView

        let refreshButton = NSButton(title: tr("刷新", "Refresh"), target: self, action: #selector(refreshLogs))
        let openFolderButton = NSButton(
            title: tr("打开日志目录", "Open Logs Folder"),
            target: self,
            action: #selector(openLogsFolder)
        )
        let buttonStack = NSStackView(views: [refreshButton, openFolderButton, statusLabel])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 10

        content.addSubview(scrollView)
        content.addSubview(buttonStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -10),
            buttonStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            buttonStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    func present() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshLogs()
    }

    @objc private func refreshLogs() {
        statusLabel.stringValue = tr("正在读取…", "Reading…")
        let sections = [
            ("dsh-web.err.log", errLogPath),
            ("dsh-web.out.log", outLogPath),
            ("DShMenu.log", controllerLogPath)
        ]
        // 每个文件最多读取 256 KiB，保持同步实现可避免跨线程触碰 AppKit 对象。
        let text = sections.map { name, path in
            tr(
                "========== \(name)（尾部最多 256 KiB）==========\n\(tailText(atPath: path))",
                "========== \(name) (last 256 KiB maximum) ==========\n\(tailText(atPath: path))"
            )
        }.joined(separator: "\n\n")
        textView.string = text
        textView.scrollToEndOfDocument(nil)
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        statusLabel.stringValue = tr("更新于 \(time)", "Updated at \(time)")
    }

    @objc private func openLogsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: logsURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            NSWorkspace.shared.open(logsURL)
        } catch {
            writeControllerLog("无法打开日志目录：\(error)")
        }
    }
}

// MARK: - 菜单栏状态图标

@MainActor
func statusImage(color: NSColor) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    let path = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10))
    color.setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.25).setStroke()
    path.lineWidth = 1
    path.stroke()
    image.unlockFocus()
    return image
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var statusMenuItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var refreshInFlight = false
    private var cachedServiceState: ServiceState?
    private var serviceStateCheckedAt = Date.distantPast
    private let serviceStateCacheInterval: TimeInterval = 7.0
    private var logWindowController: LogWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let button = statusItem.button else { return }
        button.image = statusImage(color: .systemGray)
        button.action = #selector(iconClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = tr("DeepSeek Harness — 端口 \(port)", "DeepSeek Harness — Port \(port)")

        buildMenu()
        refresh(forceServiceState: true)
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func buildMenu() {
        statusMenuItem = NSMenuItem(
            title: tr("状态：检测中…", "Status: Checking…"),
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: tr("打开 dsh Web UI", "Open dsh Web UI"),
            action: #selector(openWebUI),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        for item in [
            NSMenuItem(title: tr("启动服务", "Start Service"), action: #selector(startClicked), keyEquivalent: ""),
            NSMenuItem(title: tr("停止服务", "Stop Service"), action: #selector(stopClicked), keyEquivalent: ""),
            NSMenuItem(title: tr("重启服务", "Restart Service"), action: #selector(restartClicked), keyEquivalent: "")
        ] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let logItem = NSMenuItem(title: tr("查看日志", "View Logs"), action: #selector(logClicked), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        launchAtLoginItem = NSMenuItem(
            title: tr("登录自启", "Start at Login"),
            action: #selector(toggleLaunchAtLoginClicked),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: tr("退出菜单栏（保留服务）", "Quit Menu Bar (Keep Service Running)"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        let quitAllItem = NSMenuItem(
            title: tr("停止服务并退出", "Stop Service and Quit"),
            action: #selector(stopAndQuit),
            keyEquivalent: ""
        )
        quitAllItem.target = self
        menu.addItem(quitAllItem)
    }

    // MARK: 状态刷新

    @objc private func refreshTimerFired() {
        refresh()
    }

    func refresh(forceServiceState: Bool = false) {
        guard !refreshInFlight else { return }
        refreshInFlight = true

        let cached = cachedServiceState
        let shouldQueryService = forceServiceState || cached == nil ||
            Date().timeIntervalSince(serviceStateCheckedAt) >= serviceStateCacheInterval

        DispatchQueue.global(qos: .utility).async { [self] in
            let health = checkHealth()
            let state = shouldQueryService ? serviceState() : cached!
            DispatchQueue.main.async {
                if shouldQueryService {
                    self.cachedServiceState = state
                    self.serviceStateCheckedAt = Date()
                }
                self.applyStatus(health: health, state: state)
                self.refreshInFlight = false
            }
        }
    }

    private func applyStatus(health: HealthResult, state: ServiceState) {
        let text: String
        let color: NSColor

        switch health {
        case .dsh where state.running:
            text = tr("● 运行中  http://127.0.0.1:\(port)", "● Running  http://127.0.0.1:\(port)")
            color = .systemGreen
        case .dsh:
            text = tr("⚠ 检测到外部 DSh 实例（非 launchd 运行）", "⚠ External DSh instance detected (not managed by launchd)")
            color = .systemOrange
        case .otherHTTP(_, let description):
            text = tr(
                "✕ 端口 \(port) 被其他 HTTP 服务占用：\(description)",
                "✕ Port \(port) is occupied by another HTTP service: \(description)"
            )
            color = .systemRed
        case .noResponse where state.running:
            text = tr("◌ launchd 服务运行中，但 DSh 尚未就绪", "◌ launchd service is running; DSh is not ready")
            color = .systemYellow
        case .noResponse where state.loaded:
            text = tr("○ 已停止（服务已加载）", "○ Stopped (service loaded)")
            color = .systemGray
        case .noResponse:
            text = FileManager.default.fileExists(atPath: plistPath)
                ? tr("○ 服务未加载", "○ Service not loaded")
                : tr("○ 未安装服务", "○ Service not installed")
            color = .systemGray
        }

        statusMenuItem.title = text
        statusItem.button?.image = statusImage(color: color)
        switch state.preference {
        case .enabled:
            launchAtLoginItem.state = .on
            launchAtLoginItem.title = tr("登录自启", "Start at Login")
            launchAtLoginItem.isEnabled = true
        case .disabled:
            launchAtLoginItem.state = .off
            launchAtLoginItem.title = tr("登录自启", "Start at Login")
            launchAtLoginItem.isEnabled = true
        case .unknown:
            launchAtLoginItem.state = .mixed
            launchAtLoginItem.title = tr("登录自启（状态未知）", "Start at Login (Unknown State)")
            // 仍允许点击，以便给出包含 launchctl 输出的明确错误提示。
            launchAtLoginItem.isEnabled = true
        }
    }

    // MARK: 动作

    @objc private func iconClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp, let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 2), in: button)
        } else {
            openWebUI()
        }
    }

    @objc private func openWebUI() {
        NSWorkspace.shared.open(baseURL)
    }

    private func runServiceAction(
        _ title: String,
        action: @escaping @Sendable () throws -> Void,
        onSuccess: (@MainActor @Sendable () -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try action()
                DispatchQueue.main.async {
                    onSuccess?()
                    self.refresh(forceServiceState: true)
                }
            } catch {
                let serviceError = error as? ServiceActionError
                let errorMessage = error.localizedDescription
                let details = serviceError?.details ?? error.localizedDescription
                writeControllerLog(tr(
                    "\(title)失败：\(errorMessage)\n\(details)",
                    "\(title) failed: \(errorMessage)\n\(details)"
                ))
                DispatchQueue.main.async {
                    self.showError(
                        title: tr("\(title)失败", "\(title) Failed"),
                        message: errorMessage,
                        details: details
                    )
                    self.refresh(forceServiceState: true)
                }
            }
        }
    }

    private func showError(title: String, message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = "\(message)\n\n\(details)"
        alert.addButton(withTitle: tr("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func startClicked() {
        runServiceAction(tr("启动服务", "Start Service")) { try startService() }
    }

    @objc private func stopClicked() {
        runServiceAction(tr("停止服务", "Stop Service")) { try stopService() }
    }

    @objc private func restartClicked() {
        runServiceAction(tr("重启服务", "Restart Service")) { try startService() }
    }

    @objc private func logClicked() {
        if logWindowController == nil { logWindowController = LogWindowController() }
        logWindowController?.present()
    }

    @objc private func toggleLaunchAtLoginClicked() {
        runServiceAction(tr("更改登录自启", "Change Start at Login")) { try toggleLaunchAtLogin() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func stopAndQuit() {
        runServiceAction(tr("停止服务", "Stop Service"), action: { try stopService() }) {
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }
}

// MARK: - 入口

#if DSHMENU_SERVICE_TEST
do {
    try startService()
    fputs("DShMenu service test: startService succeeded\n", stdout)
    exit(0)
} catch {
    let serviceError = error as? ServiceActionError
    let details = serviceError?.details ?? error.localizedDescription
    fputs("DShMenu service test failed: \(error.localizedDescription)\n\(details)\n", stderr)
    exit(1)
}
#else
let app = NSApplication.shared
guard acquireSingletonLock() else {
    exit(0)
}
// AppKit 的入口线程就是主线程；显式告诉 Swift 并发检查器该初始化位于 MainActor。
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
#endif
