import SwiftUI
import AVKit

private struct HomeTile {let title:String;let symbol:String;let colors:[Color]}
private let tiles:[HomeTile]=[
    HomeTile(title:"YouTube",symbol:"play.rectangle.fill",colors:[.white,Color(white:0.86)]),
    HomeTile(title:"Netflix",symbol:"play.rectangle.fill",colors:[.black,Color(white:0.08)]),
    HomeTile(title:"哔哩哔哩",symbol:"play.rectangle.fill",colors:[.pink,Color(red:0.85,green:0.2,blue:0.43)]),
    HomeTile(title:"本地影院",symbol:"play.display",colors:[Color(red:0.52,green:0.73,blue:1),Color(red:0.12,green:0.31,blue:0.72)]),
    HomeTile(title:"最近播放",symbol:"clock.arrow.circlepath",colors:[Color(red:0.76,green:0.48,blue:0.91),Color(red:0.38,green:0.21,blue:0.63)]),
    HomeTile(title:"控制中心",symbol:"slider.horizontal.3",colors:[Color(white:0.43),Color(white:0.22)])
]

struct ShellView:View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var app:AppModel
    var body:some View {
        GeometryReader {geometry in
        ZStack {
            Color.black
            switch app.screen {
            case .home:HomeScreen(app:app).transition(TVDesign.pageTransition(reduced:app.reducedMotion || systemReduceMotion))
            case .recent:RecentScreen(app:app).transition(TVDesign.pageTransition(reduced:app.reducedMotion || systemReduceMotion))
            case .player:PlayerScreen(app:app,media:app.playback).transition(TVDesign.pageTransition(reduced:app.reducedMotion || systemReduceMotion))
            case .web:YouTubeScreen(app:app,browser:app.browser).transition(TVDesign.pageTransition(reduced:app.reducedMotion || systemReduceMotion))
            }
            if app.menuOpen {ControlCenter(app:app).transition((app.reducedMotion || systemReduceMotion) ? .opacity : .opacity.combined(with:.move(edge:.trailing)))}
            if let toast=app.toast {VStack{Spacer();Text(toast).padding(.horizontal,26).padding(.vertical,14).background(.ultraThinMaterial,in:Capsule()).padding(.bottom,35)}}
        }
        .onChange(of:app.menuOpen){_,open in
            if !open && app.screen == .web {app.browser.webView.window?.makeFirstResponder(app.browser.webView)}
        }
        .environment(\.tvScale,TVDesign.scale(for:geometry.size))
        .preferredColorScheme(.dark)
        .frame(minWidth:960,maxWidth:.infinity,minHeight:600,maxHeight:.infinity)
        .animation((app.reducedMotion || systemReduceMotion) ? nil : .spring(response:0.42,dampingFraction:0.92),value:app.menuOpen)
        .animation((app.reducedMotion || systemReduceMotion) ? nil : .spring(response:0.42,dampingFraction:0.94),value:app.screen)
        }
    }
}

struct AmbientBackground:View {
    var accent:Color
    var body:some View {
        GeometryReader {g in
            ZStack {
                LinearGradient(colors:[Color(red:0.025,green:0.06,blue:0.14),Color(red:0.035,green:0.10,blue:0.20),Color(red:0.015,green:0.025,blue:0.065)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Ellipse().fill(LinearGradient(colors:[accent.opacity(0.38),Color.cyan.opacity(0.16),.clear],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:g.size.width*1.4,height:g.size.height*1.05).rotationEffect(.degrees(-24)).blur(radius:75).offset(x:-g.size.width*0.2,y:-g.size.height*0.42)
                Ellipse().fill(Color.indigo.opacity(0.20)).frame(width:g.size.width*1.2,height:g.size.height*0.65).blur(radius:100).offset(x:g.size.width*0.4,y:g.size.height*0.42)
                LinearGradient(colors:[.clear,.black.opacity(0.38)],startPoint:.center,endPoint:.bottom)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct TVClock:View {
    @Environment(\.tvScale) private var scale
    var body:some View {
        TimelineView(.periodic(from:.now,by:10)){context in
            Text(context.date,format:.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits))
                .font(.system(size:22*scale,weight:.medium)).monospacedDigit()
        }
    }
}

struct Header:View {
    @Environment(\.tvScale) private var scale
    var title="MacTV"
    var body:some View {
        HStack {
            Label(title,systemImage:"tv").font(.system(size:22*scale,weight:.semibold))
            Spacer()
            TimelineView(.periodic(from:.now,by:10)) {context in Text(context.date,format:.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits)).font(.system(size:22*scale,weight:.medium,design:.rounded)).monospacedDigit().padding(.leading,22)}
        }
    }
}

struct HomeScreen:View {
    @Environment(\.tvScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var app:AppModel
    var body:some View {
        GeometryReader {g in
            let spacing=40*scale
            let width=min((g.size.width-160*scale-2*spacing)/3,(g.size.height-170*scale)*0.5*1.65)
            ZStack {
                AmbientBackground(accent:.blue)
                VStack(spacing:spacing) {
                    ForEach(0..<2,id:\.self){row in
                        HStack(alignment:.top,spacing:spacing){
                            ForEach(0..<3,id:\.self){column in
                                let index=row*3+column
                                TVAppTile(index:index,focused:app.focus.column==index,reducedMotion:app.reducedMotion || systemReduceMotion){app.activate(index)}hovered:{
                                    if Date().timeIntervalSince(app.lastKeyboardTime)>0.4 {app.focusHomeApp(index)}
                                }.frame(width:width)
                            }
                        }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
    }
}

struct TVPressStyle:ButtonStyle {
    let reducedMotion:Bool
    func makeBody(configuration:Configuration)->some View {
        configuration.label.scaleEffect(configuration.isPressed && !reducedMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reducedMotion ? nil : .spring(response:0.22,dampingFraction:0.8),value:configuration.isPressed)
    }
}

private enum BrandAssets {
    static let images:[NSImage?] = ["youtube.jpg","netflix.jpg","bilibili.jpg"].map {name in
        guard let url=Bundle.main.resourceURL?.appendingPathComponent("Brand/"+name) else{return nil}
        return NSImage(contentsOf:url)
    }
}

private struct BrandArtwork:View {
    let index:Int
    var body:some View {
        GeometryReader {g in
            ZStack {
                index==1 ? Color.black : Color.white
                if let image=BrandAssets.images[index] {
                    Image(nsImage:image).resizable().scaledToFit().frame(width:g.size.width*0.65,height:g.size.height*0.84)
                }
            }.frame(width:g.size.width,height:g.size.height).clipped()
        }
    }
}

private final class TileTilt:ObservableObject { @Published var point=CGSize.zero }

private struct TVAppTile:View {
    @Environment(\.tvScale) private var scale
    let index:Int
    let focused:Bool
    let reducedMotion:Bool
    let action:()->Void
    let hovered:()->Void
    @StateObject private var tilt=TileTilt()
    private var pointer:CGSize {tilt.point}
    var body:some View {
        Button(action:action) {
            VStack(spacing:20*scale) {
                GeometryReader {geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius:22).fill(LinearGradient(colors:tiles[index].colors,startPoint:.topLeading,endPoint:.bottomTrailing))
                        RoundedRectangle(cornerRadius:22).fill(LinearGradient(colors:[.white.opacity(focused ? 0.28 : 0.04),.clear,.black.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing))
                        if index<3 {
                            BrandArtwork(index:index).clipShape(RoundedRectangle(cornerRadius:22))
                        } else {
                            Image(systemName:tiles[index].symbol).font(.system(size:34*scale,weight:.regular)).foregroundStyle(.white)
                                .offset(x:reducedMotion ? 0 : pointer.width*3,y:reducedMotion ? 0 : pointer.height*3)
                                .shadow(color:.black.opacity(focused ? 0.17 : 0),radius:8,y:focused ? 7 : 0)
                        }
                        RoundedRectangle(cornerRadius:22).fill(LinearGradient(colors:[.white.opacity(focused ? 0.14 : 0),.clear],startPoint:.topLeading,endPoint:.bottomTrailing)).allowsHitTesting(false)
                    }
                    .modifier(TVCardFocus(focused:focused,reducedMotion:reducedMotion))
                    .rotation3DEffect(.degrees(reducedMotion ? 0 : -pointer.height*2),axis:(x:1,y:0,z:0))
                    .rotation3DEffect(.degrees(reducedMotion ? 0 : pointer.width*2),axis:(x:0,y:1,z:0))
                    .onContinuousHover {phase in
                        switch phase {
                        case .active(let point):
                            hovered()
                            let x=point.x / max(1,geometry.size.width) * 2 - 1
                            let y=point.y / max(1,geometry.size.height) * 2 - 1
                            tilt.point=CGSize(width:max(-1,min(1,x)),height:max(-1,min(1,y)))
                        case .ended:tilt.point = .zero
                        }
                    }
                }.aspectRatio(1.65,contentMode:.fit)
                Text(tiles[index].title).font(.system(size:17*scale,weight:.medium)).lineLimit(1).foregroundStyle(.white.opacity(focused ? 1:0.65))
            }
        }.buttonStyle(TVPressStyle(reducedMotion:reducedMotion)).accessibilityLabel("打开"+tiles[index].title)
            .animation(reducedMotion ? nil : TVDesign.focusSpring,value:focused)
            .animation(reducedMotion ? nil : .interactiveSpring(response:0.25,dampingFraction:0.85),value:pointer)
    }
}

struct RecentScreen:View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var app:AppModel
    var body:some View {
        ZStack {
            AmbientBackground(accent:.purple)
            VStack(alignment:.leading,spacing:24) {
                HStack {Header(title:"最近播放");if !app.library.isEmpty {Button{app.openFiles()}label:{Image(systemName:"folder.badge.plus")}.buttonStyle(TVActionStyle(focused:app.focus.row==0,reducedMotion:app.reducedMotion || systemReduceMotion)).accessibilityLabel("打开影片")}}
                if app.library.isEmpty {
                    Spacer();VStack(spacing:18){Image(systemName:"film.stack").font(.system(size:65,weight:.thin));Text("暂无播放记录").font(.title);Button("选择本地影片"){app.openFiles()}.buttonStyle(TVActionStyle(focused:true,reducedMotion:app.reducedMotion || systemReduceMotion))}.frame(maxWidth:.infinity);Spacer()
                } else {
                    ScrollViewReader {proxy in
                        ScrollView {
                            LazyVStack(spacing:12) {
                                ForEach(Array(app.library.enumerated()),id:\.element.id) {i,item in
                                    Button {app.play(item)} label:{HStack(spacing:18){Image(systemName:"play.rectangle").font(.system(size:30)).frame(width:55);VStack(alignment:.leading,spacing:5){Text(item.title).font(.system(size:20,weight:.medium));Text(Timeline.text(item.position)).font(.system(size:13)).foregroundStyle(.secondary)};Spacer()}.padding(20).background(.white.opacity(app.focus.row>0 && app.focus.column==i ? 0.18 : 0.05),in:RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain).id(i)
                                }
                            }
                        }.onChange(of:app.focus.column){_,value in withAnimation((app.reducedMotion || systemReduceMotion) ? nil : .smooth(duration:0.25)){proxy.scrollTo(value,anchor:.center)}}
                    }
                }
            }.padding(45)
        }
    }
}

struct PlayerScreen:View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var app:AppModel
    @ObservedObject var media:Playback
    var body:some View {
        ZStack {
            Color.black;NativeVideoView(player:media.player)
            if let error=media.failure {VStack(spacing:20){Image(systemName:"exclamationmark.triangle").font(.largeTitle);Text(error);Button("选择其他影片"){app.openFiles()}.buttonStyle(TVActionStyle())}.padding(40).modifier(TVSurface())}
            if app.playerControls || app.playerScrubbing {
                TVPlaybackPanel(title:media.title,playing:media.playing,position:Binding(get:{media.current},set:{media.seekTo($0)}),duration:media.duration,editing:{editing in app.playerScrubbing=editing;app.showControls()}){
                    HStack(spacing:12){ForEach(0..<5,id:\.self){i in
                        Button{app.performPlayerAction(i)}label:{Image(systemName:["gobackward.10",media.playing ? "pause.fill":"play.fill","goforward.10",media.muted ? "speaker.slash.fill":"speaker.wave.2.fill","arrow.up.left.and.arrow.down.right"][i]).frame(minWidth:24)}
                            .buttonStyle(TVActionStyle(focused:app.playerActionIndex==i,reducedMotion:app.reducedMotion || systemReduceMotion)).accessibilityLabel(["后退10秒",media.playing ? "暂停":"继续","前进10秒","静音","切换全屏"][i])
                    }}
                }.transition(TVDesign.sheetTransition(reduced:app.reducedMotion || systemReduceMotion))
            }
        }.contentShape(Rectangle()).onTapGesture{app.showControls()}
            .animation(app.reducedMotion || systemReduceMotion ? nil:TVDesign.navigation,value:app.playerControls)
    }
}

struct YouTubeScreen:View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var app:AppModel
    @ObservedObject var browser:YouTubeBrowser
    var body:some View {
        ZStack {
            if let tv=browser.bilibili {BilibiliScreen(app:app,browser:browser,tv:tv)}
            else {EmbeddedYouTube(browser:browser)}
            if browser.bilibili == nil,let error=browser.failure {
                VStack(spacing:20){Image(systemName:"wifi.exclamationmark").font(.system(size:45));Text(error).font(.title3);HStack{Button("重新载入"){browser.loadHome()};if browser.service == .youtube {Button("切换网页版"){browser.desktopSite()}}}}.padding(35).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
            }
        }.background(.black).ignoresSafeArea()
            .onAppear{if browser.service != .bilibili {DispatchQueue.main.async{browser.webView.window?.makeFirstResponder(browser.webView)}}}
    }
}

struct ControlCenter:View {
    @Environment(\.tvScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var app:AppModel
    private var motion:Bool {app.reducedMotion || systemReduceMotion}
    var body:some View {
        ZStack(alignment:.topTrailing) {
            Color.black.opacity(0.20).ignoresSafeArea().onTapGesture{app.menuOpen=false}
            VStack(alignment:.trailing,spacing:18*scale){
                HStack(spacing:18*scale){
                    TVClock()
                    Button{app.backControlCenter()}label:{Image(systemName:"xmark").font(.system(size:17*scale,weight:.semibold)).frame(width:24*scale,height:24*scale)}.buttonStyle(TVActionStyle(reducedMotion:motion)).accessibilityLabel("关闭控制中心")
                }.padding(.leading,22*scale).modifier(TVSurface(radius:50))
                Button{app.performMenu(0)}label:{
                    HStack(spacing:18*scale){Image(systemName:"wifi").font(.system(size:27*scale));Text("Wi-Fi");Spacer();Image(systemName:"chevron.right").font(.system(size:14*scale))}.frame(maxWidth:.infinity,minHeight:38*scale)
                }.buttonStyle(TVActionStyle(fillsWidth:true,focused:true,reducedMotion:motion))
                    .padding(14*scale).modifier(TVSurface(radius:30))
            }.frame(width:360*scale).padding(.trailing,42*scale).padding(.top,34*scale)
        }
    }
}
