// make_icon.swift — 生成 DShMenu.app 的应用图标（1024x1024 PNG）
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

// macOS 风格圆角底色
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                      xRadius: 185, yRadius: 185)
NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.15, alpha: 1).setFill()
bg.fill()

// 绿色状态圆点（呼应菜单栏运行状态）
let dot = NSBezierPath(ovalIn: NSRect(x: 262, y: 262, width: 500, height: 500))
NSColor.systemGreen.setFill()
dot.fill()

// 内圈高光
let inner = NSBezierPath(ovalIn: NSRect(x: 342, y: 342, width: 340, height: 340))
NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.88, alpha: 1).setFill()
inner.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
do {
    try png.write(to: URL(fileURLWithPath: out))
    print("icon written: \(out)")
} catch {
    FileHandle.standardError.write("icon write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
