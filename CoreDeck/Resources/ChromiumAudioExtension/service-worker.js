async function ensureOffscreenDocument() {
  const url = chrome.runtime.getURL("offscreen.html");
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
    documentUrls: [url]
  });
  if (contexts.length === 0) {
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["USER_MEDIA", "AUDIO_PLAYBACK"],
      justification: "Apply the user-selected gain and play captured tab audio."
    });
  }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "activate-tab") {
    chrome.tabs.update(message.tabId, { active: true }).then(tab => {
      if (tab.windowId) chrome.windows.update(tab.windowId, { focused: true });
    }).catch(() => {});
    return false;
  }
  if (message.type !== "capture-tab") return false;
  ensureOffscreenDocument()
    .then(() => chrome.runtime.sendMessage(message))
    .then(() => sendResponse({ ok: true }))
    .catch(error => sendResponse({ ok: false, error: error.message }));
  return true;
});

chrome.tabs.onRemoved.addListener(tabId => {
  chrome.runtime.sendMessage({ type: "remove-tab", tabId }).catch(() => {});
});
