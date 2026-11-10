import AppKit
import WebKit
import SwiftUI

struct BilibiliCard:Decodable,Identifiable,Equatable {let id:String;let title:String;let poster:String}
struct BilibiliEpisode:Decodable,Identifiable,Equatable {let id:String;let title:String;let number:Int;let current:Bool}
struct BilibiliEpisodeRange:Decodable,Identifiable,Equatable {let id:String;let title:String;let current:Bool}
struct BilibiliQuality:Decodable,Identifiable,Equatable {let id:String;let title:String;let current:Bool;let restricted:Bool}
struct BilibiliSnapshot:Decodable {
    var url="",title="哔哩哔哩",isPlayer=false,cards:[BilibiliCard]=[],episodes:[BilibiliEpisode]=[]
    var ranges:[BilibiliEpisodeRange]=[]
    var qualities:[BilibiliQuality]=[]
    var qualityLabel=""
    var loggedIn:Bool?
    var creator:BilibiliCreator?
    var ended=false,trial=false
    var nextEpisode:BilibiliNextEpisode?
    var hasVideo=false,paused=true,current=0.0,duration=0.0
}

struct CatalogLoadGate {
    private(set) var loading=false
    private(set) var canLoad=true
    mutating func begin()->Bool {guard !loading,canLoad else{return false};loading=true;return true}
    mutating func finish(added:Bool){loading=false;canLoad=added}
    mutating func reset(){loading=false;canLoad=true}
}
enum BilibiliCatalogAction {case search,login,refresh}
enum BilibiliContentTab {case episodes,creator}
enum BilibiliPanel {case none,episodes,search,login,quality}

@MainActor final class BilibiliRemote:ObservableObject {
    @Published var snapshot=BilibiliSnapshot()
    @Published var pagination=CatalogLoadGate()
    @Published var searchDraft=""
    @Published var searchFocus=HomeFocus()
    @Published var catalogKeyword=""
    @Published var loginImage:NSImage?
    @Published var loginNotice="加载二维码…"
    @Published var loginFocus=0
    @Published var loggedIn=false
    @Published var loginChecked=false
    let searchKeys=Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)+["空格","删除","清空","搜索"]
    private var nearCatalogueEnd=false
    private var moreTask:Task<Void,Never>?
    private var loginCapturePending=false
    private var lastLoginCapture=Date.distantPast
    private var loginStarted=Date.distantPast
    let creatorLibrary=BilibiliCreatorLibrary()
    @Published var contentTab:BilibiliContentTab = .episodes
    @Published var contentTabsFocused=false
    @Published var creatorRow:CreatorSection = .videos
    private var contentURL=""
    @Published var panel:BilibiliPanel = .none
    @Published var focus=HomeFocus()
    @Published var qualityIndex=0
    @Published var episodeIndex=0
    @Published var rangeIndex=0
    @Published var rangeFocused=false
    @Published var busy=false
    @Published var toast:String?
    @Published var controlsFocused=false
    @Published var controlIndex=0
    @Published var showPlaybackHUD=true
    @Published var scrubbing=false
    @Published var transitioningPlayer=false
    @Published var nextTransition:BilibiliNextEpisode?
    @Published var transitionBackdrop:NSImage?
    @Published var autoplay=EpisodeCountdown()
    @Published var autoplayFocus=0
    private var autoplayTask:Task<Void,Never>?
    var canAutoplay:(()->Bool)?
    private weak var browser:YouTubeBrowser?
    private var timer:Timer?
    private var pending=false
    private var generation=0
    private var awaitingNavigation=false
    private func beginPlayerTransition(continuous:Bool=false){
        if !continuous {nextTransition=nil;transitionBackdrop=nil}
        generation+=1;pending=false;awaitingNavigation=true;transitioningPlayer=true
        // Hide the native WebKit surface immediately; SwiftUI transitions may still be animating.
        browser?.webView.isHidden=true
    }
    private var active=false
    private var lastURL=""
    private var lastFocusedCard:String?
    private var catalogURL=URL(string:"https://www.bilibili.com/")!
    private var hudTask:Task<Void,Never>?
    private var toastTask:Task<Void,Never>?
    var onHome:(()->Void)?
    var onFullscreen:(()->Void)?
    var onAppMenu:(()->Void)?
    var hasEpisodes:Bool {snapshot.episodes.count>1 && snapshot.episodes.contains(where:{$0.current})}
    var catalogActions:[BilibiliCatalogAction] {loggedIn ? [.search,.refresh]:[.search,.login,.refresh]}
    var rows:[Int] {let n=snapshot.cards.count;return n==0 ? [catalogActions.count] : [catalogActions.count]+stride(from:0,to:n,by:4).map{min(4,n-$0)}}
    var cardIndex:Int {max(0,(focus.row-1)*4+focus.column)}
    func attach(_ browser:YouTubeBrowser){self.browser=browser}
    func start(){guard !active else{return};active=true;refresh();timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task{@MainActor in self?.refresh()}}}
    func stop(){creatorLibrary.suspend();nextTransition=nil;transitionBackdrop=nil;cancelNextEpisode(notify:false);active=false;timer?.invalidate();timer=nil;hudTask?.cancel();moreTask?.cancel();moreTask=nil;pagination.reset();nearCatalogueEnd=false}
    func navigationStarted(){awaitingNavigation=false;cancelNextEpisode(notify:false);if snapshot.isPlayer {transitioningPlayer=true};moreTask?.cancel();moreTask=nil;pagination.reset();nearCatalogueEnd=false;generation+=1;pending=false;busy=true}
    func refresh(){
        guard active,!pending,let browser,let host=browser.webView.url?.host,(host=="www.bilibili.com" || host=="bilibili.com" || host=="search.bilibili.com") else{return}
        pending=true;let token=generation
        browser.webView.evaluateJavaScript("JSON.stringify(window.MacTVBilibili?.snapshot(\(UserDefaults.standard.bool(forKey:"adapterDiagnostics") ? "true":"false")))",in:nil,in:.defaultClient){[weak self] result in
            guard let self else{return};self.pending=false
            guard self.active,token==self.generation else{return}
            switch result {
            case .success(let raw):
                guard let json=raw as? String,let bytes=json.data(using:.utf8),let state=try? JSONDecoder().decode(BilibiliSnapshot.self,from:bytes) else{return}
                if UserDefaults.standard.bool(forKey:"adapterDiagnostics") {
                    let folder=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0].appendingPathComponent("Logs/MacTV Native")
                    try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    var report=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] ?? [:]
                    if let window=browser.webView.window,let view=window.contentView {
                        report["nativeMetrics"]=["windowClass":NSStringFromClass(type(of:window)),"windowFrame":NSStringFromRect(window.frame),"contentFrame":NSStringFromRect(view.frame),"contentBounds":NSStringFromRect(view.bounds),"webFrame":NSStringFromRect(browser.webView.frame),"webBounds":NSStringFromRect(browser.webView.bounds),"screenFrame":NSStringFromRect(window.screen?.frame ?? .zero)]
                    }
                    if let output=try? JSONSerialization.data(withJSONObject:report) {try? output.write(to:folder.appendingPathComponent("bilibili-adapter.json"),options:.atomic)}
                }
                self.accept(state)
            case .failure:break
            }
        }
    }
    private func accept(_ state:BilibiliSnapshot){
        guard !awaitingNavigation else{return}
        updateLoginStatus(state.loggedIn)
        let changed=state.url != lastURL
        if changed {lastURL=state.url;controlsFocused=false;showPlaybackHUD=nextTransition==nil}
        var next=state
        // Keep the catalogue geometry while a reload briefly empties the webpage DOM.
        if !changed && !state.isPlayer && state.cards.isEmpty && !snapshot.cards.isEmpty {next.cards=snapshot.cards}
        if !changed && next.creator==nil {next.creator=snapshot.creator}
        // A transient player rerender must not erase the episode sheet while it is being used.
        if !changed && state.episodes.isEmpty && state.isPlayer {next.episodes=snapshot.episodes}
        if !changed && state.ranges.isEmpty && state.isPlayer {next.ranges=snapshot.ranges}
        snapshot=next;busy=false
        if state.isPlayer {
            let token=generation
            browser?.webView.callAsyncJavaScript("return window.MacTVBilibili?.playerReady()",arguments:[:],in:nil,in:.defaultClient){[weak self] result in
                guard let self,self.generation==token,!self.awaitingNavigation,
                      self.browser?.webView.isLoading==false,
                      Self.samePlayerDocument(self.browser?.webView.url,snapshotURL:state.url) else{return}
                if case .success(let ready)=result,ready as? Bool==true,self.snapshot.hasVideo {
                    let continuous=self.nextTransition != nil
                    withAnimation(.easeOut(duration:0.25)){self.transitioningPlayer=false;self.nextTransition=nil;self.transitionBackdrop=nil}
                    if continuous {self.hidePlaybackControls()}
                }
            }
            if changed {armHUD()}
        } else {
            transitioningPlayer=false
            theatre(false)
            catalogKeyword=URLComponents(string:state.url)?.queryItems?.first(where:{$0.name=="keyword"})?.value ?? ""
            if let url=URL(string:state.url),["www.bilibili.com","bilibili.com","search.bilibili.com"].contains(url.host ?? "") {catalogURL=url}
            if changed {focus=HomeFocus(row:state.cards.isEmpty ? 0 : 1,column:0)}
            if focus.row>0,let old=lastFocusedCard,let index=next.cards.firstIndex(where:{$0.title==old}) {focus=HomeFocus(row:index/4+1,column:index%4)}
            focus.row=min(focus.row,max(0,rows.count-1));focus.column=min(focus.column,max(0,rows[focus.row]-1))
            rememberFocus()
        }
        qualityIndex=min(qualityIndex,max(0,next.qualities.count-1))
        episodeIndex=min(episodeIndex,max(0,next.episodes.count-1))
        updateNextEpisode()
        if panel == .login {captureLogin()}
    }
    static func samePlayerDocument(_ current:URL?,snapshotURL:String)->Bool {
        guard let current,let expected=URL(string:snapshotURL),
              current.host==expected.host,current.path==expected.path else{return false}
        func part(_ url:URL)->String {URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="p"})?.value ?? "1"}
        // The adapter deliberately omits tracking parameters from its snapshot URL.
        return part(current)==part(expected)
    }
    private func rememberFocus(){if focus.row>0,snapshot.cards.indices.contains(cardIndex){lastFocusedCard=snapshot.cards[cardIndex].title}}
    private func theatre(_ enabled:Bool){browser?.webView.evaluateJavaScript("window.MacTVBilibili?.theatre(\(enabled ? "true":"false"))",in:nil,in:.defaultClient,completionHandler:{_ in})}
    func navigate(_ command:RemoteCommand){
        if autoplay.target != nil {
            switch command {
            case .back:cancelNextEpisode();return
            case .left:autoplayFocus=0;return
            case .right:autoplayFocus=1;return
            case .select:if autoplayFocus==0 {playNextEpisodeNow()}else{cancelNextEpisode()};return
            case .volumeUp,.volumeDown,.mute:media(command.rawValue);return
            default:cancelNextEpisode(notify:false)
            }
        }
        if command == .menu && panel == .episodes {contentTabsFocused=true;return}
        if command == .menu {
            if snapshot.isPlayer {
                if panel != .none {if panel == .episodes {creatorLibrary.suspend()};panel = .none;showControlBar()}
                else if controlsFocused {hidePlaybackControls()}
                else {showControlBar()}
            } else {onAppMenu?()}
            return
        }
        if command == .back {back();return}
        if [.volumeUp,.volumeDown,.mute,.playPause].contains(command) {media(command == .playPause ? "toggle":command.rawValue);return}
        if panel == .search {
            if [.up,.down,.left,.right].contains(command){searchFocus.move(command,rows:Array(repeating:8,count:5))}
            if command == .select {pressSearchKey(searchFocus.row*8+searchFocus.column)}
            return
        }
        if panel == .login {
            if command == .left || command == .up {loginFocus=max(0,loginFocus-1)}
            if command == .right || command == .down {loginFocus=min(1,loginFocus+1)}
            if command == .select {if loginFocus==0 {refreshLogin()} else {closeLogin()}}
            return
        }
        if panel == .none && [.skipForward,.skipBackward].contains(command) {media(command.rawValue);return}
        if panel == .quality {
            switch command {
            case .up,.left:qualityIndex=max(0,qualityIndex-1)
            case .down,.right:qualityIndex=min(max(0,snapshot.qualities.count-1),qualityIndex+1)
            case .select:if snapshot.qualities.indices.contains(qualityIndex){chooseQuality(snapshot.qualities[qualityIndex])}
            default:break
            };return
        }
        if panel == .episodes {
            if contentTabsFocused {
                switch command {
                case .left:if hasEpisodes {selectContentTab(.episodes)}
                case .right:if snapshot.creator?.url != nil {selectContentTab(.creator)}
                case .down,.select:contentTabsFocused=false
                default:break
                };return
            }
            if contentTab == .creator {
                switch command {
                case .up:if creatorRow == .collections && !creatorLibrary.displayedState.videos.isEmpty {creatorRow = .videos}else{contentTabsFocused=true}
                case .down:if creatorLibrary.hasCollectionRow {creatorRow = .collections}
                case .left,.right:
                    if creatorRow == .collections {creatorLibrary.moveCollection(command == .left ? -1:1)}
                    else {creatorLibrary.moveVideo(command == .left ? -1:1)}
                case .select:
                    if creatorRow == .collections {if !creatorLibrary.displayedState.videos.isEmpty {creatorRow = .videos}}
                    else {
                        let state=creatorLibrary.displayedState
                        if state.videos.indices.contains(state.index){playCreatorVideo(state.videos[state.index])}else{creatorLibrary.retry()}
                    }
                default:break
                };return
            }
            if command == .up && episodeIndex<8 && snapshot.creator?.url != nil && snapshot.ranges.isEmpty {contentTabsFocused=true;return}
            if rangeFocused {
                switch command {
                case .left:rangeIndex=max(0,rangeIndex-1)
                case .right:rangeIndex=min(max(0,snapshot.ranges.count-1),rangeIndex+1)
                case .down:rangeFocused=false;episodeIndex=0
                case .select:if snapshot.ranges.indices.contains(rangeIndex){episodeIndex=0;activate(snapshot.ranges[rangeIndex].id,keepPanel:true)}
                default:break
                };return
            }
            if command == .up && episodeIndex<8 && !snapshot.ranges.isEmpty {rangeFocused=true;return}
            let n=snapshot.episodes.count
            switch command {case .left:episodeIndex=max(0,episodeIndex-1);case .right:episodeIndex=min(max(0,n-1),episodeIndex+1);case .up:episodeIndex=max(0,episodeIndex-8);case .down:episodeIndex=min(max(0,n-1),episodeIndex+8);case .select:if snapshot.episodes.indices.contains(episodeIndex){activate(snapshot.episodes[episodeIndex].id)};default:break};return
        }
        if snapshot.isPlayer {
            if controlsFocused {
                switch command {
                case .left:controlIndex=max(0,controlIndex-1)
                case .right:controlIndex=min(1,controlIndex+1)
                case .select:performControl(controlIndex)
                case .down:openEpisodes()
                default:break
                };return
            }
            switch command {
            case .select:media("toggle")
            case .left:media("left")
            case .right:media("right")
            case .down:openEpisodes()
            case .up:showControlBar()
            default:break
            };return
        }
        if [.up,.down,.left,.right].contains(command) {if focus.row>0 && (command == .left || command == .right) {
                let next=min(max(0,snapshot.cards.count-1),max(0,cardIndex+(command == .right ? 1:-1)))
                focus=HomeFocus(row:next/4+1,column:next%4)
            } else {focus.move(command,rows:rows)}
            rememberFocus();if focus.row>0 && snapshot.cards.count-cardIndex<=8 {loadMore()}}
        if command == .select {
            if focus.row==0,catalogActions.indices.contains(focus.column) {switch catalogActions[focus.column] {case .search:openSearch();case .login:openLogin();case .refresh:reload()}}
            else if snapshot.cards.indices.contains(cardIndex){activate(snapshot.cards[cardIndex].id)}
        }
    }
    func back(){
        if autoplay.target != nil {cancelNextEpisode();return}
        if panel == .login {closeLogin();return}
        if panel != .none {if panel == .episodes {creatorLibrary.suspend()};panel = .none;loginImage=nil;if snapshot.isPlayer {showPlaybackHUD=true;armHUD()};browser?.webView.window?.makeFirstResponder(browser?.webView);return}
        if snapshot.isPlayer {
            if showPlaybackHUD || controlsFocused || scrubbing {hidePlaybackControls();return}
            beginPlayerTransition();controlsFocused=false;media("pause");hidePlaybackControls()
            if let entry=browser?.webView.backForwardList.backList.reversed().first(where:{item in
                ["www.bilibili.com","bilibili.com","search.bilibili.com"].contains(item.url.host ?? "") && !item.url.path.contains("/video/") && !item.url.path.contains("/bangumi/play/")
            }) {browser?.webView.go(to:entry)}
            else {browser?.webView.load(URLRequest(url:catalogURL))}
        } else if !catalogKeyword.isEmpty {browser?.loadHome()}
        else {onHome?()}
    }
    func showControlBar(){controlsFocused=true;controlIndex=0;showPlaybackHUD=true;hudTask?.cancel()}
    func hidePlaybackControls(){hudTask?.cancel();controlsFocused=false;scrubbing=false;showPlaybackHUD=false}
    func performControl(_ index:Int){
        controlIndex=index
        switch index {case 0:openQuality();case 1:onFullscreen?();default:break}
    }
    func openEpisodes(){
        guard snapshot.isPlayer,hasEpisodes || snapshot.creator?.url != nil else{message("正在读取当前内容信息，请稍后重试");refresh();return}
        if contentURL != snapshot.url {contentURL=snapshot.url;contentTab=hasEpisodes ? .episodes:.creator;creatorRow = .videos}
        if !hasEpisodes {contentTab = .creator}
        panel = .episodes;contentTabsFocused=false;rangeFocused=false
        rangeIndex=snapshot.ranges.firstIndex(where:{$0.current}) ?? 0;episodeIndex=snapshot.episodes.firstIndex(where:{$0.current}) ?? 0
        if contentTab == .creator,let creator=snapshot.creator {creatorLibrary.open(creator)}
        refresh()
    }
    func selectContentTab(_ tab:BilibiliContentTab){
        contentTab=tab;contentTabsFocused=true
        if tab == .creator,let creator=snapshot.creator {creatorLibrary.open(creator)}
    }
    func playCreatorVideo(_ video:BilibiliCreatorVideo){
        guard !busy,let url=video.url else{return}
        cancelNextEpisode(notify:false);creatorLibrary.suspend();busy=true;beginPlayerTransition();panel = .none;hidePlaybackControls()
        browser?.webView.load(URLRequest(url:url))
    }
    func openQuality(){
        guard snapshot.isPlayer else{message("请先播放视频，再选择清晰度");return}
        panel = .quality;qualityIndex=snapshot.qualities.firstIndex(where:{$0.current}) ?? 0
        browser?.webView.evaluateJavaScript("window.MacTVBilibili?.prepareQuality()",in:nil,in:.defaultClient,completionHandler:{[weak self] _ in self?.refresh()})
    }
    func chooseQuality(_ quality:BilibiliQuality){
        guard let browser else{return}
        qualityIndex=snapshot.qualities.firstIndex(where:{$0.id==quality.id}) ?? qualityIndex
        browser.webView.callAsyncJavaScript("return window.MacTVBilibili?.chooseQuality(id)",arguments:["id":quality.id],in:nil,in:.defaultClient){[weak self] result in
            guard let self else{return}
            if case .success(let value)=result,let response=value as? [String:Any],response["ok"] as? Bool==true {
                // The selected quality is reflected by the official player snapshot.
            } else {self.message("清晰度列表已更新，请重新选择")}
            self.refresh()
        }
    }
    func reload(){busy=true;browser?.webView.reload()}
    func catalogueEndVisible(_ visible:Bool){nearCatalogueEnd=visible;if visible {loadMore()}}
    func loadMore(){
        guard active,!snapshot.isPlayer,panel == .none,!snapshot.cards.isEmpty,let browser,pagination.begin() else{return}
        let count=snapshot.cards.count,token=generation
        moreTask=Task{[weak self] in
            guard let self else{return}
            for _ in 0..<4 {
                guard !Task.isCancelled,self.active,self.generation==token else{return}
                _ = try? await browser.webView.evaluateJavaScript("window.MacTVBilibili?.more()",in:nil,in:.defaultClient)
                try? await Task.sleep(for:.milliseconds(1100))
                guard !Task.isCancelled,self.active,self.generation==token else{return}
                self.refresh()
                if self.snapshot.cards.count>count {break}
            }
            guard !Task.isCancelled,self.generation==token else{return}
            let added=self.snapshot.cards.count>count
            self.pagination.finish(added:added);self.moreTask=nil
            if added && self.nearCatalogueEnd {self.loadMore()}
        }
    }
    func openSearch(){moreTask?.cancel();moreTask=nil;pagination.reset();panel = .search;searchDraft=catalogKeyword;searchFocus=HomeFocus();browser?.webView.window?.makeFirstResponder(nil)}
    func pressSearchKey(_ index:Int){
        guard searchKeys.indices.contains(index) else{return}
        switch searchKeys[index] {
        case "空格":searchDraft+=" "
        case "删除":if !searchDraft.isEmpty {searchDraft.removeLast()}
        case "清空":searchDraft=""
        case "搜索":submitSearch()
        default:searchDraft+=searchKeys[index]
        }
    }
    func submitSearch(){
        let query=searchDraft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else{message("请输入片名或关键词");return}
        var components=URLComponents(string:"https://search.bilibili.com/all")!
        components.queryItems=[URLQueryItem(name:"keyword",value:query)]
        guard let url=components.url else{return}
        panel = .none;focus=HomeFocus(row:1,column:0)
        browser?.webView.window?.makeFirstResponder(nil);browser?.webView.load(URLRequest(url:url))
    }
    func closeLogin(){panel = .none;loginImage=nil;browser?.webView.evaluateJavaScript("window.MacTVBilibili?.closeLogin()",in:nil,in:.defaultClient,completionHandler:{_ in})}
    func updateLoginStatus(_ status:Bool?){
        guard let status else{return}
        loggedIn=status;loginChecked=true
    }
    func openLogin(){
        if loginChecked && loggedIn {return}
        moreTask?.cancel();moreTask=nil;pagination.reset()
        panel = .login;loginImage=nil;loginFocus=0
        loginStarted=Date();lastLoginCapture = .distantPast;loginNotice="加载二维码…"
        theatre(false);browser?.webView.window?.makeFirstResponder(nil)
        browser?.webView.evaluateJavaScript("window.MacTVBilibili?.showLogin()",in:nil,in:.defaultClient,completionHandler:{_ in})
        captureLogin()
    }
    func refreshLogin(){loginImage=nil;loginStarted=Date();lastLoginCapture = .distantPast;loginNotice="加载二维码…";browser?.webView.reload()}
    private func captureLogin(){
        guard panel == .login,!loginCapturePending,Date().timeIntervalSince(lastLoginCapture)>1.5,let browser else{return}
        loginCapturePending=true;lastLoginCapture=Date()
        browser.webView.evaluateJavaScript("window.MacTVBilibili?.loginInfo()",in:nil,in:.defaultClient){[weak self] result in
            guard let self else{return}
            guard self.panel == .login else{self.loginCapturePending=false;return}
            guard case .success(let raw)=result,let info=raw as? [String:Any] else{self.loginCapturePending=false;return}
            if info["loggedIn"] as? Bool==true {self.updateLoginStatus(true);self.panel = .none;self.loginImage=nil;self.loginCapturePending=false;self.message("登录成功");return}
            guard let x=info["x"] as? Double,let y=info["y"] as? Double,let w=info["width"] as? Double,let h=info["height"] as? Double,w>100,h>100 else {
                self.loginCapturePending=false
                if Date().timeIntervalSince(self.loginStarted)>15 {self.loginNotice="二维码加载失败"}
                else {browser.webView.evaluateJavaScript("window.MacTVBilibili?.showLogin()",in:nil,in:.defaultClient,completionHandler:{_ in})}
                return
            }
            let config=WKSnapshotConfiguration();config.rect=CGRect(x:x,y:y,width:w,height:h).intersection(browser.webView.bounds);config.snapshotWidth=760
            browser.webView.takeSnapshot(with:config){[weak self] image,_ in
                guard let self else{return};self.loginCapturePending=false
                guard self.panel == .login else{return}
                if let image {self.loginImage=image;self.loginNotice=""}
            }
        }
    }
    func activate(_ id:String,keepPanel:Bool=false){
        guard !busy else{return};cancelNextEpisode(notify:false);busy=true;beginPlayerTransition()
        if let index=snapshot.cards.firstIndex(where:{$0.id==id}) {focus=HomeFocus(row:index/4+1,column:index%4);rememberFocus()}
        let arg=String(data:try! JSONEncoder().encode(id),encoding:.utf8)!
        browser?.webView.evaluateJavaScript("window.MacTVBilibili?.activate(\(arg))",in:nil,in:.defaultClient){[weak self] result in
            guard let self else{return}
            self.busy=false
            if case .success(let value)=result,value as? Bool==true {if !keepPanel {self.panel = .none};self.showPlaybackHUD=true;self.armHUD()}
            else {self.awaitingNavigation=false;self.transitioningPlayer=false;self.message("片单已更新，请刷新后再选择");self.refresh()}
        }
    }
    func media(_ action:String,position:Double=0){
        if ["toggle","play","seek","left","right","skipForward","skipBackward"].contains(action){cancelNextEpisode(notify:false)}
        browser?.webView.callAsyncJavaScript("return await window.MacTVBilibili?.media(action,position)",arguments:["action":action,"position":position],in:nil,in:.defaultClient){[weak self] result in
            guard let self else{return}
            if case .success(let value)=result,let state=value as? [String:Any] {
                if state["ok"] as? Bool==false {self.message(state["message"] as? String ?? "操作暂不可用")}
                else {
                    if let current=state["current"] as? Double,current.isFinite {self.snapshot.current=max(0,current)}
                    if let duration=state["duration"] as? Double,duration.isFinite {self.snapshot.duration=max(0,duration)}
                    if let paused=state["paused"] as? Bool {self.snapshot.paused=paused}
                }
            }
            self.refresh()
        }
        showPlaybackHUD=true;armHUD()
    }
    private func updateNextEpisode(){
        let previous=autoplay.target
        let eligible=active && snapshot.isPlayer && !snapshot.trial && panel == .none && (canAutoplay?() ?? true)
        autoplay.observe(key:snapshot.url,ended:snapshot.ended,rewound:snapshot.duration>0 && snapshot.current<snapshot.duration-2,eligible:eligible,next:snapshot.nextEpisode,now:ProcessInfo.processInfo.systemUptime)
        if autoplay.target != nil && previous==nil {
            hidePlaybackControls();autoplayFocus=0
            autoplayTask?.cancel()
            autoplayTask=Task{[weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(200))
                    guard !Task.isCancelled,let self else{return}
                    guard self.active,self.canAutoplay?() ?? true,self.snapshot.ended,!self.snapshot.trial,self.panel == .none else{self.cancelNextEpisode(notify:false);return}
                    if let target=self.autoplay.tick(now:ProcessInfo.processInfo.systemUptime){self.autoplayTask=nil;self.advanceNextEpisode(target);return}
                }
            }
        } else if autoplay.target==nil {autoplayTask?.cancel();autoplayTask=nil}
    }
    func cancelNextEpisode(notify:Bool=true){
        let showing=autoplay.target != nil
        autoplayTask?.cancel();autoplayTask=nil;autoplay.cancel()
        if showing {showPlaybackHUD=true;armHUD();if notify {message("已取消连播")}}
    }
    func playNextEpisodeNow(){
        guard let target=autoplay.target else{return}
        cancelNextEpisode(notify:false);advanceNextEpisode(target)
    }
    private func advanceNextEpisode(_ target:BilibiliNextEpisode){
        guard active,snapshot.ended,!snapshot.trial,snapshot.nextEpisode==target,target.validURL != nil,canAutoplay?() ?? true,let browser else{return}
        busy=true;hidePlaybackControls();nextTransition=target
        let token=generation
        // Capture the cinema surface before navigating so the completed episode's
        // final frame can bridge the network load without exposing the webpage.
        let config=WKSnapshotConfiguration();config.rect=browser.webView.bounds
        config.snapshotWidth=NSNumber(value:Double(min(1920,browser.webView.bounds.width)))
        browser.webView.takeSnapshot(with:config){[weak self] image,_ in
            guard let self,self.active,self.generation==token,self.nextTransition==target else{return}
            self.transitionBackdrop=image;self.beginPlayerTransition(continuous:true)
            browser.webView.callAsyncJavaScript("return window.MacTVBilibili?.advanceNext(url)",arguments:["url":target.url],in:nil,in:.defaultClient){[weak self] result in
                guard let self else{return};self.busy=false
                if case .success(let raw)=result,raw as? Bool==true {return}
                self.awaitingNavigation=false;self.transitioningPlayer=false;self.nextTransition=nil;self.transitionBackdrop=nil
                self.showPlaybackHUD=true;self.message("下一集信息已变化，请从选集中选择")
            }
        }
    }

    func armHUD(){hudTask?.cancel();hudTask=Task{try? await Task.sleep(for:.seconds(4));if !Task.isCancelled && !snapshot.paused && !scrubbing && !controlsFocused && panel == .none {showPlaybackHUD=false}}}
    func message(_ text:String){toastTask?.cancel();toast=text;toastTask=Task{try? await Task.sleep(for:.seconds(4));if !Task.isCancelled {toast=nil}}}
}
