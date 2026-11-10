import AppKit

@MainActor final class TVWindow:NSWindow {
    private(set) var isTVFullscreen=false
    private var previousFrame=NSRect.zero
    private var previousStyle:NSWindow.StyleMask=[]
    private var previousPresentation:NSApplication.PresentationOptions=[]
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {true}
    override func toggleFullScreen(_ sender:Any?){
        if isTVFullscreen {restoreTVFullscreen();return}
        guard let screen=screen ?? NSScreen.main else{return}
        previousFrame=frame;previousStyle=styleMask;previousPresentation=NSApp.presentationOptions
        isTVFullscreen=true
        styleMask = .borderless
        NSApp.presentationOptions=[.autoHideDock,.autoHideMenuBar]
        setFrame(screen.frame,display:true,animate:false)
        makeKeyAndOrderFront(nil)
    }
    func restoreTVFullscreen(){
        guard isTVFullscreen else{return}
        isTVFullscreen=false;NSApp.presentationOptions=previousPresentation
        styleMask=previousStyle;setFrame(previousFrame,display:true,animate:false)
    }
    override func close(){restoreTVFullscreen();super.close()}
}
