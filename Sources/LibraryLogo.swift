import SwiftUI

struct LibraryLogo: View {
    let platform: GamePlatform

    var body: some View {
        Group {
            if platform == .psp {
                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    context.rotate(by: .degrees(-18))
                    var outline = Path(roundedRect: CGRect(x: -46, y: -21, width: 92, height: 42), cornerRadius: 14)
                    // Screen and controls are cut out of a single silhouette.
                    outline.addRoundedRect(in: CGRect(x: -24, y: -15, width: 48, height: 28), cornerSize: CGSize(width: 2, height: 2))
                    outline.move(to: CGPoint(x: -37, y: -12))
                    for point in [CGPoint(x: -33, y: -12), CGPoint(x: -33, y: -8),
                                  CGPoint(x: -29, y: -8), CGPoint(x: -29, y: -4),
                                  CGPoint(x: -33, y: -4), CGPoint(x: -33, y: 0),
                                  CGPoint(x: -37, y: 0), CGPoint(x: -37, y: -4),
                                  CGPoint(x: -41, y: -4), CGPoint(x: -41, y: -8),
                                  CGPoint(x: -37, y: -8)] {
                        outline.addLine(to: point)
                    }
                    outline.closeSubpath()
                    for center in [CGPoint(x: 35, y: -12), CGPoint(x: 41, y: -6),
                                   CGPoint(x: 35, y: 0), CGPoint(x: 29, y: -6)] {
                        outline.addEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
                    }
                    outline.addEllipse(in: CGRect(x: -38, y: 6, width: 6, height: 6))
                    for x in [-20.0, -13.0, 12.0, 19.0] {
                        outline.addRoundedRect(in: CGRect(x: x, y: 16, width: 4, height: 1.5), cornerSize: CGSize(width: 0.75, height: 0.75))
                    }
                    context.fill(outline, with: .foreground, style: FillStyle(eoFill: true))
                }
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 58))
            }
        }
        .frame(width: 118, height: 104)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }
}
