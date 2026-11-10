import AppKit
import IOKit.hid
import IOKit.hidsystem

@MainActor final class RemoteInput: ObservableObject {
    @Published var status = "键盘可用 · USB 遥控器待授权"
    @Published var permissionGranted = false
    @Published var connected = false
    @Published var lastButton = "尚未按键"
    var onCommand: ((RemoteCommand,String)->Void)?
    private var manager: IOHIDManager?
    private var devices = Set<UInt>()
    private var pressed = Set<RemoteCommand>()
    private var timers: [RemoteCommand:Timer] = [:]
    private var poll: Timer?
    var held: Set<RemoteCommand> { pressed }

    func start() {
        refresh()
        poll=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    private func refresh() {
        permissionGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)==kIOHIDAccessTypeGranted
        if !permissionGranted { status="键盘可用 · 请启用输入监控"; return }
        guard manager == nil else {
            status=connected ? "USB 遥控器已连接" : "等待 USB 接收器"
            return
        }
        let m=IOHIDManagerCreate(kCFAllocatorDefault,0)
        IOHIDManagerSetDeviceMatchingMultiple(m,[
            [kIOHIDVendorIDKey:1046,kIOHIDProductIDKey:1538,kIOHIDTransportKey:"USB",kIOHIDPrimaryUsagePageKey:1,kIOHIDPrimaryUsageKey:6],
            [kIOHIDVendorIDKey:1046,kIOHIDProductIDKey:1538,kIOHIDTransportKey:"USB",kIOHIDPrimaryUsagePageKey:12,kIOHIDPrimaryUsageKey:1]
        ] as CFArray)
        let context=Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m,{ context,result,_,device in
            guard let context,result==kIOReturnSuccess else{return}
            let id=UInt(bitPattern:Unmanaged.passUnretained(device).toOpaque())
            DispatchQueue.main.async {
                let remote=Unmanaged<RemoteInput>.fromOpaque(context).takeUnretainedValue()
                remote.devices.insert(id);remote.connected=true;remote.status="USB 遥控器已连接"
            }
        },context)
        IOHIDManagerRegisterDeviceRemovalCallback(m,{ context,_,_,device in
            guard let context else{return}
            let id=UInt(bitPattern:Unmanaged.passUnretained(device).toOpaque())
            DispatchQueue.main.async {
                let remote=Unmanaged<RemoteInput>.fromOpaque(context).takeUnretainedValue()
                remote.devices.remove(id);remote.connected = !remote.devices.isEmpty
                remote.releaseAll();remote.status=remote.connected ? "USB 遥控器已连接" : "等待 USB 接收器"
            }
        },context)
        IOHIDManagerRegisterInputValueCallback(m,{ context,result,_,value in
            guard let context,result==kIOReturnSuccess else{return}
            let element=IOHIDValueGetElement(value)
            guard let command=RemoteCommand.hid(page:IOHIDElementGetUsagePage(element),usage:IOHIDElementGetUsage(element)) else{return}
            let down=IOHIDValueGetIntegerValue(value) != 0
            DispatchQueue.main.async {
                Unmanaged<RemoteInput>.fromOpaque(context).takeUnretainedValue().receive(command,down:down)
            }
        },context)
        IOHIDManagerScheduleWithRunLoop(m,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue)
        // Shared, product-filtered reading. This application never seizes a
        // keyboard, starts a privileged helper, or installs a global event tap.
        let result=IOHIDManagerOpen(m,0)
        if result==kIOReturnSuccess {manager=m;status="等待 USB 接收器"}
        else {IOHIDManagerClose(m,0);status=String(format:"USB 打开失败（0x%08x）",result)}
    }
    private func receive(_ command:RemoteCommand,down:Bool) {
        if !down {pressed.remove(command);timers.removeValue(forKey:command)?.invalidate();return}
        guard NSApp.isActive,pressed.insert(command).inserted else{return}
        lastButton=command.label;onCommand?(command,"hid")
        if command.repeats {
            let timer=Timer(fire:Date(timeIntervalSinceNow:0.42),interval:0.12,repeats:true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard NSApp.isActive else{self?.releaseAll();return}
                    self?.onCommand?(command,"hid")
                }
            }
            timers[command]=timer;RunLoop.main.add(timer,forMode:.common)
        }
    }
    func releaseAll() {timers.values.forEach{$0.invalidate()};timers.removeAll();pressed.removeAll()}
    func stop() {
        poll?.invalidate();releaseAll()
        if let m=manager {IOHIDManagerUnscheduleFromRunLoop(m,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue);IOHIDManagerClose(m,0)}
        manager=nil
    }
}
