import AppKit
import Foundation

/// App-owned Companion receiver. Commands enter AppModel directly; no global event injection.
@MainActor final class IPhoneRemote: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var name: String
    @Published private(set) var running = false
    @Published private(set) var connected = false
    @Published private(set) var ready = false
    @Published private(set) var pairingOpen = false
    @Published private(set) var pin = ""
    @Published private(set) var failure: String?
    @Published private(set) var lastCommand = "尚未按键"
    @Published private(set) var commandCount = 0
    var onCommand: ((RemoteCommand) -> Void)?
    var onAudio: ((Double, Bool) -> Void)?
    private var process: Process?
    private var retiring: [Process] = []
    private var resetRequested = false
    private var input: FileHandle?
    private let writes = DispatchQueue(label: "studio.machauncy.mactv.remote-ipc")
    private var generation = UUID()
    private var lifecycle: Task<Void, Never>?
    private var pairingExpiry: Task<Void, Never>?
    private var retries = 0
    private var credential: Credential?
    private var started = false

    private struct Credential: Codable {
        var serverID: String
        var deviceID: String
        var privateKey: String
        var pin: Int
        static func fresh() -> Self {
            let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
            let mac = [UInt8(0x02)] + (0..<5).map { _ in UInt8.random(in: 0...255) }
            return Self(serverID: UUID().uuidString, deviceID: mac.map { String(format:"%02X", $0) }.joined(separator: ":"),
                        privateKey: bytes.map { String(format:"%02x", $0) }.joined(), pin: Int.random(in: 1000...9999))
        }
    }

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "iphoneRemoteEnabled") as? Bool ?? true
        name = Self.validName(defaults.string(forKey: "iphoneRemoteName") ?? "MacTV Native")
    }
    var status: String {
        if !enabled { return "已关闭" }
        if let failure { return failure }
        if ready { return "控制会话已就绪" }
        if connected { return "手机正在连接" }
        return running ? "等待 iPhone 连接" : "正在启动接收端"
    }
    static func validName(_ value: String) -> String {
        let cleaned = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        // Bonjour names have a 63-byte limit; reserve space for conflict suffixes.
        var result = ""
        for character in cleaned {
            if (result + String(character)).utf8.count > 48 { break }
            result.append(character)
        }
        return result.isEmpty ? "MacTV Native" : result
    }
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacTV Native/iPhone Remote", isDirectory: true)
    }
    func start() { guard !started else { return }; started = true; if enabled { restart() } }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey:"iphoneRemoteEnabled")
        retries = 0
        if value { restart() } else { lifecycle?.cancel(); stopReceiver() }
    }
    func rename(_ value: String) {
        let next = Self.validName(value)
        guard next != name else { return }
        name = next; UserDefaults.standard.set(next, forKey:"iphoneRemoteName")
        if enabled { restart() }
    }
    func pairAnotherPhone() {
        guard running else { restart(); return }
        send(["type":"pair"])
        openPairingWindow()
    }
    func resetPairing() { retries = 0; restart(reset: true) }
    func retry() { retries = 0; restart() }

    private func restart(reset: Bool = false) {
        resetRequested = resetRequested || reset
        lifecycle?.cancel()
        stopReceiver()
        lifecycle = Task { [weak self] in
            // Give the helper time to withdraw Bonjour records and close its ports.
            for _ in 0..<50 {
                guard let self else { return }
                self.retiring.removeAll { !$0.isRunning }
                if self.retiring.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled, let self, self.enabled else { return }
            guard self.retiring.allSatisfy({ !$0.isRunning }) else { self.failure = "接收端未退出，请重新打开 MacTV"; return }
            self.retiring.removeAll()
            do {
                if self.resetRequested {
                    for filename in ["identity.json", "controllers.json"] {
                        let file = self.directory.appendingPathComponent(filename)
                        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                    }
                    self.credential = nil
                    self.resetRequested = false
                }
                try self.launch()
            } catch { self.failure = "遥控接收端启动失败：\(error.localizedDescription)"; self.writeDiagnostics() }
        }
    }
    private func launch() throws {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable:"MacTVRemoteReceiver") else {
            throw NSError(domain:"MacTVRemote", code:1, userInfo:[NSLocalizedDescriptionKey:"安装包缺少手机遥控接收组件"])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories:true, attributes:[.posixPermissions:0o700])
        let identity = directory.appendingPathComponent("identity.json")
        let value: Credential
        if FileManager.default.fileExists(atPath: identity.path) {
            value = try JSONDecoder().decode(Credential.self, from: Data(contentsOf:identity))
        } else {
            value = .fresh()
            try JSONEncoder().encode(value).write(to:identity, options:.atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:identity.path)
        credential = value; pin = String(format:"%04d",value.pin)
        failure = nil; running = false; connected = false; ready = false
        let token = UUID(); generation = token
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        process = child; input = stdin.fileHandleForWriting
        child.terminationHandler = { [weak self] child in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.running = false; self.connected = false; self.ready = false
                self.pairingOpen = false; self.input = nil; self.process = nil
                self.failure = "遥控接收端已停止（\(child.terminationStatus)）"
                self.writeDiagnostics()
                if self.enabled && self.retries < 3 {
                    self.retries += 1
                    self.lifecycle = Task { [weak self] in
                        try? await Task.sleep(for:.seconds(2))
                        guard !Task.isCancelled else { return }
                        self?.restart()
                    }
                }
            }
        }
        try child.run()
        // The parent must not retain a copy of the read ends supplied to the child.
        stdin.fileHandleForReading.closeFile()
        stdout.fileHandleForWriting.closeFile(); stderr.fileHandleForWriting.closeFile()
        send(["name":name, "pin":value.pin, "serverId":value.serverID, "deviceId":value.deviceID,
              "privateKey":value.privateKey, "stateDirectory":directory.path])
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var buffer = Data()
            while true {
                let data = stdout.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                if buffer.count > 256 * 1024 { child.terminate(); break }
                while let newline = buffer.firstIndex(of:10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.receive(line)
                    }
                }
            }
            stdout.fileHandleForReading.closeFile()
        }
        DispatchQueue.global(qos:.utility).async {
            // Drain stderr to prevent a blocked child; protocol/log details are not shown as UI.
            while !stderr.fileHandleForReading.availableData.isEmpty {}
            stderr.fileHandleForReading.closeFile()
        }
        Task { [weak self] in
            try? await Task.sleep(for:.seconds(8))
            guard let self, self.generation == token, !self.running else { return }
            self.failure = "接收端未能启动，请检查网络后重试"
            self.stopReceiver()
        }
    }
    private func send(_ object:[String:Any]) {
        guard let input, let data = try? JSONSerialization.data(withJSONObject:object) else { return }
        writes.async { try? input.write(contentsOf:data + Data([10])) }
    }
    func updateAudio(volume:Double, muted:Bool) {
        guard running, volume.isFinite else { return }
        send(["type":"audio", "volume":min(1,max(0,volume)), "muted":muted])
    }
    private func receive(_ data:Data) {
        guard let message = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let type = message["type"] as? String else { return }
        switch type {
        case "started":
            running = true; failure = nil
            if message["pairingOpen"] as? Bool == true { openPairingWindow() }
        case "connection":
            connected = message["connected"] as? Bool ?? false
            ready = connected && (message["ready"] as? Bool ?? false)
        case "paired": pairingOpen = false; pairingExpiry?.cancel()
        case "pairing": openPairingWindow()
        case "command":
            if let value = message["command"] as? String, let command = RemoteCommand(rawValue:value) {
                lastCommand = command.label; commandCount += 1; onCommand?(command)
            }
        case "audio":
            if let volume = message["volume"] as? Double, let muted = message["muted"] as? Bool { onAudio?(volume,muted) }
        case "error": failure = "接收端异常，请重试或重新配对"
        case "stopped": running = false; connected = false; ready = false
        default:break
        }
        writeDiagnostics()
    }
    private func openPairingWindow() {
        pairingExpiry?.cancel(); pairingOpen = true
        pairingExpiry = Task { [weak self] in
            try? await Task.sleep(for:.seconds(300))
            if !Task.isCancelled { self?.pairingOpen = false }
        }
    }
    private func stopReceiver() {
        generation = UUID(); pairingExpiry?.cancel()
        let old = process, pipe = input
        if let pipe {
            writes.async {
                try? pipe.write(contentsOf:Data("{\"type\":\"stop\"}\n".utf8))
                try? pipe.close()
            }
        }
        input = nil; process = nil; running = false; connected = false; ready = false; pairingOpen = false
        if let old {
            retiring.append(old)
            Task {
                try? await Task.sleep(for:.seconds(2))
                if old.isRunning { old.terminate() }
            }
        }
        writeDiagnostics()
    }
    func stop() { started = false; lifecycle?.cancel(); stopReceiver() }
    private func writeDiagnostics() {
        // Explicit developer opt-in. Never include PINs, identifiers, or controller keys.
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of:"--remote-diagnostics"), i+1 < args.count else { return }
        let state:[String:Any] = ["running":running,"connected":connected,"ready":ready,"name":name,
            "lastCommand":lastCommand,"commandCount":commandCount,"appActive":NSApp.isActive,"status":status]
        if let data = try? JSONSerialization.data(withJSONObject:state,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:URL(fileURLWithPath:args[i+1]),options:.atomic)
        }
    }
}
