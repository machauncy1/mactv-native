import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

enum Screen {case home,player,web,recent}

@MainActor final class AppModel:ObservableObject {
    @Published var screen:Screen = .home
    @Published var focus=HomeFocus()
    @Published var menuOpen=false {didSet {if !menuOpen {menuIndex=0}}}
    @Published var menuIndex=0
    @Published var library:[LibraryItem]=[]
    @Published var toast:String?
    @Published var playerControls=true
    @Published var playerActionIndex:Int?
    @Published var playerScrubbing=false
    @Published var reducedMotion=UserDefaults.standard.bool(forKey:"reduceMotion")
    let playback=Playback()
    @Published var service:WebService = .youtube
    private var cachedBrowsers:[WebService:YouTubeBrowser]=[:]
    var browser:YouTubeBrowser {
        if let value=cachedBrowsers[service] {return value}
        let value=YouTubeBrowser(service:service)
        value.bilibili?.canAutoplay={ [weak self] in guard let self else{return false};return self.screen == .web && self.service == .bilibili && !self.menuOpen && NSApp.isActive }
        value.bilibili?.onHome={ [weak self] in self?.home() }
        value.bilibili?.onFullscreen={ [weak self] in self?.toggleFullscreen() }
        value.bilibili?.onAppMenu={ [weak self] in self?.menuIndex=0;self?.menuOpen=true }
        cachedBrowsers[service]=value;return value
    }
    let remote=RemoteInput()
    private var filePanel:NSOpenPanel?
    private var homeIndex=UserDefaults.standard.integer(forKey:"homeAppIndex")
    private var recentIndex=0
    private var activeItem:UUID?
    private var persistenceDate=Date.distantPast
    private var lastInput:(RemoteCommand,String,TimeInterval)?
    private var toastTask:Task<Void,Never>?
    private var hideControls:Task<Void,Never>?
    private var eventMonitor:Any?
    private var consumedKeys=Set<UInt16>()
    private var resignObserver:NSObjectProtocol?
    var lastKeyboardTime=Date.distantPast
    let menuTitles=["Wi-Fi"]
    func backControlCenter(){menuOpen=false}

    init() {
        if let bytes=UserDefaults.standard.data(forKey:"library"),let items=try? JSONDecoder().decode([LibraryItem].self,from:bytes) {library=Array(items.prefix(30))}
        let originalLibrary=library.count
        library.removeAll{item in item.title=="test-pattern" && (resolve(item)?.path.hasSuffix("/mactv-native/.build/test-pattern.mp4") ?? false)}
        if library.count != originalLibrary {
            if let old=UserDefaults.standard.data(forKey:"library") {UserDefaults.standard.set(old,forKey:"libraryBeforeDemoCleanup")}
            saveLibrary()
        }
        homeIndex=min(5,max(0,homeIndex));focus=HomeFocus(row:0,column:homeIndex)
        remote.onCommand={ [weak self] command,source in self?.input(command,source:source) }
        playback.onProgress={ [weak self] _ in self?.persistProgress() }
    }
    func start() {
        remote.start()
        eventMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.systemDefined]) { [weak self] event in
            guard let self,NSApp.isActive else{return event}
            if event.type == .keyUp {return self.consumedKeys.remove(event.keyCode) == nil ? event:nil}
            let result=self.keyboard(event)
            if event.type == .keyDown && result == nil {self.consumedKeys.insert(event.keyCode)}
            return result
        }
        resignObserver=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.remote.releaseAll();self?.consumedKeys.removeAll() }
        }
    }
    func finish() {persistProgress(force:true);remote.stop();playback.finish();if let eventMonitor {NSEvent.removeMonitor(eventMonitor)};if let resignObserver {NotificationCenter.default.removeObserver(resignObserver)}}
    private func keyboard(_ event:NSEvent)->NSEvent? {
        if let panel=filePanel,panel.isVisible {
            if event.type == .keyDown && event.keyCode==53 {panel.cancel(nil);return nil}
            return event
        }
        guard !(NSApp.keyWindow is NSPanel) else{return event}
        if event.type == .systemDefined {
            let flags=(event.data1>>8)&0xff
            guard event.subtype.rawValue==8,flags==0x0a else{return event}
            let code=(event.data1>>16)&0xffff
            let map:[Int:RemoteCommand]=[0:.volumeUp,1:.volumeDown,7:.mute,16:.playPause,17:.skipForward,18:.skipBackward]
            if let c=map[code] {input(c,source:"keyboard");return nil}
            return event
        }
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased()=="o" {openFiles();return nil}
            if event.charactersIgnoringModifiers?.lowercased()=="h",event.modifierFlags.contains(.shift) {home();return nil}
            return event
        }
        let map:[UInt16:RemoteCommand]=[126:.up,125:.down,123:.left,124:.right,36:.select,76:.select,53:.back,51:.back,115:.home,116:.skipForward,121:.skipBackward,49:.playPause,46:.playPause]
        // Native keyboard events stay trusted inside WebKit. Raw HID commands
        // go through WebKit's NSResponder when the USB receiver is used.
        if screen == .web && !menuOpen {
            if event.keyCode==53 {input(.back,source:"keyboard");return nil}
            if event.keyCode==115 {input(.home,source:"keyboard");return nil}
            if let c=map[event.keyCode],remote.held.contains(c) {return nil}
            if service == .bilibili,let tv=browser.bilibili {
                if tv.panel == .search,NSApp.keyWindow?.firstResponder is NSTextView {return event}
                if event.charactersIgnoringModifiers?.lowercased()=="f" {toggleFullscreen();return nil}
                if event.charactersIgnoringModifiers?.lowercased()=="e" {tv.openEpisodes();return nil}
                if let command=map[event.keyCode] {input(command,source:"keyboard");return nil}
            }
            return event
        }
        if event.charactersIgnoringModifiers?.lowercased()=="f" {toggleFullscreen();return nil}
        guard let command=map[event.keyCode] else{return event}
        if event.isARepeat && remote.held.contains(command) {return nil}
        input(command,source:"keyboard");return nil
    }
    func input(_ command:RemoteCommand,source:String) {
        guard NSApp.isActive else{return}
        if let panel=filePanel,panel.isVisible {if command == .back {panel.cancel(nil)};return}
        guard !(NSApp.keyWindow is NSPanel) else{return}
        let now=ProcessInfo.processInfo.systemUptime
        if let (old,oldSource,time)=lastInput,old==command,oldSource != source,now-time<0.075 {return}
        lastInput=(command,source,now);lastKeyboardTime=Date()
        if command == .home {home();return}
        if command == .playPause {
            if screen == .player {playback.toggle();showControls()}
            else if screen == .web {browser.send(.playPause)}
            return
        }
        if command == .menu {
            if menuOpen {menuOpen=false;return}
            if screen == .player {if playerActionIndex != nil {hidePlayerControls()} else {showPlayerActions()};return}
            if screen == .web && service == .bilibili && !menuOpen {browser.bilibili?.navigate(command)}
            else {menuOpen.toggle();menuIndex=0}
            return
        }
        if [.volumeUp,.volumeDown,.mute].contains(command) {media(command);return}
        if menuOpen {
            switch command {
            case .up:menuIndex=max(0,menuIndex-1)
            case .down:menuIndex=min(menuTitles.count-1,menuIndex+1)
            case .left:menuIndex=max(0,menuIndex-1)
            case .right:menuIndex=min(menuTitles.count-1,menuIndex+1)
            case .select:performMenu(menuIndex)
            case .back:backControlCenter()
            default:break
            }
            return
        }
        switch screen {
        case .home:
            if command == .select {activate(focus.column)}
            else {focusHomeApp(HomeGrid.move(command,index:focus.column))}
        case .recent:
            switch command {
            case .up:
                if recentIndex==0 && !library.isEmpty {focus=HomeFocus(row:0,column:0)}else{recentIndex=max(0,recentIndex-1);focus=HomeFocus(row:1,column:recentIndex)}
            case .down:
                if focus.row==0 {focus=HomeFocus(row:1,column:recentIndex)}else{recentIndex=min(max(0,library.count-1),recentIndex+1);focus=HomeFocus(row:1,column:recentIndex)}
            case .left,.right:
                if focus.row>0 {recentIndex=min(max(0,library.count-1),max(0,recentIndex+(command == .right ? 1:-1)));focus=HomeFocus(row:1,column:recentIndex)}
            case .select:if !library.isEmpty && focus.row>0 {play(library[recentIndex])}else{openFiles()}
            case .back:home()
            default:break
            }
        case .player:
            if let index=playerActionIndex {
                switch command {
                case .left:playerActionIndex=max(0,index-1)
                case .right:playerActionIndex=min(4,index+1)
                case .select:performPlayerAction(index)
                case .down:playerActionIndex=nil;showControls()
                case .back:hidePlayerControls()
                default:break
                };return
            }
            switch command {
            case .left:playback.seek(-10);showControls()
            case .right:playback.seek(10);showControls()
            case .skipForward:playback.seek(30);showControls()
            case .skipBackward:playback.seek(-30);showControls()
            case .select,.playPause:playback.toggle();showControls()
            case .up:showPlayerActions()
            case .down:showControls()
            case .back:if playerControls || playerScrubbing {hidePlayerControls()}else{home()}
            default:break
            }
        case .web:
            if service == .bilibili {browser.bilibili?.navigate(command);return}
            if command == .back {
                if !browser.back() {home()}
            }else{browser.send(command)}
        }
    }
    func activate(_ index:Int) {
        homeIndex=min(5,max(0,index));UserDefaults.standard.set(homeIndex,forKey:"homeAppIndex")
        focus=HomeFocus(row:0,column:index)
        switch index {
        case 0...2:
            persistProgress(force:true);playback.pause();cachedBrowsers[service]?.pause()
            service=WebService.allCases[index];screen = .web;browser.open()
        case 3:if playback.loadedURL != nil {cachedBrowsers[service]?.pause();screen = .player;playback.player.play();playback.playing=true;showControls()} else {openFiles()}
        case 4:screen = .recent;recentIndex=0;focus=HomeFocus(row:1,column:0)
        default:menuIndex=0;menuOpen=true
        }
    }
    func home() {
        persistProgress(force:true);playback.pause();cachedBrowsers[service]?.pause();menuOpen=false;playerActionIndex=nil;playerScrubbing=false;screen = .home
        focus=HomeFocus(row:0,column:homeIndex)
    }
    func focusHomeApp(_ index:Int){
        let next=min(5,max(0,index));guard next != focus.column else{return}
        focus=HomeFocus(row:0,column:next);homeIndex=next
        UserDefaults.standard.set(next,forKey:"homeAppIndex")
    }
    func media(_ command:RemoteCommand) {
        if screen == .web {browser.send(command)}
        else {
            if command == .mute {playback.toggleMute()} else {playback.changeVolume(command == .volumeUp ? 0.05 : -0.05)}
            message(playback.muted ? "已静音" : "播放音量 \(Int(playback.volume*100))%")
        }
    }
    func performMenu(_ index:Int) {
        guard index==0,let url=URL(string:"x-apple.systempreferences:com.apple.wifi-settings-extension") else{return}
        if NSWorkspace.shared.open(url) {menuOpen=false}else{message("无法打开 Wi-Fi 设置")}
    }
    func toggleFullscreen() {NSApp.keyWindow?.toggleFullScreen(nil)}
    func message(_ text:String) {
        toastTask?.cancel();toast=text
        toastTask=Task {try? await Task.sleep(for:.seconds(3));if !Task.isCancelled {toast=nil}}
    }
    func showPlayerActions(){hideControls?.cancel();playerControls=true;playerActionIndex=1}
    func hidePlayerControls(){hideControls?.cancel();playerControls=false;playerActionIndex=nil;playerScrubbing=false}
    func performPlayerAction(_ index:Int){
        switch index {
        case 0:playback.seek(-10)
        case 1:playback.toggle()
        case 2:playback.seek(10)
        case 3:playback.toggleMute()
        case 4:toggleFullscreen()
        default:break
        }
        showControls()
    }
    func showControls() {
        hideControls?.cancel();playerControls=true
        hideControls=Task {try? await Task.sleep(for:.seconds(4));if !Task.isCancelled && playback.playing && playerActionIndex==nil && !playerScrubbing {playerControls=false}}
    }
    func openFiles() {
        if filePanel?.isVisible == true {return}
        let panel=NSOpenPanel();filePanel=panel;panel.title="选择本地影片";panel.prompt="播放";panel.canChooseDirectories=false
        panel.allowsMultipleSelection=true;panel.allowedContentTypes=[.movie,.video,.audiovisualContent]
        panel.begin { [weak self] response in
            self?.filePanel=nil
            guard response == .OK else{return}
            let urls=panel.urls
            Task { @MainActor in
                guard let self else{return}
                for url in urls {self.remember(url)}
                if let first=urls.first {self.openURL(first)}
            }
        }
    }
    private func remember(_ url:URL) {
        guard let data=try? url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil) else{return}
        if let i=library.firstIndex(where:{resolve($0)==url}) {library[i].lastPlayed=Date()}
        else {library.insert(LibraryItem(id:UUID(),title:url.deletingPathExtension().lastPathComponent,bookmark:data,position:0,lastPlayed:Date()),at:0)}
        library=Array(library.sorted{$0.lastPlayed>$1.lastPlayed}.prefix(30));saveLibrary()
    }
    func openURL(_ url:URL) {
        guard url.isFileURL else{return}
        remember(url)
        if let item=library.first(where:{resolve($0)==url}) {play(item)}
    }
    func resolve(_ item:LibraryItem)->URL? {var stale=false;return try? URL(resolvingBookmarkData:item.bookmark,options:[.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)}
    func play(_ item:LibraryItem) {
        guard let url=resolve(item),FileManager.default.isReadableFile(atPath:url.path) else{message("文件暂时不可用，请重新选择影片。");return}
        persistProgress(force:true);cachedBrowsers[service]?.pause();activeItem=item.id;screen = .player;menuOpen=false
        playback.open(url,title:item.title,position:item.position);showControls()
    }
    func persistProgress(force:Bool=false) {
        guard force || Date().timeIntervalSince(persistenceDate)>5 else{return}
        guard let id=activeItem,let i=library.firstIndex(where:{$0.id==id}) else{return}
        persistenceDate=Date();library[i].position=playback.current;library[i].lastPlayed=Date();saveLibrary()
    }
    private func saveLibrary() {if let data=try? JSONEncoder().encode(library) {UserDefaults.standard.set(data,forKey:"library")}}
}
