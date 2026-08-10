const tabs = new Map();

browser.runtime.onMessage.addListener((message, sender) => {
  if (message.type !== "media-state" || !sender.tab || sender.tab.incognito) return;
  const id = sender.tab.id;
  if (!message.controllable || !Number.isInteger(id)) {
    tabs.delete(id);
  } else {
    tabs.set(id, {
      id: `safari:${id}`,
      browser: "Safari",
      title: sender.tab.title || "Safari Tab",
      canSetVolume: true,
      volume: Math.max(0, Math.min(100, Number(message.volume) || 0)),
      isMuted: Number(message.volume) === 0,
      audible: Boolean(message.audible)
    });
  }
  publishState();
});

browser.tabs.onRemoved.addListener(tabId => {
  tabs.delete(tabId);
  publishState();
});

async function publishState() {
  try {
    const response = await browser.runtime.sendNativeMessage("com.brgirgin.ClipboardHistory", {
      version: 1,
      type: "state",
      source: "safari",
      tabs: Array.from(tabs.values())
    });
    if (!response || response.version !== 1 || !Array.isArray(response.commands)) return;
    for (const command of response.commands) {
      if (typeof command.id !== "string" || !command.id.startsWith("safari:")) continue;
      const tabId = Number(command.id.slice("safari:".length));
      if (!tabs.has(tabId)) continue;
      if (command.action === "activate") {
        const tab = await browser.tabs.update(tabId, { active: true }).catch(() => null);
        if (tab && tab.windowId) await browser.windows.update(tab.windowId, { focused: true }).catch(() => {});
        continue;
      }
      await browser.tabs.sendMessage(tabId, { type: "set-volume", volume: command.volume }).catch(() => {});
    }
  } catch (_) {}
}

setInterval(publishState, 1000);
