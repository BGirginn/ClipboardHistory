import AppKit

@MainActor
final class MenuBarMetricSegmentView: NSView {
    private enum Presentation: Equatable {
        case stacked
        case iconAndValue
        case valueOnly
    }

    private let imageView = NSImageView()
    private let leadingLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private var widthConstraint: NSLayoutConstraint?
    private var activeLayoutConstraints: [NSLayoutConstraint] = []
    private var presentation: Presentation?
    private(set) var state: MenuBarMetricSegmentState
    private(set) var mutationCount = 0

    init(state: MenuBarMetricSegmentState) {
        self.state = state
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        leadingLabel.translatesAutoresizingMaskIntoConstraints = false
        leadingLabel.font = .systemFont(ofSize: 8, weight: .regular)
        leadingLabel.textColor = .labelColor
        leadingLabel.alignment = .center
        leadingLabel.lineBreakMode = .byClipping
        leadingLabel.maximumNumberOfLines = 1
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .center
        valueLabel.lineBreakMode = .byClipping
        valueLabel.maximumNumberOfLines = 1

        addSubview(imageView)
        addSubview(leadingLabel)
        addSubview(valueLabel)
        widthConstraint = widthAnchor.constraint(equalToConstant: state.width)
        widthConstraint?.isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        update(state)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(_ newState: MenuBarMetricSegmentState) {
        let didChange = state != newState
        let newPresentation = Self.presentation(for: newState)
        if presentation != newPresentation {
            applyLayout(newPresentation)
        }
        if state.symbol != newState.symbol || imageView.image == nil {
            imageView.image = newState.symbol.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
        }
        if state.leadingText != newState.leadingText || leadingLabel.stringValue.isEmpty {
            leadingLabel.stringValue = newState.leadingText ?? ""
        }
        if state.value != newState.value || valueLabel.stringValue.isEmpty {
            valueLabel.stringValue = newState.value
        }
        if state.width != newState.width {
            widthConstraint?.constant = newState.width
        }
        state = newState
        if didChange { mutationCount += 1 }
    }

    private func applyLayout(_ newPresentation: Presentation) {
        NSLayoutConstraint.deactivate(activeLayoutConstraints)
        presentation = newPresentation
        imageView.isHidden = newPresentation != .iconAndValue
        leadingLabel.isHidden = newPresentation != .stacked
        switch newPresentation {
        case .stacked:
            activeLayoutConstraints = [
                leadingLabel.topAnchor.constraint(equalTo: topAnchor),
                leadingLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                leadingLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
                valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
            ]
        case .iconAndValue:
            activeLayoutConstraints = [
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 11),
                imageView.heightAnchor.constraint(equalToConstant: 11),
                valueLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
                valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        case .valueOnly:
            activeLayoutConstraints = [
                valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        }
        NSLayoutConstraint.activate(activeLayoutConstraints)
    }

    private static func presentation(for state: MenuBarMetricSegmentState) -> Presentation {
        if state.leadingText != nil { return .stacked }
        return state.symbol == nil ? .valueOnly : .iconAndValue
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
