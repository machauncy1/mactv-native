import AppKit
import SwiftUI
import AVKit
import WebKit

@MainActor final class Playback: ObservableObject {
    let player=AVPlayer()
    @Published var title="本地影院"
    @Published var current=0.0
    @Published var duration=0.0
    @Published var playing=false
    @Published var volume:Float=0.8
    @Published var muted=false
    @Published var failure:String?
    var loadedURL:URL?
    var onProgress:((Double)->Void)?
    private var observer:Any?
    private var statusObservation:NSKeyValueObservation?
    private var finished:NSObjectProtocol?
    init() {
        player.volume=volume
        player.appliesMediaSelectionCriteriaAutomatically=false
        observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.25,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor in
                guard let self else{return}
                self.current=max(0,time.seconds.isFinite ? time.seconds : 0)
                self.playing=self.player.rate>0
                if let d=self.player.currentItem?.duration.seconds,d.isFinite {self.duration=max(0,d)}
                self.onProgress?(self.current)
            }
        }
    }
    func open(_ url:URL,title:String,position:Double=0) {
        failure=nil;self.title=title;loadedURL=url;duration=0;current=0
        let item=AVPlayerItem(url:url)
        statusObservation=item.observe(\.status,options:[.initial,.new]) { [weak self] item,_ in
            let failed=item.status == .failed
            DispatchQueue.main.async {
                guard let self,self.player.currentItem === item else{return}
                if item.status == .readyToPlay,let subtitles=item.asset.mediaSelectionGroup(forMediaCharacteristic:.legible) {self.player.currentItem?.select(nil,in:subtitles)}
                if item.status == .readyToPlay,position>0 {
                    self.player.seek(to:CMTime(seconds:Timeline.resume(position,duration:item.duration.seconds),preferredTimescale:600))
                }
                if failed {self.failure="无法播放这个文件。请使用系统支持的 MP4、MOV 或其他兼容视频。";self.playing=false}
            }
        }
        if let finished {NotificationCenter.default.removeObserver(finished)}
        finished=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.playing=false }
        }
        player.replaceCurrentItem(with:item)
        player.play();playing=true
    }
    func toggle() {if player.rate>0 {pause()} else {if duration>0 && current>=duration-0.5 {seekTo(0)};player.play();playing=true}}
    func pause() {player.pause();playing=false}
    func seek(_ delta:Double) {seekTo(current+delta)}
    func seekTo(_ value:Double) {player.seek(to:CMTime(seconds:Timeline.clamp(value,duration:duration),preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:CMTime(seconds:0.1,preferredTimescale:600))}
    func changeVolume(_ delta:Float) {volume=min(1,max(0,volume+delta));muted=false;player.isMuted=false;player.volume=volume}
    func toggleMute() {muted.toggle();player.isMuted=muted}
    func finish() {pause();if let observer {player.removeTimeObserver(observer)};observer=nil;statusObservation=nil;if let finished {NotificationCenter.default.removeObserver(finished)}}
}

enum WebService:String,CaseIterable {
    case youtube,netflix,bilibili
    var title:String {switch self {case .youtube:return "YouTube";case .netflix:return "Netflix";case .bilibili:return "哔哩哔哩"}}
    var url:URL {URL(string:self == .youtube ? "https://www.youtube.com/tv" : self == .netflix ? "https://www.netflix.com/" : "https://www.bilibili.com/")!}
}

@MainActor final class YouTubeBrowser:NSObject,ObservableObject,WKNavigationDelegate,WKUIDelegate {
    let webView:WKWebView
    let service:WebService
    var bilibili:BilibiliRemote?
    @Published var loading=false
    @Published var failure:String?
    private var loaded=false
    private let tvAgent="Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.5) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.5 TV Safari/537.36"
    init(service:WebService = .youtube) {
        self.service=service
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback=[]
        configuration.allowsAirPlayForMediaPlayback=true
        configuration.preferences.isElementFullscreenEnabled=true
        if let url=Bundle.main.resourceURL?.appendingPathComponent("Playback/preferences.js"),let script=try? String(contentsOf:url,encoding:.utf8){
            configuration.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:.defaultClient))
        }
        if service == .bilibili,let url=Bundle.main.resourceURL?.appendingPathComponent("Bilibili/episode-guard.js"),let script=try? String(contentsOf:url,encoding:.utf8){
            configuration.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentStart,forMainFrameOnly:true,in:.page))
        }
        if service == .bilibili {
            let curtain="""
            if (/(^|\\.)bilibili\\.com$/.test(location.hostname) && /\\/video\\/|\\/bangumi\\/play\\//.test(location.pathname)) {
                const install=()=>{if(!document.documentElement)return false;const style=document.createElement('style');style.textContent='html{background:#000!important}html:not([data-mactv-player-ready]) body{visibility:hidden!important}';document.documentElement.appendChild(style);return true;};
                if(!install()){const observer=new MutationObserver(()=>{if(install())observer.disconnect()});observer.observe(document,{childList:true,subtree:true})}
            }
            """
            configuration.userContentController.addUserScript(WKUserScript(source:curtain,injectionTime:.atDocumentStart,forMainFrameOnly:true,in:.defaultClient))
        }
        if service == .bilibili,let url=Bundle.main.resourceURL?.appendingPathComponent("Bilibili/adapter.js"),let script=try? String(contentsOf:url,encoding:.utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:.defaultClient))
        }
        webView=WKWebView(frame:.zero,configuration:configuration)
        super.init()
        if service == .bilibili {let remote=BilibiliRemote();remote.attach(self);bilibili=remote}
        webView.navigationDelegate=self;webView.uiDelegate=self
        webView.allowsBackForwardNavigationGestures=true
        webView.customUserAgent=service == .youtube ? tvAgent : service == .bilibili ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15" : nil
        webView.underPageBackgroundColor = .black
    }
    func open() {if !loaded {loadHome()}}
    func loadHome() {if service == .youtube {loadTV()} else {loaded=true;failure=nil;webView.load(URLRequest(url:service.url))}}
    func loadTV() {loaded=true;failure=nil;webView.customUserAgent=tvAgent;webView.load(URLRequest(url:URL(string:"https://www.youtube.com/tv")!))}
    func desktopSite() {loaded=true;failure=nil;webView.customUserAgent=nil;webView.load(URLRequest(url:URL(string:"https://www.youtube.com/")!))}
    func pause() {webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v=>v.pause())",completionHandler:nil)}
    func media(_ expression:String) {webView.evaluateJavaScript("(()=>{const v=document.querySelector('video,audio');if(v){\(expression)}})()",completionHandler:nil)}
    func back() -> Bool {if webView.canGoBack {webView.goBack();return true};return false}
    func send(_ command:RemoteCommand) {
        if let bilibili {bilibili.navigate(command);return}
        if command == .playPause {media("v.paused?v.play():v.pause();");return}
        if command == .volumeUp {media("v.muted=false;v.volume=Math.min(1,v.volume+0.05);");return}
        if command == .volumeDown {media("v.volume=Math.max(0,v.volume-0.05);");return}
        if command == .mute {media("v.muted=!v.muted;");return}
        if command == .skipForward {media("v.currentTime+=30;");return}
        if command == .skipBackward {media("v.currentTime=Math.max(0,v.currentTime-30);");return}
        sendNative(command)
    }
    func sendNative(_ command:RemoteCommand) {
        let mapping:[RemoteCommand:(UInt16,String)]=[.up:(126,String(UnicodeScalar(NSUpArrowFunctionKey)!)),.down:(125,String(UnicodeScalar(NSDownArrowFunctionKey)!)),.left:(123,String(UnicodeScalar(NSLeftArrowFunctionKey)!)),.right:(124,String(UnicodeScalar(NSRightArrowFunctionKey)!)),.select:(36,"\r")]
        guard let (code,chars)=mapping[command],let window=webView.window else{return}
        window.makeFirstResponder(webView)
        let responder=window.firstResponder ?? webView
        for type in [NSEvent.EventType.keyDown,.keyUp] {
            if let event=NSEvent.keyEvent(with:type,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code) {
                if type == .keyDown {responder.keyDown(with:event)} else {responder.keyUp(with:event)}
            }
        }
    }
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!) {loading=true;failure=nil;bilibili?.navigationStarted()}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {loading=false;if service != .bilibili {webView.window?.makeFirstResponder(webView)};bilibili?.refresh()}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        guard (error as NSError).code != NSURLErrorCancelled else{return}
        loading=false;failure="\(service.title) 暂时无法加载，请检查网络后重试。"
    }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {loading=false}
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {loading=false;failure="网页进程已停止，请重新载入。"}
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if navigationAction.targetFrame == nil,let url=navigationAction.request.url,["https","http"].contains(url.scheme ?? "") {webView.load(navigationAction.request)}
        return nil
    }
}

struct NativeVideoView:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->AVPlayerView {let v=AVPlayerView();v.player=player;v.controlsStyle = .none;v.videoGravity = .resizeAspect;return v}
    func updateNSView(_ view:AVPlayerView,context:Context) {if view.player !== player {view.player=player}}
}
struct EmbeddedYouTube:NSViewRepresentable {
    let browser:YouTubeBrowser
    var visible=true
    func makeNSView(context:Context)->WKWebView {browser.webView.isHidden = !visible;return browser.webView}
    func updateNSView(_ view:WKWebView,context:Context) {view.isHidden = !visible}
}
