protocol ClipboardContentProcessing: Actor {
    func process(
        _ rawContent: ClipboardRawContent,
        sourceBundleIdentifier: String?
    ) async -> ClipboardContent?
}
