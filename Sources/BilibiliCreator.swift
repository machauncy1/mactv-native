import AppKit
import WebKit

struct BilibiliCreator:Decodable,Equatable {
    let id:String
    let name:String
    let avatar:String
    var url:URL? {guard id.range(of:"^[0-9]{1,20}$",options:.regularExpression) != nil else{return nil};return URL(string:"https://space.bilibili.com/\(id)/upload/video")}
}
struct BilibiliCreatorVideo:Decodable,Identifiable,Equatable {
    let id:String
    let title:String
    let poster:String
    let duration:String
    var url:URL? {guard let url=URL(string:id),url.scheme=="https",url.host=="www.bilibili.com",url.user==nil,url.password==nil,url.port==nil,url.path.range(of:"^/video/BV[A-Za-z0-9]+/?$",options:.regularExpression) != nil else{return nil};return url}
    var card:BilibiliCard {BilibiliCard(id:id,title:title,poster:poster)}
}
struct BilibiliCreatorCollection:Decodable,Identifiable,Equatable {
    let id:String
    let title:String
    let poster:String
    let detail:String
    var count:Int? = nil
    var card:BilibiliCard {BilibiliCard(id:id,title:title,poster:poster)}
}
struct CreatorBrowseState {
    var videos:[BilibiliCreatorVideo]=[]
    var collections:[BilibiliCreatorCollection]=[]
    var index=0
    var canLoad=true
    var empty=false
    mutating func merge(_ incoming:[BilibiliCreatorVideo])->Int {
        var seen=Set(videos.map(\.id));let additions=incoming.filter{$0.url != nil && seen.insert($0.id).inserted}
        videos.append(contentsOf:additions);if !videos.isEmpty {empty=false};return additions.count
    }
    mutating func mergeCollections(_ incoming:[BilibiliCreatorCollection])->Int {
        var seen=Set(collections.map(\.id));let additions=incoming.filter{seen.insert($0.id).inserted}
        collections.append(contentsOf:additions);return additions.count
    }
    mutating func move(_ delta:Int,count:Int?=nil){index=min(max(0,(count ?? videos.count)-1),max(0,index+delta))}
}
enum CreatorSection {case videos,collections}
struct CreatorCollectionFocus {
    private(set) var index = -1 // Latest videos is the first tab.
    mutating func select(_ value:Int,count:Int){index=min(max(-1,count-1),max(-1,value))}
    func neighbors(count:Int)->[Int] {(index == -1 ? [0,1]:[index+1,index-1]).filter{$0>=0 && $0<count}}
}


@MainActor final class BilibiliCreatorLibrary:NSObject,ObservableObject,WKNavigationDelegate {
    @Published private(set) var creator:BilibiliCreator?
    @Published private(set) var state=CreatorBrowseState()
    @Published private(set) var section:CreatorSection = .videos
    @Published private(set) var selectedCollection:BilibiliCreatorCollection?
    @Published private(set) var collectionFocus=CreatorCollectionFocus()
    @Published private(set) var collectionsChecked=false
    @Published private(set) var loading=false
    @Published private(set) var failure:String?
    @Published private(set) var webView:WKWebView?
    @Published private(set) var preloader:BilibiliCreatorLibrary?
    private let allowsPrefetch:Bool
    private var preloadTask:Task<Void,Never>?
    @Published private var cache:[String:CreatorBrowseState]=[:]
    private var prefetchedCollections=false
    private var task:Task<Void,Never>?
    private var revision=0
    private var preparedRoute=""
    init(allowsPrefetch:Bool=true){self.allowsPrefetch=allowsPrefetch;super.init()}
    private var route:String {(creator?.id ?? "")+":"+(section == .videos ? "videos":selectedCollection.map{"collection:"+$0.id} ?? "collections")}
    var videoState:CreatorBrowseState {section == .videos ? state:cache[(creator?.id ?? "")+":videos"] ?? CreatorBrowseState()}
    var collectionListState:CreatorBrowseState {section == .collections && selectedCollection==nil ? state:cache[(creator?.id ?? "")+":collections"] ?? CreatorBrowseState()}
    var displayedState:CreatorBrowseState {selectedCollection==nil ? videoState:state}
    var hasCollectionRow:Bool {!collectionListState.collections.isEmpty || !collectionsChecked}
    var showingCollections:Bool {section == .collections && selectedCollection==nil}
    var count:Int {showingCollections ? state.collections.count:state.videos.count}
    func open(_ value:BilibiliCreator){
        guard value.url != nil else{return}
        if creator?.id==value.id {if count==0 && !loading {loadMore()};return}
        save();invalidate();creator=value;collectionFocus=CreatorCollectionFocus();collectionsChecked=false;prefetchedCollections=false;section = .videos;selectedCollection=nil;state=cache[route] ?? CreatorBrowseState();preparedRoute=""
        if count==0 {loadMore()}else{prefetchAdjacent()}
    }
    func chooseSection(_ value:CreatorSection){
        if value == .videos {collectionFocus.select(-1,count:collectionListState.collections.count)}
        if section==value && selectedCollection==nil {return}
        save();invalidate();section=value;selectedCollection=nil;state=cache[route] ?? CreatorBrowseState();preparedRoute=""
        if count==0 {loadMore()}else{prefetchAdjacent()}
    }
    func selectCollection(_ index:Int){
        let entries=collectionListState.collections
        var next=collectionFocus;next.select(index,count:entries.count)
        if next.index==collectionFocus.index && (next.index == -1 || selectedCollection?.id==entries[next.index].id) {return}
        collectionFocus=next
        if next.index == -1 {chooseSection(.videos);return}
        let value=entries[next.index]
        save();invalidate();selectedCollection=value;section = .collections;state=cache[route] ?? CreatorBrowseState();preparedRoute=""
        if value.count==0 {state=CreatorBrowseState();state.empty=true;state.canLoad=false;cache[route]=state;prefetchAdjacent();return}
        if state.empty {prefetchAdjacent();return}
        // Keep the tabs responsive, cancel superseded work, and request only the resting selection.
        if state.videos.isEmpty {
            loading=true;let token=revision
            task=Task{[weak self] in
                try? await Task.sleep(for:.milliseconds(220))
                guard !Task.isCancelled,let self,self.revision==token else{return}
                self.loading=false;self.loadMore()
            }
        }else{prefetchAdjacent()}
    }
    func moveCollection(_ delta:Int){selectCollection(collectionFocus.index+delta)}
    func moveVideo(_ delta:Int){if selectedCollection==nil {chooseSection(.videos)};move(delta)}
    func focusVideo(_ index:Int){if selectedCollection==nil {chooseSection(.videos)};focus(index)}
    func move(_ delta:Int){state.move(delta,count:count);if count-state.index<=4 {loadMore()}}
    func focus(_ index:Int){guard index>=0,index<count else{return};state.index=index}
    func retry(){failure=nil;state.canLoad=true;preparedRoute="";loadMore()}
    private func save(){if creator != nil {cache[route]=state;trimCache()}}
    private func trimCache(){
        let protected=[route,(creator?.id ?? "")+":videos",(creator?.id ?? "")+":collections"]
        while cache.count>12,let key=cache.keys.sorted().first(where:{!protected.contains($0)}) {cache.removeValue(forKey:key)}
    }
    private func cancelPreloading(){preloadTask?.cancel();preloadTask=nil;preloader?.suspend();preloader=nil}
    private func invalidate(){task?.cancel();task=nil;cancelPreloading();webView?.stopLoading();revision+=1;loading=false;failure=nil}
    private func prefetchAdjacent(){
        guard allowsPrefetch,!loading,let creator else{return}
        let entries=collectionListState.collections
        let targets=collectionFocus.neighbors(count:entries.count).map{entries[$0]}.filter{$0.count != 0 && cache[creator.id+":collection:"+$0.id]?.videos.isEmpty != false}
        cancelPreloading()
        guard !targets.isEmpty else{return}
        let current=route
        preloadTask=Task{[weak self] in
            try? await Task.sleep(for:.milliseconds(250))
            for entry in targets.prefix(2) {
                guard !Task.isCancelled,let self,self.route==current else{return}
                let worker=BilibiliCreatorLibrary(allowsPrefetch:false)
                worker.creator=creator;worker.section = .collections;worker.selectedCollection=entry
                self.preloader=worker;worker.loadMore()
                for _ in 0..<55 {
                    try? await Task.sleep(for:.milliseconds(400))
                    if Task.isCancelled || !worker.loading {break}
                }
                guard !Task.isCancelled,self.route==current else{worker.suspend();return}
                if !worker.state.videos.isEmpty {
                    var firstPage=worker.state;firstPage.videos=Array(firstPage.videos.prefix(12));firstPage.index=0;firstPage.canLoad=true
                    self.cache[creator.id+":collection:"+entry.id]=firstPage;self.trimCache()
                    for video in firstPage.videos.prefix(6) {
                        guard !Task.isCancelled else{worker.suspend();return}
                        _ = await BilibiliCoverCache.fetch(video.poster)
                    }
                }
                worker.suspend();if self.preloader === worker {self.preloader=nil}
            }
        }
    }
    func suspend(){save();invalidate()}
    func loadMore(){
        guard !loading,state.canLoad,let creator,let videoURL=creator.url else{return}
        if webView==nil {
            let config=WKWebViewConfiguration();config.websiteDataStore = .default();config.mediaTypesRequiringUserActionForPlayback = .all
            let view=WKWebView(frame:NSRect(x:0,y:0,width:1440,height:1000),configuration:config)
            view.navigationDelegate=self
            view.customUserAgent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            webView=view
        }
        guard let view=webView,let resource=Bundle.main.resourceURL?.appendingPathComponent("Bilibili/creator.js"),let script=try? String(contentsOf:resource,encoding:.utf8) else{return}
        loading=true;failure=nil;let token=revision,key=route,collection=selectedCollection,listMode=showingCollections
        let first=preparedRoute != key
        if first {preparedRoute=key;view.load(URLRequest(url:section == .videos ? videoURL:URL(string:"https://space.bilibili.com/\(creator.id)/lists")!))}
        task=Task{[weak self] in
            guard let self else{return}
            if !first {_ = try? await Self.evaluate(view,script+"\nreturn window.MacTVCreator?.more()",arguments:[:])}
            var growth=0,stable=0,opened=false,resumedPage=false
            let deadline=ContinuousClock.now.advanced(by:.seconds(12))
            for _ in 0..<35 {
                try? await Task.sleep(for:.milliseconds(600))
                guard !Task.isCancelled,self.revision==token else{return}
                if ContinuousClock.now>=deadline {break}
                if UserDefaults.standard.bool(forKey:"adapterDiagnostics") {
                    let folder=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0].appendingPathComponent("Logs/MacTV Native")
                    try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    if let data=try? JSONSerialization.data(withJSONObject:["url":view.url?.absoluteString ?? "nil","loading":String(view.isLoading),"title":view.title ?? ""]){try? data.write(to:folder.appendingPathComponent("creator-navigation.json"),options:.atomic)}
                }
                guard view.url?.host=="space.bilibili.com",view.url?.path.split(separator:"/").first.map(String.init)==creator.id else{continue}
                if first && view.isLoading {continue}
                if let collection,first,!opened {
                    let result=try? await Self.evaluate(view,script+"\nreturn window.MacTVCreator?.openCollection(title)",arguments:["title":collection.id])
                    if result as? Bool==true {opened=true};continue
                }
                if collection != nil,first,view.url?.path.range(of:"/lists/[0-9]+",options:.regularExpression)==nil {continue}
                if let raw=try? await Self.evaluate(view,script+"\nreturn JSON.stringify(window.MacTVCreator?.read())",arguments:[:]),let json=raw as? String,let data=json.data(using:.utf8),let result=try? JSONDecoder().decode(CreatorPage.self,from:data){
                    guard !Task.isCancelled,self.revision==token else{return}
                    let added=listMode ? self.state.mergeCollections(result.collections):self.state.merge(result.videos);growth+=added
                    if result.empty==true {self.state.empty=true;self.state.canLoad=false;break}
                    if added>0 {stable=0}else{stable+=1}
                    if UserDefaults.standard.bool(forKey:"adapterDiagnostics") {
                        let folder=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0].appendingPathComponent("Logs/MacTV Native")
                        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                        try? data.write(to:folder.appendingPathComponent("creator-page.json"),options:.atomic)
                    }
                    if first,growth==0,stable>=2,self.count>0,!resumedPage,!result.finished {
                        resumedPage=true;stable=0
                        _ = try? await Self.evaluate(view,script+"\nreturn window.MacTVCreator?.more()",arguments:[:]);continue
                    }
                    if !self.allowsPrefetch && growth>0 {break}
                    if growth>0 && stable>=2 {break}
                    if result.blocked {self.failure="官方页面暂时无法提供作品，请稍后重试。";break}
                    if result.finished && (self.count>0 || listMode) {self.state.canLoad=false;break}
                }
            }
            guard !Task.isCancelled,self.revision==token else{return}
            self.loading=false;self.task=nil
            if listMode {self.collectionsChecked=true}
            if self.count==0 && !self.state.empty && self.failure==nil {self.failure=listMode ? "暂未读取到合集或系列。":"暂未读取到作品，请稍后重试。"}
            else if !first && growth==0 && self.failure==nil {self.state.canLoad=false}
            self.cache[key]=self.state;self.trimCache()
            if self.allowsPrefetch,self.section == .videos,!self.prefetchedCollections,self.count>0 {
                self.prefetchedCollections=true;self.chooseSection(.collections)
            }else{self.prefetchAdjacent()}
        }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        guard let url=navigationAction.request.url,["space.bilibili.com","passport.bilibili.com"].contains(url.host ?? ""),url.scheme=="https" else{decisionHandler(.cancel);return}
        decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){if (error as NSError).code != NSURLErrorCancelled {failure="UP 主作品暂时无法加载，请重试。"}}
    private static func evaluate(_ view:WKWebView,_ script:String,arguments:[String:Any]) async throws -> Any {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Any,Error>) in
            var completed=false
            let timeout=Task { @MainActor in
                try? await Task.sleep(for:.seconds(3))
                guard !Task.isCancelled,!completed else{return}
                completed=true;continuation.resume(throwing:URLError(.timedOut))
            }
            view.callAsyncJavaScript(script,arguments:arguments,in:nil,in:.defaultClient){result in
                guard !completed else{return};completed=true;timeout.cancel();continuation.resume(with:result)
            }
        }
    }
    private struct CreatorPage:Decodable {let videos:[BilibiliCreatorVideo];let collections:[BilibiliCreatorCollection];let blocked:Bool;let finished:Bool;let empty:Bool?}
}
