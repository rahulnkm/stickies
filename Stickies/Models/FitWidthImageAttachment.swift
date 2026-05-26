import AppKit

/// NSTextAttachment that always scales its image to the line fragment width,
/// preserving aspect ratio. AppKit calls attachmentBounds(...) on every layout
/// pass — so window resize → image refit, no extra plumbing.
final class FitWidthImageAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        guard let image = self.image, image.size.width > 0 else {
            return super.attachmentBounds(for: textContainer,
                                          proposedLineFragment: lineFrag,
                                          glyphPosition: position,
                                          characterIndex: charIndex)
        }
        // Prefer the container's bounded width when present — proposedLineFragment
        // can come through unbounded (CGFloat.greatestFiniteMagnitude) before the
        // container settles, which would let the image render at native size.
        var width = lineFrag.width
        if let container = textContainer {
            let containerWidth = container.size.width
            if containerWidth > 0, containerWidth < CGFloat.greatestFiniteMagnitude {
                width = (width > 0) ? min(width, containerWidth) : containerWidth
            }
        }
        guard width > 0, width.isFinite else {
            return super.attachmentBounds(for: textContainer,
                                          proposedLineFragment: lineFrag,
                                          glyphPosition: position,
                                          characterIndex: charIndex)
        }
        let aspect = image.size.height / image.size.width
        return CGRect(x: 0, y: 0, width: width, height: width * aspect)
    }
}
