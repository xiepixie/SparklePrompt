import AppKit

extension NSColor {
    convenience init?(hex: String) {
        let hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hexString)
        if hexString.hasPrefix("#") {
            scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
        }

        var color: UInt64 = 0
        guard scanner.scanHexInt64(&color) else { return nil }

        let r, g, b, a: CGFloat
        let cleanHex = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        if cleanHex.count == 8 {
            r = CGFloat((color & 0xff000000) >> 24) / 255
            g = CGFloat((color & 0x00ff0000) >> 16) / 255
            b = CGFloat((color & 0x0000ff00) >> 8) / 255
            a = CGFloat(color & 0x000000ff) / 255
        } else if cleanHex.count == 6 {
            r = CGFloat((color & 0xff0000) >> 16) / 255
            g = CGFloat((color & 0x00ff00) >> 8) / 255
            b = CGFloat(color & 0x0000ff) / 255
            a = 1.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    func toHex() -> String? {
        guard let rgbColor = usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        let a = Int(round(rgbColor.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
