// ui/Theme.kt's OutlinedText (lines 108-124): text drawn twice, a dark outline and then the fill (the Mini Games titles).

import SwiftUI
import UIKit

/**
 * Text drawn twice: a dark outline, then the fill. Compose strokes it [size]/4 pixels wide, so here it is
 * size/(4 × the screen's scale) points: the same pixels. One line by default, cut short with "…" past [maxLines];
 * its lines [alignment]ed (Compose's textAlign).
 */
struct OutlinedText: UIViewRepresentable {
    let text: String
    var size: CGFloat = 22
    var fill: UIColor = .white
    var outline: UIColor = Palette.inkUI
    var maxLines = 1
    var alignment: NSTextAlignment = .natural
    /// A heading, for VoiceOver (its rotor goes from heading to heading).
    var isHeader = false

    init(_ text: String, size: CGFloat = 22, fill: UIColor = .white, outline: UIColor = Palette.inkUI,
         maxLines: Int = 1, alignment: NSTextAlignment = .natural, isHeader: Bool = false) {
        self.text = text
        self.size = size
        self.fill = fill
        self.outline = outline
        self.maxLines = maxLines
        self.alignment = alignment
        self.isHeader = isHeader
    }

    func makeUIView(context: Context) -> OutlinedLabel {
        let label = OutlinedLabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: OutlinedLabel, context: Context) {
        label.configure(
            text: text, size: size, fill: fill, outline: outline, maxLines: maxLines, alignment: alignment,
            scale: context.environment.displayScale,
            category: UIContentSizeCategory(context.environment.dynamicTypeSize))
        label.accessibilityTraits = isHeader ? [.staticText, .header] : .staticText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: OutlinedLabel, context: Context) -> CGSize? {
        var width = proposal.width ?? .greatestFiniteMagnitude
        if !width.isFinite { width = .greatestFiniteMagnitude }
        return label.fitting(width: width)
    }
}

/// The label: measured as a UILabel (one accessibility element with its text), drawn in two passes.
final class OutlinedLabel: UILabel {
    private var stroke: CGFloat = 0
    private var outline: UIColor = Palette.inkUI
    private var fill: UIColor = .white
    /// Room around the text for the half of the outline outside the letters.
    private var pad: CGFloat { ceil(stroke / 2) }

    func configure(
        text: String, size: CGFloat, fill: UIColor, outline: UIColor, maxLines: Int,
        alignment: NSTextAlignment = .natural, scale: CGFloat, category: UIContentSizeCategory
    ) {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let font = UIFontMetrics.default.scaledFont(for: Lilita.uiFont(size), compatibleWith: traits)
        let stroke = size / (4 * max(scale, 1))
        guard text != self.text || font != self.font || fill != self.fill || outline != self.outline
            || maxLines != numberOfLines || stroke != self.stroke || alignment != textAlignment else { return }
        self.font = font
        self.text = text
        self.fill = fill
        self.outline = outline
        self.stroke = stroke
        textColor = fill
        numberOfLines = maxLines
        textAlignment = alignment
        lineBreakMode = .byTruncatingTail
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    /**
     * Its size within [width]: the text's lines (at least one, as an empty Compose Text has) and the outline. Text
     * that doesn't fit on one line takes the whole width, as a Compose Text does (it lays a wrapped paragraph out at
     * its maximum width), so its lines start at the left edge rather than in a block centred under the circle.
     */
    func fitting(width: CGFloat) -> CGSize {
        let inner = max(width - 2 * pad, 0)
        var size = super.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude))
        let oneLine = super.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        size.width = ceil(oneLine.width) > inner ? inner : min(ceil(size.width), inner)
        size.height = max(ceil(size.height), ceil(font.lineHeight))
        return CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { fitting(width: size.width) }

    override var intrinsicContentSize: CGSize { fitting(width: .greatestFiniteMagnitude) }

    override func drawText(in rect: CGRect) {
        let inner = rect.insetBy(dx: pad, dy: pad)
        var box = textRect(forBounds: inner, limitedToNumberOfLines: numberOfLines)
        box.origin.y = inner.minY + max((inner.height - box.height) / 2, 0)
        box.origin.x = inner.minX
        box.size.width = inner.width
        let text = self.text ?? ""
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = textAlignment
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        if let context = UIGraphicsGetCurrentContext() {
            // Compose's Stroke: miter joins, miter limit 4.
            context.setLineJoin(.miter)
            context.setMiterLimit(4)
        }
        if stroke > 0 {
            let outlined = NSAttributedString(string: text, attributes: [
                .font: font as UIFont, .paragraphStyle: paragraph, .foregroundColor: outline,
                .strokeColor: outline, .strokeWidth: stroke / font.pointSize * 100,
            ])
            outlined.draw(with: box, options: options, context: nil)
        }
        let filled = NSAttributedString(string: text, attributes: [
            .font: font as UIFont, .paragraphStyle: paragraph, .foregroundColor: fill,
        ])
        filled.draw(with: box, options: options, context: nil)
    }
}
