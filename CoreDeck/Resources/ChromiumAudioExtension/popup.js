const button = document.getElementById("add");
const status = document.getElementById("status");
const message = (key) => chrome.i18n.getMessage(key);

button.textContent = message("addButton");

button.addEventListener("click", async () => {
  button.disabled = true;
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.id) throw new Error(message("noActiveTab"));
    if (tab.incognito) throw new Error(message("privateTab"));
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
    const response = await chrome.runtime.sendMessage({
      type: "capture-tab",
      tabId: tab.id,
      title: tab.title || message("browserTab"),
      streamId
    });
    if (!response?.ok) throw new Error(response?.error || message("captureFailed"));
    status.textContent = message("addedStatus");
  } catch (error) {
    status.textContent = error.message;
  } finally {
    button.disabled = false;
  }
});
