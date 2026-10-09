import AppKit

// Read-only raster check: a wider preview must add margins, not stretch the art.
func measure(_ path: String) throws -> [String: Int] {
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path)))!
    var left=bitmap.pixelsWide, top=bitmap.pixelsHigh, right=0, bottom=0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
            if min(c.redComponent,c.greenComponent,c.blueComponent) < 0.78 && c.alphaComponent > 0.9 {
                left=min(left,x); right=max(right,x); top=min(top,y); bottom=max(bottom,y)
            }
        }
    }
    precondition(right>left && bottom>top, "The artwork must not be empty")
    return ["imageWidth":bitmap.pixelsWide,"imageHeight":bitmap.pixelsHigh,
            "left":left,"top":top,"width":right-left+1,"height":bottom-top+1]
}
let dir=CommandLine.arguments[1]
let normal=try measure(dir+"/controller-artwork.png")
let wide=try measure(dir+"/controller-artwork-wide.png")
precondition(normal["width"] == wide["width"] && normal["height"] == wide["height"], "The controller was stretched")
let result: [String: Any] = ["normal":normal,"wide":wide,"uniformScaleVerified":true]
let json=try JSONSerialization.data(withJSONObject:result, options:[.prettyPrinted,.sortedKeys])
print(String(decoding:json,as:UTF8.self))
