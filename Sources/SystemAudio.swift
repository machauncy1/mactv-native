import Foundation
import CoreAudio
import AudioToolbox

struct SystemAudioSnapshot {
    let volume:Double
    let muted:Bool
}

enum AudioLevel {
    static func clamped(_ value:Double)->Double? {value.isFinite ? min(1,max(0,value)):nil}
    static func adjusted(_ value:Double,delta:Double)->Double? {
        guard value.isFinite,delta.isFinite else{return nil}
        return clamped(value+delta)
    }
}

/// Controls the current default output through Core Audio, without changing its routing.
/// Fixed-level outputs return nil so the caller can explicitly fall back to player gain.
final class SystemAudioDriver {
    private struct Output {
        let device:AudioObjectID
        var volumeAddress:AudioObjectPropertyAddress
        let volume:Float32
    }
    private var emulatedMute:(device:AudioObjectID,volume:Double)?
    private func address(_ selector:AudioObjectPropertySelector,scope:AudioObjectPropertyScope=kAudioDevicePropertyScopeOutput)->AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    private func writable(_ device:AudioObjectID,_ original:AudioObjectPropertyAddress)->Bool {
        var property=original,allowed=DarwinBoolean(false)
        return AudioObjectHasProperty(device,&property) && AudioObjectIsPropertySettable(device,&property,&allowed)==noErr && allowed.boolValue
    }
    private func output()->Output? {
        var property=address(kAudioHardwarePropertyDefaultOutputDevice,scope:kAudioObjectPropertyScopeGlobal)
        var device=AudioObjectID(0),size=UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&property,0,nil,&size,&device)==noErr,device != kAudioObjectUnknown else{return nil}
        if let remembered=emulatedMute,remembered.device != device {emulatedMute=nil}
        // Virtual main volume preserves the balance of devices with channel controls.
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume,kAudioDevicePropertyVolumeScalar] {
            var property=address(selector),volume=Float32(0);size=UInt32(MemoryLayout<Float32>.size)
            if writable(device,property),AudioObjectGetPropertyData(device,&property,0,nil,&size,&volume)==noErr,volume.isFinite {
                return Output(device:device,volumeAddress:property,volume:volume)
            }
        }
        return nil
    }
    private func mute(_ device:AudioObjectID)->Bool? {
        var property=address(kAudioDevicePropertyMute),value=UInt32(0),size=UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device,&property),AudioObjectGetPropertyData(device,&property,0,nil,&size,&value)==noErr else{return nil}
        return value != 0
    }
    func read()->SystemAudioSnapshot? {
        guard let output=output() else{return nil}
        if let remembered=emulatedMute,remembered.device==output.device {
            if output.volume<=0.0001 {return SystemAudioSnapshot(volume:remembered.volume,muted:true)}
            emulatedMute=nil
        }
        return SystemAudioSnapshot(volume:Double(output.volume),muted:mute(output.device) ?? false)
    }
    @discardableResult func set(volume:Double,muted:Bool,deadline:TimeInterval = .infinity)->SystemAudioSnapshot? {
        guard let requested=AudioLevel.clamped(volume),let output=output() else{return nil}
        guard ProcessInfo.processInfo.systemUptime<deadline else{return nil}
        var muteProperty=address(kAudioDevicePropertyMute)
        let hardwareMute=writable(output.device,muteProperty)
        // Mute first when requested, but set the new level before unmuting.
        if muted && hardwareMute {
            var value=UInt32(1)
            guard AudioObjectSetPropertyData(output.device,&muteProperty,0,nil,UInt32(MemoryLayout<UInt32>.size),&value)==noErr else{return nil}
        }
        guard ProcessInfo.processInfo.systemUptime<deadline else{return nil}
        var property=output.volumeAddress,level=Float32(muted && !hardwareMute ? 0:requested)
        guard AudioObjectSetPropertyData(output.device,&property,0,nil,UInt32(MemoryLayout<Float32>.size),&level)==noErr else{return nil}
        if hardwareMute && !muted {
            var value=UInt32(0)
            guard AudioObjectSetPropertyData(output.device,&muteProperty,0,nil,UInt32(MemoryLayout<UInt32>.size),&value)==noErr else{return nil}
        }
        emulatedMute=muted && !hardwareMute ? (output.device,requested):nil
        return read()
    }
    @discardableResult func adjust(_ command:RemoteCommand,deadline:TimeInterval = .infinity)->SystemAudioSnapshot? {
        guard let current=read(),ProcessInfo.processInfo.systemUptime<deadline else{return nil}
        switch command {
        case .volumeUp:return set(volume:AudioLevel.adjusted(current.volume,delta:0.05) ?? current.volume,muted:false,deadline:deadline)
        case .volumeDown:return set(volume:AudioLevel.adjusted(current.volume,delta:-0.05) ?? current.volume,muted:false,deadline:deadline)
        case .mute:return set(volume:current.volume,muted:!current.muted,deadline:deadline)
        default:return nil
        }
    }
}


enum SystemAudioResult {case success(SystemAudioSnapshot),unsupported,unavailable}

/// HAL calls may wait on another process. Keep them off the UI thread, bound the
/// queue, and expire pending writes instead of applying delayed keys much later.
@MainActor final class SystemAudio {
    private let driver=SystemAudioDriver()
    private let queue=DispatchQueue(label:"studio.machauncy.mactv.system-audio",qos:.userInitiated)
    private var outstanding=0
    func read(_ completion:@escaping(SystemAudioResult)->Void){
        guard outstanding==0 else{return}
        perform({driver,_ in driver.read()},completion)
    }
    func adjust(_ command:RemoteCommand,_ completion:@escaping(SystemAudioResult)->Void){
        perform({driver,deadline in driver.adjust(command,deadline:deadline)},completion)
    }
    func set(volume:Double,muted:Bool,_ completion:@escaping(SystemAudioResult)->Void){
        perform({driver,deadline in driver.set(volume:volume,muted:muted,deadline:deadline)},completion)
    }
    private func perform(_ operation:@escaping(SystemAudioDriver,TimeInterval)->SystemAudioSnapshot?,_ completion:@escaping(SystemAudioResult)->Void){
        guard outstanding<16 else{completion(.unavailable);return}
        outstanding+=1
        let deadline=ProcessInfo.processInfo.systemUptime+2,driver=self.driver
        var delivered=false
        let timeout=Task { @MainActor in
            try? await Task.sleep(for:.seconds(2))
            guard !Task.isCancelled,!delivered else{return}
            delivered=true;completion(.unavailable)
        }
        queue.async{[weak self] in
            let state=ProcessInfo.processInfo.systemUptime<deadline ? operation(driver,deadline):nil
            let expired=ProcessInfo.processInfo.systemUptime>=deadline
            Task { @MainActor [weak self] in
                self?.outstanding-=1
                guard !delivered else{return};delivered=true;timeout.cancel()
                completion(expired ? .unavailable:state.map{.success($0)} ?? .unsupported)
            }
        }
    }
}
