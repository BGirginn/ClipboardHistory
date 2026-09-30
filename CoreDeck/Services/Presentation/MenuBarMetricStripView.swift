import AppKit

@MainActor
final class MenuBarMetricStripView: NSView {
    private let stackView = NSStackView()
    private var segmentViews: [MenuBarMetricID: MenuBarMetricSegmentView] = [:]
    private(set) var segments: [MenuBarMetricSegmentState] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 5
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(_ newSegments: [MenuBarMetricSegmentState]) {
        let newIDs = newSegments.map(\.metric)
        if newIDs != segments.map(\.metric) {
            stackView.arrangedSubviews.forEach {
                stackView.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            segmentViews.removeAll(keepingCapacity: true)
            for segment in newSegments {
                let view = MenuBarMetricSegmentView(state: segment)
                segmentViews[segment.metric] = view
                stackView.addArrangedSubview(view)
            }
        } else {
            for segment in newSegments {
                segmentViews[segment.metric]?.update(segment)
            }
        }
        segments = newSegments
        invalidateIntrinsicContentSize()
    }

    func segmentView(for metric: MenuBarMetricID) -> MenuBarMetricSegmentView? {
        segmentViews[metric]
    }

    override var intrinsicContentSize: NSSize {
        let segmentWidth = segments.reduce(CGFloat.zero) { $0 + $1.width }
        let spacing = CGFloat(max(segments.count - 1, 0)) * stackView.spacing
        return NSSize(width: segmentWidth + spacing, height: NSStatusBar.system.thickness)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
