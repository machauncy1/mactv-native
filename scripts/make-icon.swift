import AppKit
import Foundation

let folder=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image=NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let s=CGFloat(size)
    let box=NSRect(x:s*0.06,y:s*0.06,width:s*0.88,height:s*0.88)
    let shape=NSBezierPath(roundedRect:box,xRadius:s*0.20,yRadius:s*0.20)
    NSGradient(starting:NSColor(red:0.23,green:0.28,blue:0.55,alpha:1),ending:NSColor(red:0.055,green:0.07,blue:0.16,alpha:1))!.draw(in:shape,angle:-80)
    let screen=NSBezierPath(roundedRect:NSRect(x:s*0.20,y:s*0.28,width:s*0.60,height:s*0.43),xRadius:s*0.075,yRadius:s*0.075)
    NSColor.white.withAlphaComponent(0.9).setStroke();screen.lineWidth=max(1,s*0.026);screen.stroke()
    let play=NSBezierPath();play.move(to:NSPoint(x:s*0.44,y:s*0.39));play.line(to:NSPoint(x:s*0.44,y:s*0.61));play.line(to:NSPoint(x:s*0.62,y:s*0.5));play.close()
    NSColor.white.setFill();play.fill()
    let base=NSBezierPath();base.move(to:NSPoint(x:s*0.39,y:s*0.19));base.line(to:NSPoint(x:s*0.61,y:s*0.19));base.lineWidth=max(1,s*0.025);base.lineCapStyle = .round;NSColor.white.withAlphaComponent(0.7).setStroke();base.stroke()
    image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    let png=rep.representation(using:.png,properties:[:])!
    let names:[String]
    switch size {
    case 16:names=["icon_16x16.png"]
    case 32:names=["icon_16x16@2x.png","icon_32x32.png"]
    case 64:names=["icon_32x32@2x.png"]
    case 128:names=["icon_128x128.png"]
    case 256:names=["icon_128x128@2x.png","icon_256x256.png"]
    case 512:names=["icon_256x256@2x.png","icon_512x512.png"]
    default:names=["icon_512x512@2x.png"]
    }
    for name in names {try png.write(to:folder.appendingPathComponent(name))}
}
