import os.signpost

@MainActor
extension MenuBarController {
    func beginPresentationSignpost() {
        let signpostID = OSSignpostID(log: presentationLog)
        presentationSignpostID = signpostID
        os_signpost(
            .begin,
            log: presentationLog,
            name: "ClickToVisible",
            signpostID: signpostID
        )
    }

    func markPresentationPrepared() {
        guard let presentationSignpostID else { return }
        os_signpost(
            .event,
            log: presentationLog,
            name: "ContentPrepared",
            signpostID: presentationSignpostID
        )
    }

    func endPresentationSignpost() {
        guard let presentationSignpostID else { return }
        os_signpost(
            .end,
            log: presentationLog,
            name: "ClickToVisible",
            signpostID: presentationSignpostID
        )
        self.presentationSignpostID = nil
    }
}
