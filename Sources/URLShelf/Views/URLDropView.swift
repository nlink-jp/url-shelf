import AppKit

/// Transparent overlay on the status item's button that accepts dragged URLs.
///
/// `NSStatusBarButton` cannot be subclassed or given a dragging delegate, so the
/// drop target is a subview layered over it. Clicks are forwarded to the button
/// so the menu still opens — the overlay is invisible in every sense except to
/// the drag.
@MainActor
final class URLDropView: NSView {
    var onDrop: ((URL) -> Bool)?
    weak var button: NSStatusBarButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.URL, .fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) {
        button?.performClick(nil)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.url(from: sender) != nil else { return [] }
        button?.highlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        button?.highlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        guard let url = Self.url(from: sender) else { return false }
        return onDrop?(url) ?? false
    }

    /// Browsers put a real URL on the pasteboard; dragging selected text gives a
    /// string that may or may not be one.
    static func url(from sender: NSDraggingInfo) -> URL? {
        let pasteboard = sender.draggingPasteboard

        if let url = NSURL(from: pasteboard) as URL?, url.scheme != nil {
            return url
        }
        if let text = pasteboard.string(forType: .string) {
            return WebURL.parse(text)
        }
        return nil
    }
}
