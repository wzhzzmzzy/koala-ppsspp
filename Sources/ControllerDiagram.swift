import SwiftUI

// All artwork coordinates use the reference's 596 × 335 plane. Keep a single
// scale for both axes: resizing a help panel must never stretch the controller.
struct ControllerArtwork: View {
    var playStation = false
    static let size = CGSize(width: 596, height: 335)
    static let centers: [PadPart: CGPoint] = [
        .lt: .init(x: 187, y: 77), .lb: .init(x: 161, y: 103),
        .rt: .init(x: 397, y: 77), .rb: .init(x: 425, y: 103),
        .leftStick: .init(x: 168, y: 191), .l3: .init(x: 168, y: 191),
        .dpad: .init(x: 238, y: 233), .back: .init(x: 249, y: 174),
        .guide: .init(x: 296, y: 173), .start: .init(x: 342, y: 174),
        .rightStick: .init(x: 352, y: 248), .r3: .init(x: 352, y: 248),
        .y: .init(x: 416, y: 146), .b: .init(x: 443, y: 172),
        .a: .init(x: 410, y: 200), .x: .init(x: 383, y: 174)
    ]
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.size.width, size.height / Self.size.height)
            context.translateBy(x: (size.width - Self.size.width * scale) / 2,
                                y: (size.height - Self.size.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            draw(&context)
        }.aspectRatio(Self.size, contentMode: .fit).accessibilityHidden(true)
    }
    func draw(_ c: inout GraphicsContext) {
        let edge = Color(white: 0.12)
        func fill(_ path: Path, top: Double, bottom: Double, from: CGPoint, to: CGPoint) {
            c.fill(path, with: .linearGradient(Gradient(colors: [Color(white: top), Color(white: bottom)]), startPoint: from, endPoint: to))
            c.stroke(path, with: .color(edge), lineWidth: 1.6)
        }
        // Triggers extend just above the sloping shoulders, rather than sitting
        // on top of the shell as separate tall rectangular buttons.
        for x: CGFloat in [187, 397] {
            var trigger = Path()
            trigger.addLines([.init(x: x-16, y: 91), .init(x: x-10, y: 66), .init(x: x-6, y: 63), .init(x: x+10, y: 63), .init(x: x+15, y: 91)])
            trigger.closeSubpath()
            fill(trigger, top: 0.39, bottom: 0.24, from: .init(x: x-8, y: 63), to: .init(x: x+12, y: 92))
            var groove = Path(); groove.move(to: .init(x: x-5, y: 68)); groove.addLine(to: .init(x: x-8, y: 83))
            c.stroke(groove, with: .color(.white.opacity(0.17)), lineWidth: 2)
        }
        let bridge = Path(roundedRect: CGRect(x: 246, y: 97, width: 98, height: 32), cornerRadius: 15)
        fill(bridge, top: 0.36, bottom: 0.27, from: .init(x: 290, y: 97), to: .init(x: 290, y: 126))
        c.stroke(Path(roundedRect: CGRect(x: 255, y: 101, width: 80, height: 22), cornerRadius: 11), with: .color(.black.opacity(0.25)), lineWidth: 1)
        var shell = Path()
        shell.move(to: .init(x: 128, y: 121))
        shell.addCurve(to: .init(x: 192, y: 86), control1: .init(x: 140, y: 98), control2: .init(x: 172, y: 88))
        shell.addCurve(to: .init(x: 246, y: 110), control1: .init(x: 210, y: 86), control2: .init(x: 227, y: 105))
        shell.addCurve(to: .init(x: 340, y: 111), control1: .init(x: 273, y: 114), control2: .init(x: 316, y: 114))
        shell.addCurve(to: .init(x: 394, y: 86), control1: .init(x: 362, y: 104), control2: .init(x: 375, y: 84))
        shell.addCurve(to: .init(x: 456, y: 121), control1: .init(x: 413, y: 89), control2: .init(x: 443, y: 98))
        shell.addCurve(to: .init(x: 489, y: 258), control1: .init(x: 473, y: 159), control2: .init(x: 490, y: 221))
        shell.addCurve(to: .init(x: 460, y: 309), control1: .init(x: 489, y: 284), control2: .init(x: 482, y: 304))
        shell.addCurve(to: .init(x: 416, y: 300), control1: .init(x: 445, y: 314), control2: .init(x: 430, y: 308))
        shell.addCurve(to: .init(x: 361, y: 260), control1: .init(x: 397, y: 291), control2: .init(x: 377, y: 274))
        shell.addCurve(to: .init(x: 220, y: 259), control1: .init(x: 322, y: 250), control2: .init(x: 263, y: 250))
        shell.addCurve(to: .init(x: 157, y: 300), control1: .init(x: 203, y: 273), control2: .init(x: 178, y: 291))
        shell.addCurve(to: .init(x: 111, y: 301), control1: .init(x: 140, y: 311), control2: .init(x: 123, y: 314))
        shell.addCurve(to: .init(x: 97, y: 248), control1: .init(x: 97, y: 290), control2: .init(x: 94, y: 272))
        shell.addCurve(to: .init(x: 128, y: 121), control1: .init(x: 100, y: 203), control2: .init(x: 114, y: 151))
        shell.closeSubpath()
        fill(shell, top: 0.42, bottom: 0.34, from: .init(x: 294, y: 100), to: .init(x: 294, y: 310))
        // Two shallow shell seams also define the bumpers' sloped, integrated shape.
        func seam(_ y: CGFloat) -> Path {
            var p = Path(); p.move(to: .init(x: 128, y: 121+y))
            p.addCurve(to: .init(x: 192, y: 100+y), control1: .init(x: 146, y: 115+y), control2: .init(x: 176, y: 100+y))
            p.addCurve(to: .init(x: 247, y: 127+y), control1: .init(x: 211, y: 99+y), control2: .init(x: 231, y: 123+y))
            p.addCurve(to: .init(x: 341, y: 128+y), control1: .init(x: 275, y: 132+y), control2: .init(x: 313, y: 131+y))
            p.addCurve(to: .init(x: 394, y: 101+y), control1: .init(x: 357, y: 120+y), control2: .init(x: 376, y: 99+y))
            p.addCurve(to: .init(x: 456, y: 121+y), control1: .init(x: 415, y: 102+y), control2: .init(x: 440, y: 114+y))
            return p
        }
        c.stroke(seam(-6), with: .color(.white.opacity(0.14)), lineWidth: 1)
        c.stroke(seam(0), with: .color(edge.opacity(0.85)), lineWidth: 1.5)
        c.stroke(seam(7), with: .color(edge.opacity(0.65)), lineWidth: 1)
        drawStick(&c, socket: .init(x: 175, y: 176), cap: Self.centers[.leftStick]!, radius: 40)
        drawStick(&c, socket: .init(x: 349, y: 228), cap: Self.centers[.rightStick]!, radius: 38)
        let dpad = Path(ellipseIn: CGRect(x: 197, y: 199, width: 80, height: 64))
        fill(dpad, top: 0.31, bottom: 0.23, from: .init(x: 237, y: 199), to: .init(x: 237, y: 263))
        c.stroke(Path(ellipseIn: CGRect(x: 202, y: 203, width: 70, height: 56)), with: .color(.white.opacity(0.18)), lineWidth: 1)
        var cross = Path()
        cross.addLines([(226.0,210.0),(247,209),(249,224),(266,223),(269,242),(249,244),(250,258),(227,259),(227,244),(207,245),(207,226),(225,225)].map { CGPoint(x:$0.0,y:$0.1) })
        cross.closeSubpath()
        fill(cross, top: 0.47, bottom: 0.33, from: .init(x: 238, y: 209), to: .init(x: 238, y: 259))
        for part in [PadPart.back, .start] {
            let p = Self.centers[part]!
            let button = Path(ellipseIn: CGRect(x: p.x-6, y: p.y-5, width: 12, height: 10))
            fill(button, top: 0.43, bottom: 0.25, from: .init(x: p.x,y:p.y-5), to: .init(x:p.x,y:p.y+5))
        }
        let guide = Path(ellipseIn: CGRect(x: 274,y: 151,width: 44,height: 43))
        fill(guide, top: 0.58, bottom: 0.31, from: .init(x: 296,y:151), to: .init(x:296,y:194))
        let center = Path(ellipseIn: CGRect(x: 279,y: 156,width: 34,height: 33))
        fill(center, top: 0.88, bottom: 0.67, from: .init(x: 296,y:156), to: .init(x:296,y:189))
        c.draw(Text(Image(systemName: "house.fill")).font(.system(size: 18,weight: .regular)).foregroundColor(Color(white:0.32)), at: Self.centers[.guide]!)
        for (part, color) in [(PadPart.a,Color(red:0.47,green:0.72,blue:0.29)),(.b,Color(red:0.82,green:0.23,blue:0.23)),(.x,Color(red:0.21,green:0.65,blue:0.82)),(.y,Color(red:0.91,green:0.83,blue:0.27))] {
            let p = Self.centers[part]!
            let button = Path(ellipseIn: CGRect(x:p.x-14,y:p.y-13,width:28,height:26))
            c.fill(button.offsetBy(dx:0,dy:2), with:.color(edge))
            c.fill(button, with:.linearGradient(Gradient(colors:[color, color.opacity(0.85)]), startPoint:.init(x:p.x,y:p.y-13), endPoint:.init(x:p.x,y:p.y+13)))
            c.stroke(button, with:.color(edge), lineWidth:1.4)
            c.stroke(Path(ellipseIn:CGRect(x:p.x-10,y:p.y-10,width:20,height:19)),with:.color(.white.opacity(0.30)),lineWidth:0.8)
            c.draw(Text(part.title(playStation:playStation)).font(.system(size:16,weight:.medium,design:.rounded)).foregroundColor(Color(white:0.10)), at:p)
        }
    }
    private func drawStick(_ c: inout GraphicsContext, socket: CGPoint, cap: CGPoint, radius: CGFloat) {
        let edge = Color(white:0.16)
        for (inset, shade) in [(0.0,0.34),(6.0,0.39),(12.0,0.25)] {
            let r = radius-inset
            let ring = Path(ellipseIn:CGRect(x:socket.x-r,y:socket.y-r*0.83,width:r*2,height:r*1.66))
            c.fill(ring,with:.color(Color(white:shade))); c.stroke(ring,with:.color(edge),lineWidth:1.2)
        }
        let base = Path(ellipseIn:CGRect(x:cap.x-28,y:cap.y-26,width:56,height:46))
        c.fill(base,with:.color(Color(white:0.31)));c.stroke(base,with:.color(edge),lineWidth:1.5)
        let top = Path(ellipseIn:CGRect(x:cap.x-25,y:cap.y-19,width:50,height:39))
        c.fill(top,with:.linearGradient(Gradient(colors:[Color(white:0.43),Color(white:0.34)]),startPoint:.init(x:cap.x,y:cap.y-19),endPoint:.init(x:cap.x,y:cap.y+20)))
        c.stroke(top,with:.color(edge),lineWidth:1.4)
        c.stroke(Path(ellipseIn:CGRect(x:cap.x-20,y:cap.y-14,width:40,height:29)),with:.color(edge.opacity(0.6)),lineWidth:1)
    }
}

struct ControllerDiagram: View {
    var snapshot: MappingSnapshot?
    var device: Int
    var playStation: Bool
    @Binding var selection: PadPart
    private let accent = Color(red:0.77,green:0.20,blue:0.23)
    private static let plane = CGSize(width:900,height:438)
    private static let artScale: CGFloat = 1.12
    private static let artOrigin = CGPoint(x:119,y:25)
    private static let captions: [PadPart: CGPoint] = [
        .lb:.init(x:199,y:26), .lt:.init(x:343,y:26), .rt:.init(x:556,y:26), .rb:.init(x:700,y:26),
        .leftStick:.init(x:76,y:239), .back:.init(x:76,y:155), .dpad:.init(x:76,y:317),
        .y:.init(x:824,y:142), .b:.init(x:824,y:204), .x:.init(x:824,y:266), .a:.init(x:824,y:328),
        .l3:.init(x:228,y:412), .guide:.init(x:440,y:412), .start:.init(x:450,y:80),
        .r3:.init(x:650,y:412), .rightStick:.init(x:824,y:397)
    ]
    // Leaders terminate at the edge of each control, leaving its glyph readable.
    private static let tips: [PadPart: CGPoint] = [
        .lt:.init(x:187,y:69), .lb:.init(x:158,y:99), .rt:.init(x:397,y:69), .rb:.init(x:427,y:99),
        .leftStick:.init(x:144,y:189), .l3:.init(x:169,y:211), .dpad:.init(x:215,y:241),
        .back:.init(x:243,y:171), .guide:.init(x:291,y:194), .start:.init(x:342,y:169),
        .rightStick:.init(x:376,y:247), .r3:.init(x:352,y:267),
        .y:.init(x:429,y:142), .b:.init(x:457,y:172), .x:.init(x:397,y:176), .a:.init(x:423,y:205)
    ]
    private static func artPoint(_ p: CGPoint) -> CGPoint {
        .init(x:artOrigin.x+p.x*artScale, y:artOrigin.y+p.y*artScale)
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width/Self.plane.width,geometry.size.height/Self.plane.height)
            let origin = CGPoint(x:(geometry.size.width-Self.plane.width*scale)/2,y:(geometry.size.height-Self.plane.height*scale)/2)
            ZStack {
                Canvas { context, _ in
                    context.translateBy(x:origin.x,y:origin.y)
                    context.scaleBy(x:scale,y:scale)
                    var art = context
                    art.translateBy(x:Self.artOrigin.x,y:Self.artOrigin.y)
                    art.scaleBy(x:Self.artScale,y:Self.artScale)
                    ControllerArtwork(playStation:playStation).draw(&art)
                    for part in PadPart.allCases {
                        guard let tip=Self.tips[part], let caption=Self.captions[part] else { continue }
                        let anchor=Self.artPoint(tip)
                        var line=Path();line.move(to:anchor)
                        var end=caption
                        if caption.x < 100 { end.x += 69; line.addLine(to:.init(x:179,y:caption.y)) }
                        else if caption.x > 800 { end.x -= 73; line.addLine(to:.init(x:718,y:caption.y)) }
                        else { end.y += caption.y < 100 ? 22 : -24 }
                        line.addLine(to:end)
                        context.stroke(line,with:.color(accent.opacity(selection == part ? 1 : 0.56)),style:StrokeStyle(lineWidth:selection == part ? 1.7 : 1.1,lineCap:.round,lineJoin:.round))
                        context.fill(Path(ellipseIn:CGRect(x:anchor.x-1.8,y:anchor.y-1.8,width:3.6,height:3.6)),with:.color(accent))
                    }
                }.accessibilityHidden(true)
                ForEach(PadPart.allCases) { part in
                    if let caption=Self.captions[part] {
                        Button { selection=part } label: {
                            VStack(alignment:.leading,spacing:3) {
                                Text(part.title(playStation:playStation)).font(.system(size:12,weight:.semibold))
                                Text(summary(part)).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width:126,alignment:.leading).padding(6)
                                .background(selection == part ? accent.opacity(0.07) : .clear,in:RoundedRectangle(cornerRadius:6))
                                .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(selection == part ? accent.opacity(0.35) : .clear))
                        }.buttonStyle(.plain).position(x:origin.x+caption.x*scale,y:origin.y+caption.y*scale)
                            .help(summary(part)).accessibilityLabel("\(part.title(playStation:playStation))，\(summary(part))；查看完整映射")
                    }
                    if let center=ControllerArtwork.centers[part], part != .l3 && part != .r3 {
                        let p=Self.artPoint(center)
                        Button { selection=part } label: {
                            Ellipse().fill(.white.opacity(0.001))
                                .frame(width:(part == .leftStick || part == .rightStick ? 53 : 28)*Self.artScale*scale,height:(part == .leftStick || part == .rightStick ? 40 : 26)*Self.artScale*scale)
                        }.buttonStyle(.plain).position(x:origin.x+p.x*scale,y:origin.y+p.y*scale)
                            .help(part.title(playStation:playStation)).accessibilityLabel("查看\(part.title(playStation:playStation))的映射")
                    }
                }
            }
        }.frame(height:438)
    }
    private func summary(_ part: PadPart) -> String {
        snapshot?.summary(codes:part.codes,device:device) ?? "等待配置"
    }
}
