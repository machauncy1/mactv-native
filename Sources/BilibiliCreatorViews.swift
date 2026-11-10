import SwiftUI
import WebKit

// Keep the reader attached behind an opaque surface so the official page can
// finish layout and lazy loading; it is never an interactive or visible page.
struct BilibiliCreatorBackground:View {
    @ObservedObject var library:BilibiliCreatorLibrary
    var body:some View {ZStack{CreatorReaderSurface(library:library);if let worker=library.preloader {CreatorReaderSurface(library:worker)}}}
}
private struct CreatorReaderSurface:View {
    @ObservedObject var library:BilibiliCreatorLibrary
    var body:some View {if let view=library.webView {CreatorWebSurface(view:view)}}
}
private struct CreatorWebSurface:NSViewRepresentable {
    let view:WKWebView
    func makeNSView(context:Context)->NSView {let holder=NSView();view.frame=holder.bounds;view.autoresizingMask=[.width,.height];holder.addSubview(view);return holder}
    func updateNSView(_ holder:NSView,context:Context){view.frame=holder.bounds}
}
struct BilibiliCreatorShelf:View {
    @Environment(\.tvScale) private var scale
    @ObservedObject var library:BilibiliCreatorLibrary
    @ObservedObject var tv:BilibiliRemote
    let motion:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:10*scale){
            HStack(spacing:12*scale){
                if let avatar=library.creator?.avatar,let url=URL(string:avatar){AsyncImage(url:url){image in image.resizable().scaledToFill()}placeholder:{Image(systemName:"person.crop.circle.fill").resizable()}.frame(width:36*scale,height:36*scale).clipShape(Circle())}
                Text(library.creator?.name ?? tv.snapshot.creator?.name ?? "UP 主").font(.system(size:22*scale,weight:.semibold))
                Spacer()
            }
            Text(library.selectedCollection?.title ?? "最新视频").font(.system(size:16*scale,weight:.semibold)).foregroundStyle(.secondary)
            videoRow(library.displayedState).id(library.selectedCollection?.id ?? "latest").transition(.opacity)

            if !library.collectionListState.collections.isEmpty || (library.section == .collections && library.loading) || tv.creatorRow == .collections {
                collectionRow
            }
        }.animation(motion ? nil:TVDesign.fade,value:library.selectedCollection?.id)
    }
    private func videoRow(_ state:CreatorBrowseState)->some View {
        Group {
            if state.videos.isEmpty {
                if library.loading {HStack(spacing:22*scale){ForEach(0..<5,id:\.self){_ in RoundedRectangle(cornerRadius:18*scale).fill(.white.opacity(0.08)).frame(width:220*scale,height:125*scale)}}.padding(.horizontal,10*scale).frame(height:210*scale,alignment:.top).clipped().accessibilityLabel("载入视频")}
                else if state.empty {Text("暂无视频").foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:210*scale)}
                else {emptyRow(section:.videos)}
            }
            else {ScrollViewReader{proxy in
                ScrollView(.horizontal,showsIndicators:false){LazyHStack(alignment:.top,spacing:22*scale){
                    ForEach(Array(state.videos.enumerated()),id:\.element.id){i,video in
                        BilibiliPoster(item:video.card,duration:video.duration,focused:!tv.contentTabsFocused && tv.creatorRow == .videos && state.index==i,motion:motion){library.focusVideo(i);tv.playCreatorVideo(video)}.frame(width:220*scale).id(video.id)
                            .onAppear{if i>=state.videos.count-2,(library.selectedCollection != nil || library.section == .videos) {library.loadMore()}}
                    }

                }.padding(.horizontal,10*scale).padding(.vertical,10*scale)}
                .onAppear{scroll(proxy,state:state)}.onChange(of:state.index){_,_ in withAnimation(motion ? nil:TVDesign.focusSpring){scroll(proxy,state:state)}}
            }.frame(height:210*scale)}
        }
    }
    private var collectionRow:some View {
        ScrollViewReader{proxy in
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:20*scale){
                collectionTab(title:"最新视频",index:-1,symbol:"play.rectangle")
                ForEach(Array(library.collectionListState.collections.enumerated()),id:\.element.id){i,entry in
                    collectionTab(title:entry.title,index:i,symbol:"rectangle.stack.fill")
                }
            }.padding(.horizontal,10*scale).padding(.vertical,10*scale)}
            .onChange(of:library.collectionFocus.index){_,index in withAnimation(motion ? nil:TVDesign.focusSpring){proxy.scrollTo(index,anchor:.center)}}
        }.frame(height:95*scale)
    }
    private func collectionTab(title:String,index:Int,symbol:String)->some View {
        Button{tv.creatorRow = .collections;library.selectCollection(index)}label:{
            HStack(spacing:12*scale){Image(systemName:symbol).font(.system(size:25*scale));Text(title).font(.system(size:16*scale,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)}.frame(width:240*scale,height:52*scale)
        }.buttonStyle(TVActionStyle(focused:!tv.contentTabsFocused && tv.creatorRow == .collections && library.collectionFocus.index==index,reducedMotion:motion)).id(index)
    }
    private func emptyRow(section:CreatorSection)->some View {
        HStack(spacing:16*scale){
            if library.loading && library.section==section {ProgressView()}
            else {Text(section == .collections ? "暂无合集":library.failure ?? "暂无视频").foregroundStyle(.secondary);Button("重试"){library.retry()}.buttonStyle(TVActionStyle(focused:!tv.contentTabsFocused && tv.creatorRow==section,reducedMotion:motion))}
        }.frame(maxWidth:.infinity,minHeight:section == .videos ? 180*scale:75*scale)
    }
    private func scroll(_ proxy:ScrollViewProxy,state:CreatorBrowseState){if state.videos.indices.contains(state.index){proxy.scrollTo(state.videos[state.index].id,anchor:.center)}}
}
