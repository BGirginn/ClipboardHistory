import AppKit
import SwiftUI

struct KeyboardEventMonitorView: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start(in: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?
        private weak var ownerView: NSView?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func start(in view: NSView? = nil) {
            ownerView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.ownerView?.window,
                      event.window === window,
                      window.attachedSheet == nil,
                      NSApp.modalWindow == nil,
                      !(window.firstResponder is NSTextView),
                      RunLoop.current.currentMode != .eventTracking else { return event }
                return self.handler(event) ? nil : event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            MainActor.assumeIsolated { stop() }
        }
    }
}
