// logic-test
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// カメラとライブラリの写真を、アップロード用のJPEGに作り直す（RCNO-30）。
///
/// 元のファイルをそのまま送ると、EXIF・XMPのGPS座標や撮影機材の情報も一緒に共有される。
/// ここでは画素だけを取り出して新しいJPEGを書くので、メタデータは一切引き継がない。
/// 都市を共有するかどうかは、利用者が投稿画面で明示的に選んだ値だけで決める（RCNO-29）。
enum PhotoImagePreparer {
    /// 長辺の上限。ボードとマップの表示には十分で、10MBの上限（RCNO-35）より十分小さくなる。
    static let maxPixelSize = 2048
    /// Storage の photos バケットの上限は10MB。余裕を持たせる。
    static let maxBytes = 9 * 1024 * 1024
    private static let qualities: [CGFloat] = [0.85, 0.7, 0.55]

    static func prepare(_ original: Data) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw PhotoPreparationError.unreadable }

        // 向き（EXIF Orientation）は画素に反映してから捨てる。メタデータを捨てても正しい向きで表示される。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw PhotoPreparationError.unreadable }

        for quality in qualities {
            let data = try encodeJPEG(image, quality: quality)
            if data.count <= maxBytes {
                return PreparedPhoto(data: data, width: image.width, height: image.height)
            }
        }
        throw PhotoPreparationError.tooLarge
    }

    /// 画像に位置情報が含まれているか。EXIFのGPS辞書と、XMPのGPS項目の両方を調べる。
    static func containsLocation(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return false }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           properties[kCGImagePropertyGPSDictionary] != nil {
            return true
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return false }
        var found = false
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, [kCGImageMetadataEnumerateRecursively: true] as CFDictionary) { _, tag in
            let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
            if name.hasPrefix("GPS") {
                found = true
                return false
            }
            return true
        }
        return found
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw PhotoPreparationError.unreadable }

        // 画像だけを書く。元のプロパティ（EXIF、GPS、TIFF、XMP）は渡さない。
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw PhotoPreparationError.unreadable }
        return output as Data
    }
}
