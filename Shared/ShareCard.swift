import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum ShareCard {
    static let size = CGSize(width: 1080, height: 1350)
    static let placeholderURL = URL(string: "https://hgsldswk-alt.github.io/before3pm-support/")!

    static func downloadURL(appStoreID: String?) -> URL {
        if let appStoreID, !appStoreID.isEmpty,
           appStoreID.utf8.allSatisfy({ (48...57).contains($0) }),
           let url = URL(string: "https://apps.apple.com/app/id" + appStoreID) { return url }
        return placeholderURL
    }

    static func qr(url: URL) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        return filter.outputImage
    }

    static func render(days: Int?, url: URL) -> UIImage? {
        guard let qr = qr(url: url), let code = CIContext().createCGImage(qr, from: qr.extent) else { return nil }
        let ink = UIColor(red: 31 / 255, green: 35 / 255, blue: 38 / 255, alpha: 1)
        let accent = UIColor(red: 88 / 255, green: 69 / 255, blue: 184 / 255, alpha: 1)
        let paper = UIColor(red: 247 / 255, green: 245 / 255, blue: 240 / 255, alpha: 1)
        let wash = UIColor(red: 238 / 255, green: 233 / 255, blue: 250 / 255, alpha: 1)
        let prep = UIColor(red: 133 / 255, green: 113 / 255, blue: 174 / 255, alpha: 1)
        let travel = UIColor(red: 214 / 255, green: 199 / 255, blue: 236 / 255, alpha: 1)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            paper.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))

            wash.setFill()
            UIBezierPath(roundedRect: CGRect(x: 72, y: 72, width: 936, height: 902), cornerRadius: 52).fill()
            draw(L.t("app.name"), at: CGRect(x: 126, y: 133, width: 820, height: 68),
                 font: .systemFont(ofSize: 42, weight: .semibold), color: accent)
            draw(L.t("share.headline"), at: CGRect(x: 126, y: 246, width: 820, height: 338),
                 font: .systemFont(ofSize: 111, weight: .bold), color: ink)
            if let days {
                draw(L.f("share.days", days), at: CGRect(x: 126, y: 628, width: 820, height: 116),
                     font: .systemFont(ofSize: 78, weight: .bold), color: accent)
            }
            draw(L.t("share.caption"), at: CGRect(x: 126, y: 771, width: 820, height: 105),
                 font: .systemFont(ofSize: 44, weight: .medium), color: accent)
            for (x, width, color) in [(126, 412, accent), (548, 136, prep), (694, 244, travel)] {
                color.setFill()
                UIBezierPath(roundedRect: CGRect(x: x, y: 893, width: width, height: 17), cornerRadius: 8).fill()
            }

            let codeFrame = CGRect(x: 774, y: 1010, width: 234, height: 234)
            UIColor.white.setFill()
            renderer.fill(codeFrame)
            let scale = max(1, Int(codeFrame.width) / (code.width + 8))
            let side = CGFloat(code.width * scale)
            let codeRect = CGRect(x: (codeFrame.midX - side / 2).rounded(.down),
                                  y: (codeFrame.midY - side / 2).rounded(.down), width: side, height: side)
            renderer.cgContext.saveGState()
            renderer.cgContext.interpolationQuality = .none
            UIImage(cgImage: code).draw(in: codeRect)
            renderer.cgContext.restoreGState()

            draw(L.t("share.hashtags"), at: CGRect(x: 76, y: 1067, width: 662, height: 100),
                 font: .systemFont(ofSize: 40, weight: .semibold), color: accent)
            draw(L.t("share.scan"), at: CGRect(x: 76, y: 1186, width: 662, height: 68),
                 font: .systemFont(ofSize: 33), color: ink)
        }
    }

    private static func draw(_ text: String, at rect: CGRect, font: UIFont, color: UIColor) {
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                               attributes: [.font: font, .foregroundColor: color], context: nil)
    }
}
