import Foundation

// ICNS is a length-prefixed container. Modern entries store PNG bytes directly.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
]
func length(_ value: Int) -> Data {
    let v = UInt32(value)
    return Data([UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)])
}
var payload = Data()
for (type, file) in entries {
    let image = try Data(contentsOf: folder.appendingPathComponent(file))
    payload.append(Data(type.utf8))
    payload.append(length(image.count + 8))
    payload.append(image)
}
var result = Data("icns".utf8)
result.append(length(payload.count + 8))
result.append(payload)
try result.write(to: output, options: .atomic)
