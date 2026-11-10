import AppKit
import SwiftUI

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    var window:NSWindow!
    var model:AppModel!
    func applicationDidFinishLaunching(_ notification:Notification) {
        model=AppModel()
        window=TVWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="MacTV Native";window.titlebarAppearsTransparent=true;window.titleVisibility = .hidden
        window.backgroundColor = .black;window.minSize=NSSize(width:960,height:600)
        window.isReleasedWhenClosed=false;window.collectionBehavior.insert(.fullScreenPrimary)
        let hosting=NSHostingView(rootView:ShellView(app:model))
        hosting.frame=window.contentView?.bounds ?? NSRect(x:0,y:0,width:1280,height:800)
        hosting.autoresizingMask=[.width,.height]
        hosting.sizingOptions=[.minSize]
        #if compiler(>=5.9)
        hosting.safeAreaRegions=[]
        #endif
        window.contentView=hosting
        window.center();window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        installMenu();model.start()
        if CommandLine.arguments.contains("--show-remote-settings") {model.menuOpen=true;model.remoteSettingsOpen=true}
        if let i=CommandLine.arguments.firstIndex(of:"--open"),i+1<CommandLine.arguments.count {
            model.openURL(URL(fileURLWithPath:CommandLine.arguments[i+1]))
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {(window as? TVWindow)?.restoreTVFullscreen();model?.finish()}
    func application(_ sender:NSApplication,openFiles filenames:[String]) {if let first=filenames.first {model?.openURL(URL(fileURLWithPath:first))};sender.reply(toOpenOrPrint:.success)}
    @objc func openFile() {model.openFiles()}
    @objc func showHome() {model.home()}
    @objc func fullScreen() {model.toggleFullscreen()}
    @objc func showControls() {model.menuIndex=0;model.menuOpen.toggle()}
    private func installMenu() {
        let menu=NSMenu()
        let application=NSMenuItem();let appMenu=NSMenu()
        appMenu.addItem(withTitle:"关于 MacTV Native",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"退出 MacTV Native",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        application.submenu=appMenu;menu.addItem(application)
        let file=NSMenuItem();let files=NSMenu(title:"文件")
        let open=files.addItem(withTitle:"打开影片…",action:#selector(openFile),keyEquivalent:"o");open.target=self
        file.submenu=files;menu.addItem(file)
        let edit=NSMenuItem();let edits=NSMenu(title:"编辑")
        edits.addItem(withTitle:"撤销",action:Selector(("undo:")),keyEquivalent:"z")
        let redo=edits.addItem(withTitle:"重做",action:Selector(("redo:")),keyEquivalent:"z");redo.keyEquivalentModifierMask=[.command,.shift]
        edits.addItem(.separator())
        edits.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        edits.addItem(withTitle:"复制",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edits.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edits.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        edit.submenu=edits;menu.addItem(edit)
        let view=NSMenuItem();let views=NSMenu(title:"显示")
        let home=views.addItem(withTitle:"首页",action:#selector(showHome),keyEquivalent:"h");home.keyEquivalentModifierMask=[.command,.shift];home.target=self
        let control=views.addItem(withTitle:"控制中心",action:#selector(showControls),keyEquivalent:",");control.target=self
        let full=views.addItem(withTitle:"切换全屏",action:#selector(fullScreen),keyEquivalent:"f");full.keyEquivalentModifierMask=[.command,.control];full.target=self
        view.submenu=views;menu.addItem(view);NSApp.mainMenu=menu
    }
}

@main enum NativeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {_ = SmokeTests.run();_ = BilibiliTests.run();return}
        if let i=CommandLine.arguments.firstIndex(of:"--verify-media"),i+1<CommandLine.arguments.count {
            exit(MediaProbe.run(path:CommandLine.arguments[i+1]) ? 0 : 1)
        }
        let app=NSApplication.shared
        let delegate=AppDelegate()
        app.delegate=delegate;app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate){app.run()}
    }
}
