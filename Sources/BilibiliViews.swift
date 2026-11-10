import SwiftUI

struct BilibiliScreen:View {
    @Environment(\.tvScale) private var scale
    @ObservedObject var app:AppModel
    @ObservedObject var browser:YouTubeBrowser
    @ObservedObject var tv:BilibiliRemote
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var motion:Bool {app.reducedMotion || systemReduceMotion}
    var body:some View {
        ZStack {
            BilibiliCreatorBackground(library:tv.creatorLibrary).allowsHitTesting(false).accessibilityHidden(true).ignoresSafeArea()
            Color.black.ignoresSafeArea()
            EmbeddedYouTube(browser:browser,visible:(tv.snapshot.isPlayer && !tv.transitioningPlayer)).ignoresSafeArea().accessibilityHidden(!tv.snapshot.isPlayer)
            if !tv.snapshot.isPlayer {catalog.transition(TVDesign.pageTransition(reduced:motion))}
            if tv.transitioningPlayer {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let image=tv.transitionBackdrop {Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity).ignoresSafeArea();Color.black.opacity(0.12).ignoresSafeArea()}
                    if let failure=browser.failure {VStack(spacing:20){Text(failure);Button("重试"){tv.reload()}.buttonStyle(TVActionStyle())}.padding(32*scale).modifier(TVSurface())}
                    else if tv.nextTransition==nil {VStack{Spacer();HStack{Text("载入中").font(.system(size:18*scale,weight:.medium)).foregroundStyle(.white.opacity(0.6));Spacer()}}.padding(54*scale)}
                }.frame(maxWidth:.infinity,maxHeight:.infinity).transition(.opacity)
            }
            if tv.snapshot.isPlayer && !tv.transitioningPlayer && tv.nextTransition==nil && (tv.showPlaybackHUD || tv.scrubbing) && tv.panel == .none && tv.autoplay.target == nil {
                TVPlaybackPanel(title:tv.snapshot.title,playing:!tv.snapshot.paused,position:Binding(get:{tv.snapshot.current},set:{tv.media("seek",position:$0)}),duration:tv.snapshot.duration,editing:{editing in tv.scrubbing=editing;tv.armHUD()}){
                    HStack(spacing:12*scale){ForEach(Array([tv.snapshot.qualityLabel.isEmpty ? "清晰度":tv.snapshot.qualityLabel,"全屏"].enumerated()),id:\.offset){i,title in
                        Button{tv.controlsFocused=true;tv.performControl(i)}label:{Text(title).lineLimit(1)}.buttonStyle(TVActionStyle(focused:tv.controlsFocused && tv.controlIndex==i,reducedMotion:motion))
                    }}
                }.transition(TVDesign.sheetTransition(reduced:motion))
            }
            if tv.panel == .search {searchPanel.transition(TVDesign.sheetTransition(reduced:motion))}
            if tv.panel == .login {loginPanel.transition(TVDesign.sheetTransition(reduced:motion))}
            if tv.panel == .quality {qualityPanel.transition(TVDesign.sheetTransition(reduced:motion))}
            if tv.panel == .episodes {episodes.transition(TVDesign.sheetTransition(reduced:motion))}
            if let target=tv.nextTransition ?? tv.autoplay.target {nextEpisode(target).transition(TVDesign.sheetTransition(reduced:motion))}
            if let toast=tv.toast {VStack{Spacer();Text(toast).font(.system(size:17*scale)).padding(20).background(.regularMaterial,in:Capsule()).padding(.bottom,32)}}
        }
        .onAppear{tv.start()}.onDisappear{tv.stop()}
        .animation(motion ? nil : TVDesign.navigation,value:tv.snapshot.isPlayer)
        .animation(motion ? nil : TVDesign.navigation,value:(tv.nextTransition ?? tv.autoplay.target) != nil)
        .animation(motion ? nil : TVDesign.navigation,value:tv.panel)
        .animation(motion ? nil : TVDesign.navigation,value:tv.showPlaybackHUD)
    }
    private func nextEpisode(_ target:BilibiliNextEpisode)->some View {
        VStack{Spacer();HStack{Spacer()
            VStack(alignment:.leading,spacing:18*scale){
                HStack {
                    Text(tv.nextTransition==nil ? "下一集":"载入中").font(.system(size:15*scale,weight:.semibold)).foregroundStyle(.white.opacity(0.65));Spacer()
                    ZStack {
                        Circle().stroke(.white.opacity(0.15),lineWidth:3*scale)
                        Circle().trim(from:0,to:CGFloat(tv.autoplay.remaining)/10).stroke(.white,style:StrokeStyle(lineWidth:3*scale,lineCap:.round)).rotationEffect(.degrees(-90))
                            .animation(motion ? nil:.linear(duration:0.8),value:tv.autoplay.remaining)
                        Text(String(tv.autoplay.remaining)).font(.system(size:20*scale,weight:.semibold,design:.rounded)).monospacedDigit()
                    }.frame(width:48*scale,height:48*scale).opacity(tv.nextTransition==nil ? 1:0).accessibilityHidden(tv.nextTransition != nil).accessibilityLabel("还有 \(tv.autoplay.remaining) 秒")
                }
                Text(target.title).font(.system(size:24*scale,weight:.semibold)).lineLimit(2)
                HStack(spacing:12*scale){
                    Button("立即播放"){tv.playNextEpisodeNow()}.buttonStyle(TVActionStyle(focused:tv.autoplayFocus==0,reducedMotion:motion))
                    Button("取消"){tv.cancelNextEpisode()}.buttonStyle(TVActionStyle(focused:tv.autoplayFocus==1,reducedMotion:motion))
                }.opacity(tv.nextTransition==nil ? 1:0).allowsHitTesting(tv.nextTransition==nil).accessibilityHidden(tv.nextTransition != nil)
            }.frame(width:390*scale,alignment:.leading).padding(26*scale).modifier(TVSurface())
        }}.padding(.horizontal,54*scale).padding(.bottom,38*scale)
    }
    private var catalog:some View {
        ZStack {
            AmbientBackground(accent:.pink)
            GeometryReader{viewport in
                ScrollViewReader{proxy in
                    ScrollView {
                        VStack(alignment:.leading,spacing:24*scale){
                            HStack {
                                VStack(alignment:.leading,spacing:8){Text("哔哩哔哩").font(.system(size:36*scale,weight:.bold));if !tv.catalogKeyword.isEmpty {Text(tv.catalogKeyword).font(.system(size:19*scale)).foregroundStyle(.secondary)}}
                                Spacer()
                                ForEach(Array(tv.catalogActions.enumerated()),id:\.offset){i,action in
                                    Button{tv.focus=HomeFocus(row:0,column:i);tv.navigate(.select)}label:{Image(systemName:action == .search ? "magnifyingglass":action == .login ? "person.crop.circle":"arrow.clockwise").frame(width:24*scale)}.buttonStyle(TVActionStyle(focused:tv.focus.row==0 && tv.focus.column==i,reducedMotion:motion)).accessibilityLabel(action == .search ? "搜索":action == .login ? "登录":"刷新")
                                }
                            }
                            if tv.snapshot.cards.isEmpty {
                                VStack(spacing:20){if tv.busy {ProgressView()}else{Text("暂无视频").font(.title2)}}.frame(maxWidth:.infinity,minHeight:max(280,viewport.size.height-230))
                            } else {
                                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:28*scale),count:4),spacing:38*scale){
                                    ForEach(Array(tv.snapshot.cards.enumerated()),id:\.offset){i,item in
                                        BilibiliPoster(item:item,focused:tv.focus.row>0 && tv.cardIndex==i,motion:motion){tv.activate(item.id)}.id(i)
                                    }
                                }.padding(.horizontal,12*scale).padding(.vertical,18*scale)
                                HStack{Spacer();if tv.pagination.loading {ProgressView().controlSize(.small)};Spacer()}.font(.system(size:13*scale)).foregroundStyle(.secondary).frame(height:38)
                                    .background(GeometryReader{end in Color.clear.preference(key:CatalogBottomPreference.self,value:end.frame(in:.named("bilibiliCatalog")).minY)})
                            }
                        }.padding(.horizontal,viewport.size.width/24).padding(.top,viewport.size.height/18).padding(.bottom,40*scale).id("catalogTop")
                    }.coordinateSpace(name:"bilibiliCatalog")
                        .onPreferenceChange(CatalogBottomPreference.self){y in tv.catalogueEndVisible(y<viewport.size.height+260)}
                        .onChange(of:tv.focus){_,focus in withAnimation(motion ? nil:TVDesign.navigation){if focus.row==0 {proxy.scrollTo("catalogTop",anchor:.top)}else{proxy.scrollTo(tv.cardIndex,anchor:.center)}}}
                }
            }
        }
    }
    private var searchPanel:some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment:.leading,spacing:24*scale){
                HStack{Text("搜索").font(.system(size:28*scale,weight:.semibold));Spacer();BilibiliDismissButton(motion:motion){tv.back()}}
                HStack{TextField("搜索视频",text:$tv.searchDraft).textFieldStyle(.plain).font(.system(size:24*scale)).padding(18*scale).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:18*scale)).onSubmit{tv.submitSearch()}}
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:8),spacing:12){
                    ForEach(Array(tv.searchKeys.enumerated()),id:\.offset){i,key in
                        Button{tv.pressSearchKey(i)}label:{Text(key).lineLimit(1)}.buttonStyle(TVActionStyle(fillsWidth:true,focused:tv.searchFocus.row*8+tv.searchFocus.column==i,reducedMotion:motion))
                    }
                }
            }.padding(32*scale).frame(maxWidth:980*scale).modifier(TVSurface()).padding(40*scale)
        }
    }
    private var loginPanel:some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing:22){
                Text("扫码登录").font(.system(size:28*scale,weight:.semibold))
                if tv.loginImage==nil,!tv.loginNotice.isEmpty {Text(tv.loginNotice).font(.system(size:17*scale)).foregroundStyle(.secondary)}
                if let image=tv.loginImage {Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:760,maxHeight:430).clipShape(RoundedRectangle(cornerRadius:18)).accessibilityLabel("哔哩哔哩官方扫码登录二维码")}
                else {ProgressView().frame(width:300,height:250)}
                HStack(spacing:18){ForEach(Array(["刷新","关闭"].enumerated()),id:\.offset){i,title in
                    Button{if i==0 {tv.refreshLogin()}else{tv.closeLogin()}}label:{Text(title)}.buttonStyle(TVActionStyle(focused:tv.loginFocus==i,reducedMotion:motion))
                }}
            }.padding(32*scale).frame(maxWidth:980*scale).modifier(TVSurface()).padding(40*scale)
        }
    }
    private var qualityPanel:some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(alignment:.leading,spacing:20){
                HStack{Text("清晰度").font(.system(size:28*scale,weight:.semibold));Spacer();BilibiliDismissButton(motion:motion){tv.back()}}
                if tv.snapshot.qualities.isEmpty {ProgressView().frame(maxWidth:.infinity).padding(.vertical,24)}
                ScrollViewReader{proxy in ScrollView {
                    VStack(spacing:12){ForEach(Array(tv.snapshot.qualities.enumerated()),id:\.element.id){i,item in
                        Button{tv.chooseQuality(item)}label:{HStack{Text(item.title);Spacer();if item.current {Image(systemName:"checkmark.circle.fill")}}.frame(maxWidth:.infinity)}.buttonStyle(TVActionStyle(focused:tv.qualityIndex==i,reducedMotion:motion)).id(i)
                    }}.onAppear{proxy.scrollTo(tv.qualityIndex,anchor:.center)}.onChange(of:tv.qualityIndex){_,index in withAnimation(motion ? nil:TVDesign.focusSpring){proxy.scrollTo(index,anchor:.center)}}
                }}.frame(maxHeight:330*scale)
            }.padding(32*scale).frame(maxWidth:660*scale).modifier(TVSurface()).padding(40*scale)
        }
    }
    private var episodes:some View {
        ZStack(alignment:.bottom) {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture{tv.panel = .none}
            VStack(alignment:.leading,spacing:22){
                HStack{
                    if tv.hasEpisodes {Button("选集"){tv.selectContentTab(.episodes)}.buttonStyle(TVActionStyle(focused:tv.contentTabsFocused && tv.contentTab == .episodes,reducedMotion:motion))}
                    if tv.snapshot.creator?.url != nil {Button("UP 主"){tv.selectContentTab(.creator)}.buttonStyle(TVActionStyle(focused:tv.contentTabsFocused && tv.contentTab == .creator,reducedMotion:motion))}
                    Spacer();BilibiliDismissButton(motion:motion){tv.back()}}
                if tv.contentTab == .creator {BilibiliCreatorShelf(library:tv.creatorLibrary,tv:tv,motion:motion)}
                else {
                if !tv.snapshot.ranges.isEmpty {
                    HStack(spacing:12){ForEach(Array(tv.snapshot.ranges.enumerated()),id:\.element.id){i,item in
                        Button{tv.rangeIndex=i;tv.activate(item.id,keepPanel:true)}label:{Text(item.title)}.buttonStyle(TVActionStyle(focused:tv.rangeFocused && tv.rangeIndex==i,reducedMotion:motion))
                    }}
                }
                if tv.snapshot.episodes.isEmpty {VStack(alignment:.leading,spacing:18){Text("暂无剧集");Button("重试"){tv.refresh()}}.padding(.vertical,25)}
                else {
                    ScrollViewReader{proxy in
                        ScrollView{
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:14),count:8),spacing:14){
                                ForEach(Array(tv.snapshot.episodes.enumerated()),id:\.element.number){i,item in
                                    BilibiliEpisodeButton(episode:item,focused:!tv.rangeFocused && tv.episodeIndex==i,motion:motion){tv.activate(item.id)}.id(item.number)
                                }
                            }.padding(5)
                        }.onAppear{if tv.snapshot.episodes.indices.contains(tv.episodeIndex){proxy.scrollTo(tv.snapshot.episodes[tv.episodeIndex].number,anchor:.center)}}.onChange(of:tv.episodeIndex){_,value in withAnimation(motion ? nil:.smooth(duration:0.2)){if tv.snapshot.episodes.indices.contains(value){proxy.scrollTo(tv.snapshot.episodes[value].number)}}}
                    }.frame(maxHeight:280*scale)
                }
                }
            }.padding(32*scale).modifier(TVSurface()).padding(.horizontal,54*scale).padding(.bottom,38*scale)
        }
    }
}

@MainActor enum BilibiliCoverCache {
    final class Entry:NSObject {let image:NSImage;let data:Data;init(image:NSImage,data:Data){self.image=image;self.data=data}}
    private static let images:NSCache<NSString,Entry>={let cache=NSCache<NSString,Entry>();cache.countLimit=24;cache.totalCostLimit=32*1024*1024;return cache}()
    static func cached(_ value:String)->Entry? {images.object(forKey:value as NSString)}
    static func fetch(_ value:String) async -> Entry? {
        if let value=cached(value){return value}
        guard !Task.isCancelled,let url=URL(string:value),url.scheme=="https" else{return nil}
        let request=URLRequest(url:url,cachePolicy:.returnCacheDataElseLoad,timeoutInterval:8)
        guard let (data,response)=try? await URLSession.shared.data(for:request),!Task.isCancelled,data.count<=6*1024*1024,
              (response as? HTTPURLResponse)?.statusCode==200,let image=NSImage(data:data) else{return nil}
        let entry=Entry(image:image,data:data)
        images.setObject(entry,forKey:value as NSString,cost:data.count+Int(image.size.width*image.size.height)*4)
        return entry
    }
}

@MainActor private final class BilibiliCoverLoader:ObservableObject {
    @Published var image:NSImage?
    @Published var imageRevision=0
    @Published var title=""
    @Published var loading=false
    private var requestedURL=""
    private var requestedTitle=""
    private var imageData:Data?
    private var task:Task<Void,Never>?
    func load(_ value:String,title:String,animated:Bool){
        requestedTitle=title
        if value==requestedURL && (task != nil || image != nil) {
            if !loading && self.title != title {withAnimation(animated ? .easeInOut(duration:0.2):nil){self.title=title}}
            return
        }
        task?.cancel();requestedURL=value;loading=true
        task=Task{[weak self] in
            guard let url=URL(string:value),url.scheme=="https" else{self?.loading=false;return}
            let entry=await BilibiliCoverCache.fetch(url.absoluteString)
            guard !Task.isCancelled,let self,self.requestedURL==value else{return}
            if let entry {
                let data=entry.data,result=entry.image
                withAnimation(animated ? .easeInOut(duration:0.2):nil){
                    if self.imageData != data {self.image=result;self.imageData=data;self.imageRevision+=1}
                    self.title=self.requestedTitle;self.loading=false
                }
            } else {self.loading=false}
            self.task=nil
        }
    }
    func cancel(){if loading {task?.cancel();task=nil;requestedURL=""}}
    deinit {task?.cancel()}
}

private struct BilibiliCoverLoading:View {
    let motion:Bool
    var body:some View {
        GeometryReader{g in
            ZStack {
                Color.white.opacity(0.06)
                if !motion {
                    TimelineView(.animation(minimumInterval:1.0/30)){context in
                        let progress=context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:1.35)/1.35
                        LinearGradient(colors:[.clear,.white.opacity(0.08),.clear],startPoint:.leading,endPoint:.trailing)
                            .frame(width:g.size.width*0.65).rotationEffect(.degrees(15)).offset(x:(progress*2-1)*g.size.width)
                    }
                }
            }.frame(width:g.size.width,height:g.size.height).clipped()
        }.allowsHitTesting(false)
    }
}

struct BilibiliPoster:View {
    @Environment(\.tvScale) private var scale
    let item:BilibiliCard
    var duration=""
    let focused:Bool
    let motion:Bool
    let action:()->Void
    @StateObject private var cover=BilibiliCoverLoader()
    var body:some View {
        Button(action:action){
            VStack(alignment:.leading,spacing:13){
                GeometryReader{g in
                    ZStack {
                        RoundedRectangle(cornerRadius:18).fill(.white.opacity(0.08))
                        if let image=cover.image {
                            Image(nsImage:image).resizable().scaledToFill().frame(width:g.size.width,height:g.size.height).clipped().id(cover.imageRevision).transition(.opacity).zIndex(1)
                        }
                        if cover.loading && cover.image==nil {BilibiliCoverLoading(motion:motion).accessibilityLabel("正在加载封面")}
                        else if cover.image==nil {Image(systemName:"photo").font(.system(size:34)).foregroundStyle(.secondary)}

                    }.frame(width:g.size.width,height:g.size.height).clipShape(RoundedRectangle(cornerRadius:18))
                        .overlay(alignment:.bottomTrailing){if !duration.isEmpty {Text(duration).font(.system(size:12*scale,weight:.medium)).padding(.horizontal,7*scale).padding(.vertical,4*scale).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:6)).padding(10*scale)}}
                        .modifier(TVCardFocus(focused:focused,reducedMotion:motion))
                }.aspectRatio(16/9,contentMode:.fit)

                Text(cover.title.isEmpty ? item.title:cover.title).contentTransition(.opacity).font(.system(size:20*scale,weight:focused ? .semibold:.medium)).foregroundStyle(.white.opacity(focused ? 1:0.65)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).frame(height:54*scale,alignment:.topLeading).padding(.horizontal,4*scale)
            }
        }.buttonStyle(TVPressStyle(reducedMotion:motion)).accessibilityLabel(item.title)
            .onAppear{cover.load(item.poster,title:item.title,animated:!motion)}
            .onChange(of:item){_,item in cover.load(item.poster,title:item.title,animated:!motion)}
            .onDisappear{cover.cancel()}
            .animation(motion ? nil:TVDesign.focusSpring,value:focused)
    }
}

private struct BilibiliEpisodeButton:View {
    @Environment(\.tvScale) private var scale
    let episode:BilibiliEpisode
    let focused:Bool
    let motion:Bool
    let action:()->Void
    var body:some View {
        Button(action:action){
            Text(String(episode.number)).font(.system(size:26*scale,weight:.semibold)).monospacedDigit()
                .frame(height:54*scale,alignment:.center)
        }.buttonStyle(TVActionStyle(fillsWidth:true,focused:focused,reducedMotion:motion))
            .overlay(alignment:.bottom){
                if episode.current {Text("当前集").font(.system(size:11*scale,weight:.medium)).foregroundStyle(focused ? .black.opacity(0.65):.white.opacity(0.65)).padding(.bottom,6*scale).allowsHitTesting(false)}
            }.accessibilityLabel("第 \(episode.number) 集"+(episode.current ? "，当前集":""))
    }
}

private struct CatalogBottomPreference:PreferenceKey {
    static var defaultValue:CGFloat { .infinity }
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=min(value,nextValue())}
}

struct BilibiliDismissButton:View {
    let motion:Bool
    let action:()->Void
    var body:some View {Button(action:action){Image(systemName:"xmark").frame(width:22,height:22)}.buttonStyle(TVActionStyle(reducedMotion:motion)).accessibilityLabel("关闭")}
}
