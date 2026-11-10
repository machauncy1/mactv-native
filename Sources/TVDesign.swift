import SwiftUI

// One visual vocabulary for the home screen, catalogue, sheets and both native players.
enum TVDesign {
    static let focusSpring=Animation.spring(response:0.36,dampingFraction:0.86)
    static let navigation=Animation.spring(response:0.42,dampingFraction:0.94)
    static let fade=Animation.easeInOut(duration:0.2)
    static func scale(for size:CGSize)->CGFloat {min(1.45,max(0.82,min(size.width/1280,size.height/800)))}
    static func pageTransition(reduced:Bool)->AnyTransition {reduced ? .opacity : .asymmetric(insertion:.opacity.combined(with:.offset(y:10)),removal:.opacity)}
    static func sheetTransition(reduced:Bool)->AnyTransition {reduced ? .opacity : .opacity.combined(with:.offset(y:20))}
}
private struct TVScaleKey:EnvironmentKey {static let defaultValue:CGFloat=1}
extension EnvironmentValues {var tvScale:CGFloat {get{self[TVScaleKey.self]}set{self[TVScaleKey.self]=newValue}}}

struct TVCardFocus:ViewModifier {
    let focused:Bool
    let reducedMotion:Bool
    @Environment(\.tvScale) private var scale
    func body(content:Content)->some View {
        content
            .clipShape(RoundedRectangle(cornerRadius:20*scale,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:20*scale,style:.continuous).strokeBorder(.white.opacity(focused ? 0.92:0.08),lineWidth:(focused ? 1.5:0.5)*scale))
            .shadow(color:.white.opacity(focused ? 0.12:0),radius:14*scale)
            .shadow(color:.black.opacity(focused ? 0.6:0.25),radius:(focused ? 22:8)*scale,y:(focused ? 15:6)*scale)
            .scaleEffect(focused && !reducedMotion ? 1.08:1)
            .offset(y:focused && !reducedMotion ? -4*scale:0)
            .animation(reducedMotion ? nil:TVDesign.focusSpring,value:focused)
    }
}

struct TVActionStyle:ButtonStyle {
    var fillsWidth=false
    var focused=false
    var reducedMotion=false
    @Environment(\.tvScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:18*scale,weight:.medium))
            .multilineTextAlignment(.center)
            .frame(minHeight:26*scale,alignment:.center)
            .padding(.horizontal,20*scale).padding(.vertical,13*scale)
            .frame(maxWidth:fillsWidth ? .infinity:nil,alignment:.center)
            .foregroundStyle(focused ? .black:.white.opacity(0.92))
            .background(focused ? Color.white:.white.opacity(0.1),in:RoundedRectangle(cornerRadius:16*scale,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:16*scale,style:.continuous).strokeBorder(.white.opacity(focused ? 0.9:0.08),lineWidth:1))
            .shadow(color:.black.opacity(focused ? 0.3:0),radius:12*scale,y:6*scale)
            .scaleEffect(configuration.isPressed && !reducedMotion && !systemReduced ? 0.97 : focused && !reducedMotion && !systemReduced ? 1.025:1)
            .animation(reducedMotion || systemReduced ? nil:TVDesign.focusSpring,value:focused)
            .animation(reducedMotion || systemReduced ? nil:TVDesign.fade,value:configuration.isPressed)
    }
}

struct TVSurface:ViewModifier {
    var radius:CGFloat=28
    @Environment(\.tvScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content:Content)->some View {
        surface(content)
            .shadow(color:.black.opacity(0.22),radius:24*scale,y:12*scale)
    }
    @ViewBuilder private func surface(_ content:Content)->some View {
        let shape=RoundedRectangle(cornerRadius:radius*scale,style:.continuous)
        if reduceTransparency {
            content.background(Color(white:0.12),in:shape).overlay(shape.strokeBorder(.white.opacity(0.14),lineWidth:0.7))
        } else if #available(macOS 26.0,*) {
            content.glassEffect(.regular,in:shape)
        } else {
            content.background(.ultraThinMaterial,in:shape)
                .overlay(shape.strokeBorder(LinearGradient(colors:[.white.opacity(0.30),.white.opacity(0.06),.white.opacity(0.16)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.8))
        }
    }
}

struct TVTimeline:View {
    @Binding var position:Double
    let duration:Double
    var editing:(Bool)->Void={_ in}
    @Environment(\.tvScale) private var scale
    private var ratio:CGFloat {duration>0 ? CGFloat(min(1,max(0,position/duration))):0}
    var body:some View {
        VStack(spacing:10*scale){
            GeometryReader{g in
                ZStack(alignment:.leading){
                    Capsule().fill(.white.opacity(0.25)).frame(height:4*scale)
                    Capsule().fill(.white).frame(width:max(0,g.size.width*ratio),height:4*scale)
                    Circle().fill(.white).frame(width:12*scale,height:12*scale).shadow(color:.black.opacity(0.2),radius:3).offset(x:max(0,min(g.size.width-12*scale,g.size.width*ratio-6*scale)))
                }.frame(height:28*scale).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged{value in
                        guard duration.isFinite,duration>0 else{return}
                        editing(true);position=min(duration,max(0,Double(value.location.x/max(1,g.size.width))*duration))
                    }.onEnded{_ in editing(false)})
            }.frame(height:28*scale)
            HStack {Text(Timeline.text(position));Spacer();Text("−"+Timeline.text(max(0,duration-position))).foregroundStyle(.white.opacity(0.7))}
                .font(.system(size:15*scale,weight:.medium,design:.monospaced)).monospacedDigit()
        }.accessibilityElement(children:.ignore).accessibilityLabel("播放进度")
            .accessibilityValue(Timeline.text(position)+" / "+Timeline.text(duration))
            .accessibilityAdjustableAction{direction in
                guard duration>0 else{return};editing(true)
                switch direction {case .increment:position=min(duration,position+10);case .decrement:position=max(0,position-10);@unknown default:break}
                editing(false)
            }
    }
}

struct TVPlaybackPanel<Actions:View>:View {
    let title:String
    let playing:Bool
    @Binding var position:Double
    let duration:Double
    var editing:(Bool)->Void
    @ViewBuilder var actions:()->Actions
    @Environment(\.tvScale) private var scale
    var body:some View {
        VStack(spacing:0){
            Spacer()
            VStack(alignment:.leading,spacing:16*scale){
                HStack(alignment:.center,spacing:24*scale){
                    VStack(alignment:.leading,spacing:5*scale){
                        Text(title).font(.system(size:23*scale,weight:.semibold)).lineLimit(1)
                    }
                    Spacer(minLength:8)
                    actions()
                }
                TVTimeline(position:$position,duration:duration,editing:editing)

            }.padding(26*scale).modifier(TVSurface())
                .padding(.horizontal,54*scale).padding(.bottom,38*scale)
                .background(LinearGradient(colors:[.clear,.black.opacity(0.5)],startPoint:.top,endPoint:.bottom).ignoresSafeArea(edges:.bottom))
        }.allowsHitTesting(true)
    }
}
