// added by Terada: Center the outlined TeX mark on the inherited icon background.
// Generate Icon Composer artwork, a legacy fallback, and a full-bleed web avatar.
// swift Artwork/generate-icon.swift
import AppKit
import CoreText
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let asset = root.appendingPathComponent("Artwork/TeXShop.icon/Assets")
func fit(_ path:CGPath, height:CGFloat, centerX:CGFloat, bottom:CGFloat)->CGPath {
    let b=path.boundingBoxOfPath, scale=height/b.height
    var tr=CGAffineTransform(a:scale,b:0,c:0,d:scale,tx:centerX-b.midX*scale,ty:bottom-b.minY*scale)
    return path.copy(using:&tr)!
}
let tex=CGMutablePath()
// Outlined from page 2 (Latin Modern Roman Bold) of the user-provided PDF.
let operations = try JSONSerialization.jsonObject(with: Data(contentsOf:root.appendingPathComponent("Artwork/TeX-logo-outline.json"))) as! [[Any]]
for op in operations {
    let points=(op[1] as! [[Double]]).map { CGPoint(x:$0[0],y:$0[1]) }
    switch op[0] as! String {
    case "moveTo": tex.move(to:points[0])
    case "lineTo": tex.addLine(to:points[0])
    case "curveTo": tex.addCurve(to:points[2],control1:points[0],control2:points[1])
    case "closePath": tex.closeSubpath()
    default: fatalError("Unsupported outline operation")
    }
}
let word=fit(tex.normalized(using: .winding),height:340,centerX:512,bottom:342)
func svgPath(_ p:CGPath)->String {
    var s="";func n(_ v:CGFloat)->String {String(format:"%.3f",Double(v))}
    p.applyWithBlock { q in let e=q.pointee;let a=e.points
        switch e.type {
        case .moveToPoint:s += "M\(n(a[0].x)),\(n(a[0].y)) "
        case .addLineToPoint:s += "L\(n(a[0].x)),\(n(a[0].y)) "
        case .addQuadCurveToPoint:s += "Q\(n(a[0].x)),\(n(a[0].y)) \(n(a[1].x)),\(n(a[1].y)) "
        case .addCurveToPoint:s += "C\(n(a[0].x)),\(n(a[0].y)) \(n(a[1].x)),\(n(a[1].y)) \(n(a[2].x)),\(n(a[2].y)) "
        case .closeSubpath:s += "Z "
        @unknown default:break
        }
    };return s
}
// Layered vector relief: soft cast shadow, a lower extrusion, and a lit bevel.
func reliefSVG(_ path:CGPath, name:String, top:String, bottom:String, side:String)->String {
    let d=svgPath(path), bounds=path.boundingBoxOfPath
    var result="<defs><linearGradient id=\"\(name)\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"\(bounds.maxY)\" x2=\"0\" y2=\"\(bounds.minY)\"><stop stop-color=\"\(top)\"/><stop offset=\"1\" stop-color=\"\(bottom)\"/></linearGradient></defs>"
    for width in [14,10,6] {
        result += "<path transform=\"translate(1 -7)\" fill=\"#10292D\" fill-opacity=\"0.08\" stroke=\"#10292D\" stroke-opacity=\"0.08\" stroke-width=\"\(width)\" stroke-linejoin=\"round\" d=\"\(d)\"/>"
    }
    result += "<path transform=\"translate(0 -4)\" fill=\"\(side)\" d=\"\(d)\"/>"
    result += "<path fill=\"url(#\(name))\" stroke=\"\(side)\" stroke-width=\"1.5\" stroke-linejoin=\"round\" d=\"\(d)\"/>"
    result += "<clipPath id=\"\(name)Clip\"><path d=\"\(d)\"/></clipPath><g clip-path=\"url(#\(name)Clip)\"><path transform=\"translate(0 -1.6)\" fill=\"none\" stroke=\"white\" stroke-opacity=\"0.48\" stroke-width=\"3.2\" d=\"\(d)\"/></g>"
    return result
}
let svg="""
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<g transform="translate(0 1024) scale(1 -1)">
\(reliefSVG(word,name:"tex",top:"#FFFFFF",bottom:"#DCE1E2",side:"#8B999C"))
</g></svg>
"""
try svg.write(to:asset.appendingPathComponent("Lettering.svg"),atomically:true,encoding:.utf8)
let iconset=root.appendingPathComponent("Artwork/TeXShop.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
func png(_ pixels:Int, fullBleed:Bool = false)->Data {
    let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let ctx=NSGraphicsContext(bitmapImageRep:b)!.cgContext
    ctx.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
    let shape=fullBleed ? CGPath(rect:CGRect(x:0,y:0,width:1024,height:1024),transform:nil) : CGPath(roundedRect:CGRect(x:100,y:100,width:824,height:824),cornerWidth:185,cornerHeight:185,transform:nil)
    ctx.saveGState();ctx.addPath(shape);ctx.clip()
    let colors=[CGColor(srgbRed:180/255,green:199/255,blue:207/255,alpha:1),CGColor(srgbRed:74/255,green:102/255,blue:105/255,alpha:1)]
    let gr=CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors as CFArray,locations:[0,1])!
    ctx.drawLinearGradient(gr,start:CGPoint(x:512,y:fullBleed ? 1024 : 924),end:CGPoint(x:512,y:fullBleed ? 0 : 100),options:[]);ctx.restoreGState()
    if !fullBleed { ctx.translateBy(x:100,y:100);ctx.scaleBy(x:824/1024,y:824/1024) }
    func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->CGColor {
        CGColor(srgbRed:r/255,green:g/255,blue:b/255,alpha:a)
    }
    func relief(_ path:CGPath,top:CGColor,bottom:CGColor,side:CGColor) {
        for width:CGFloat in [14,10,6] {
            ctx.saveGState();ctx.translateBy(x:1,y:-7)
            ctx.setFillColor(color(16,41,45,0.08));ctx.setStrokeColor(color(16,41,45,0.08))
            ctx.setLineWidth(width);ctx.setLineJoin(.round);ctx.addPath(path);ctx.drawPath(using:.fillStroke);ctx.restoreGState()
        }
        ctx.saveGState();ctx.translateBy(x:0,y:-4);ctx.setFillColor(side);ctx.addPath(path);ctx.fillPath();ctx.restoreGState()
        ctx.saveGState();ctx.addPath(path);ctx.clip()
        let bounds=path.boundingBoxOfPath
        let gradient=CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:[top,bottom] as CFArray,locations:[0,1])!
        ctx.drawLinearGradient(gradient,start:CGPoint(x:0,y:bounds.maxY),end:CGPoint(x:0,y:bounds.minY),options:[]);ctx.restoreGState()
        ctx.setStrokeColor(side);ctx.setLineWidth(1.5);ctx.setLineJoin(.round);ctx.addPath(path);ctx.strokePath()
        ctx.saveGState();ctx.addPath(path);ctx.clip();ctx.translateBy(x:0,y:-1.6)
        ctx.setStrokeColor(color(255,255,255,0.48));ctx.setLineWidth(3.2);ctx.addPath(path);ctx.strokePath();ctx.restoreGState()
    }
    relief(word,top:color(255,255,255),bottom:color(220,225,226),side:color(139,153,156))
    return b.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
 try png(size).write(to:iconset.appendingPathComponent("icon_\(size)x\(size).png"))
 try png(size*2).write(to:iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try png(1024).write(to:root.appendingPathComponent("Artwork/Icon-preview.png"))
try png(1024,fullBleed:true).write(to:root.appendingPathComponent("Artwork/GitHub-avatar.png"))
print("Centered TeX outline; Icon Composer layers, legacy PNGs, and web avatar generated.")
