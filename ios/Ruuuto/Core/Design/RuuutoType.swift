import CoreText
import SwiftUI
import UIKit

@MainActor
enum RuuutoType {
    static func rounded(_ style: Font.TextStyle) -> Font {
        let name = "RoundedMplus1c-ExtraBold"
        guard registered.contains(name) else { return .system(style, design: .rounded) }
        return .custom(name, size: metrics(for: style).base, relativeTo: style)
    }

    static func body(_ style: Font.TextStyle) -> Font {
        let name = "NotoSansJP-Thin"
        guard registered.contains(name) else { return .system(style) }

        let text = metrics(for: style)
        let size = UIFontMetrics(forTextStyle: text.category).scaledValue(for: text.base)
        let base = CTFontCreateWithName(name as CFString, size, nil)
        let regular = CTFontDescriptorCreateCopyWithVariation(
            CTFontCopyFontDescriptor(base),
            NSNumber(value: 0x7767_6874), // OpenType weight axis, "wght"
            400
        )
        return Font(CTFontCreateWithFontDescriptor(regular, size, nil))
    }

    static func hand(_ style: Font.TextStyle) -> Font {
        let name = "YuseiMagic-Regular"
        guard registered.contains(name) else { return .system(style, design: .rounded) }
        return .custom(name, size: metrics(for: style).base, relativeTo: style)
    }

    private static let registered: Set<String> = {
        let resourceNames = ["MPLUSRounded1c-ExtraBold", "NotoSansJP-Variable", "YuseiMagic-Regular"]
        return Set(resourceNames.flatMap { resource -> [String] in
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf")
                ?? Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Fonts")
            else { return [] }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            return descriptors.compactMap { descriptor in
                guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                      UIFont(name: name, size: 17) != nil
                else { return nil }
                return name
            }
        })
    }()

    private static func metrics(for style: Font.TextStyle) -> (category: UIFont.TextStyle, base: CGFloat) {
        let category: UIFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        let defaults = UITraitCollection(preferredContentSizeCategory: .large)
        return (category, UIFont.preferredFont(forTextStyle: category, compatibleWith: defaults).pointSize)
    }
}
