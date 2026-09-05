import Foundation

extension AudioMixerController {
    func setBrowserVolume(_ volume: Double, tab: BrowserAudioTab) {
        browserVolumePreviewTasks.removeValue(forKey: tab.id)?.cancel()
        pendingBrowserVolumePreviews.removeValue(forKey: tab.id)
        let normalized = min(max(volume, 0), 100)
        browserBridge.setVolume(normalized, tabID: tab.id)
        if let index = browserTabs.firstIndex(where: { $0.id == tab.id }) {
            guard browserTabs[index].volume != normalized
                    || browserTabs[index].isMuted != (normalized == 0) else { return }
            browserTabs[index].volume = normalized
            browserTabs[index].isMuted = normalized == 0
        }
    }

    func previewBrowserVolume(_ volume: Double, tab: BrowserAudioTab) {
        let tabID = tab.id
        pendingBrowserVolumePreviews[tabID] = min(max(volume, 0), 100)
        guard browserVolumePreviewTasks[tabID] == nil else { return }
        browserVolumePreviewTasks[tabID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(33))
            } catch {
                return
            }
            guard let self,
                  let pending = pendingBrowserVolumePreviews.removeValue(
                    forKey: tabID
                  ) else { return }
            browserVolumePreviewTasks.removeValue(forKey: tabID)
            browserBridge.setVolume(pending, tabID: tabID)
        }
    }

    func toggleMute(_ tab: BrowserAudioTab) {
        if tab.isMuted {
            let restoredVolume = max(
                browserPreMuteGains.removeValue(forKey: tab.id) ?? 100,
                1
            )
            setBrowserVolume(restoredVolume, tab: tab)
        } else {
            browserPreMuteGains[tab.id] = tab.volume
            setBrowserVolume(0, tab: tab)
        }
    }

    func activate(_ tab: BrowserAudioTab) {
        browserBridge.activate(tabID: tab.id)
    }

    func effectiveVolume(for tab: BrowserAudioTab) -> Double {
        let matchingBundleIDs: Set<String>
        switch tab.browser.lowercased() {
        case "safari": matchingBundleIDs = ["com.apple.Safari"]
        case "brave": matchingBundleIDs = ["com.brave.Browser"]
        case "edge": matchingBundleIDs = ["com.microsoft.edgemac"]
        case "arc": matchingBundleIDs = ["company.thebrowser.Browser"]
        case "chromium": matchingBundleIDs = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser"
        ]
        default: matchingBundleIDs = ["com.google.Chrome"]
        }
        let matches = outputApplications.filter {
            matchingBundleIDs.contains($0.bundleID)
        }
        let master = matches.count == 1 ? matches[0].volume : 100
        return master * tab.volume / 100
    }
}
