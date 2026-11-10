import Foundation

enum RemoteCommand: String, CaseIterable {
    case up, down, left, right, select, back, home, menu, playPause, mute, volumeUp, volumeDown, skipForward, skipBackward
    static func hid(page: UInt32, usage: UInt32) -> Self? {
        switch (page, usage) {
        case (7,82): return .up
        case (7,81): return .down
        case (7,80): return .left
        case (7,79): return .right
        case (7,40),(12,65): return .select
        case (7,41),(7,42),(12,548): return .back
        case (7,74),(12,547): return .home
        case (7,101),(12,64): return .menu
        case (7,44),(12,240),(12,205): return .playPause
        case (12,226): return .mute
        case (12,233): return .volumeUp
        case (12,234): return .volumeDown
        case (7,75),(12,181): return .skipForward
        case (7,78),(12,182): return .skipBackward
        default: return nil
        }
    }
    var repeats: Bool { [.up,.down,.left,.right,.volumeUp,.volumeDown].contains(self) }
    var label: String {
        switch self {
        case .up:return "上"; case .down:return "下"; case .left:return "左"; case .right:return "右"
        case .select:return "确定"; case .back:return "返回"; case .home:return "主页"; case .menu:return "菜单"
        case .playPause:return "播放 / 暂停"; case .mute:return "静音"; case .volumeUp:return "音量 +"
        case .volumeDown:return "音量 −"; case .skipForward:return "快进"; case .skipBackward:return "快退"
        }
    }
}

struct HomeFocus: Equatable {
    var row = 0
    var column = 0
    mutating func move(_ command: RemoteCommand, rows: [Int]) {
        guard !rows.isEmpty else { row = 0; column = 0; return }
        row = min(max(0,row),rows.count-1)
        switch command {
        case .left:column = max(0,column-1)
        case .right:column = min(max(0,rows[row]-1),column+1)
        case .up:row = max(0,row-1)
        case .down:row = min(rows.count-1,row+1)
        default:break
        }
        column = min(max(0,column),max(0,rows[row]-1))
    }
}

enum Timeline {
    static func resume(_ position:Double,duration:Double)->Double {
        let value=clamp(position,duration:duration)
        return duration.isFinite && duration>0 && value>=max(0,duration-2) ? 0 : value
    }
    static func clamp(_ value: Double, duration: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0,min(value,duration.isFinite && duration>0 ? duration : max(0,value)))
    }
    static func text(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--:--" }
        let n = Int(value)
        return n >= 3600 ? String(format:"%d:%02d:%02d",n/3600,n/60%60,n%60) : String(format:"%d:%02d",n/60,n%60)
    }
}

enum HomeGrid {
    static func move(_ command:RemoteCommand,index:Int)->Int {
        let index=min(5,max(0,index))
        switch command {
        case .left:return index%3==0 ? index:index-1
        case .right:return index%3==2 ? index:index+1
        case .up:return index>=3 ? index-3:index
        case .down:return index<3 ? index+3:index
        default:return index
        }
    }
}

struct LibraryItem: Codable, Identifiable {
    let id: UUID
    var title: String
    var bookmark: Data
    var position: Double
    var lastPlayed: Date
}

struct SmokeTests {
    static func run() -> Bool {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !value() { fputs("FAIL: \(name)\n",stderr); exit(1) }
        }
        let inputs: [(UInt32,UInt32,RemoteCommand)] = [(7,82,.up),(7,81,.down),(7,80,.left),(7,79,.right),
            (12,65,.select),(12,548,.back),(12,547,.home),(7,101,.menu),(12,240,.playPause),
            (12,226,.mute),(12,233,.volumeUp),(12,234,.volumeDown),(7,75,.skipForward),(7,78,.skipBackward)]
        for (page,usage,result) in inputs { check(RemoteCommand.hid(page:page,usage:usage)==result,"HID \(page):\(usage)") }
        check(RemoteCommand.hid(page:7,usage:4)==nil,"unrelated typing ignored")
        check(RemoteCommand.hid(page:7,usage:UInt32.max)==nil,"array metadata ignored")
        var f=HomeFocus()
        f.move(.left,rows:[4,2]); check(f.column==0,"left boundary")
        for _ in 0..<8 { f.move(.right,rows:[4,2]) }
        check(f.column==3,"right boundary")
        f.move(.down,rows:[4,2]);check(f==HomeFocus(row:1,column:1),"short row clamp")
        f.move(.up,rows:[4,2]);check(f==HomeFocus(row:0,column:1),"return to apps")
        var wide=HomeFocus()
        for _ in 0..<9 {wide.move(.right,rows:[7,1])}
        check(wide.column==6,"seven app carousel boundary")
        wide.move(.down,rows:[7,1]);check(wide==HomeFocus(row:1,column:0),"carousel to recent clamp")
        check(HomeGrid.move(.down,index:1)==4,"grid down keeps column")
        check(HomeGrid.move(.up,index:5)==2,"grid up keeps column")
        check(HomeGrid.move(.left,index:0)==0,"shelf left boundary")
        check(HomeGrid.move(.right,index:5)==5,"shelf right boundary")
        check(HomeGrid.move(.left,index:3)==3,"grid row left boundary")
        check(HomeGrid.move(.right,index:2)==2,"grid row right boundary")
        check(HomeGrid.move(.up,index:1)==1,"grid top boundary")
        check(HomeGrid.move(.down,index:4)==4,"grid bottom boundary")
        check(Timeline.clamp(-5,duration:10)==0,"negative seek")
        check(Timeline.clamp(50,duration:10)==10,"seek past end")
        check(Timeline.clamp(.nan,duration:10)==0,"invalid seek")
        check(Timeline.text(3661)=="1:01:01","long duration")
        check(Timeline.text(.nan)=="--:--","unknown duration")
        check(Timeline.resume(99,duration:100)==0,"finished movie restarts")
        check(Timeline.resume(45,duration:100)==45,"unfinished movie resumes")
        check(!RemoteCommand.select.repeats && RemoteCommand.right.repeats,"repeat policy")
        print("PASS: \(checks) core checks")
        return true
    }
}
