const captures = new Map();
let nativePort = null;
const browserName = navigator.brave
  ? "Brave"
  : /Edg\//.test(navigator.userAgent)
    ? "Edge"
    : /Arc\//.test(navigator.userAgent)
      ? "Arc"
      : "Chrome";

function connectNative() {
  if (nativePort) return;
  try {
    nativePort = chrome.runtime.connectNative("com.brgirgin.clipboardhistory.audiomixer");
    nativePort.onMessage.addListener(handleNativeCommands);
    nativePort.onDisconnect.addListener(() => {
      nativePort = null;
      setTimeout(connectNative, 2000);
    });
  } catch (_) {
    nativePort = null;
  }
}

function publishState() {
  connectNative();
  if (!nativePort) return;
  nativePort.postMessage({
    version: 1,
    type: "state",
    source: "chromium",
    tabs: Array.from(captures.values()).map(item => ({
      id: `chromium:${item.tabId}`,
      browser: browserName,
      title: item.title,
      canSetVolume: true,
      volume: Math.round(item.gain.gain.value * 100),
      isMuted: item.gain.gain.value === 0
    }))
  });
}

function handleNativeCommands(message) {
  if (message.version !== 1 || !Array.isArray(message.commands)) return;
  for (const command of message.commands) {
    if (typeof command.id !== "string" || !command.id.startsWith("chromium:")) continue;
    const tabId = Number(command.id.slice("chromium:".length));
    if (command.action === "activate") {
      chrome.runtime.sendMessage({ type: "activate-tab", tabId }).catch(() => {});
      continue;
    }
    const capture = captures.get(tabId);
    if (!capture) continue;
    const volume = Math.max(0, Math.min(100, Number(command.volume)));
    capture.gain.gain.setValueAtTime(volume / 100, capture.context.currentTime);
  }
  publishState();
}

async function captureTab(message) {
  if (captures.has(message.tabId)) return;
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      mandatory: {
        chromeMediaSource: "tab",
        chromeMediaSourceId: message.streamId
      }
    },
    video: false
  });
  const context = new AudioContext();
  const source = context.createMediaStreamSource(stream);
  const gain = context.createGain();
  source.connect(gain).connect(context.destination);
  const item = { tabId: message.tabId, title: message.title, stream, context, source, gain };
  captures.set(message.tabId, item);
  stream.getAudioTracks()[0].addEventListener("ended", () => removeTab(message.tabId));
  publishState();
}

function removeTab(tabId) {
  const item = captures.get(Number(tabId));
  if (!item) return;
  item.stream.getTracks().forEach(track => track.stop());
  item.context.close();
  captures.delete(Number(tabId));
  publishState();
}

chrome.runtime.onMessage.addListener(message => {
  if (message.type === "capture-tab") captureTab(message).catch(() => {});
  if (message.type === "remove-tab") removeTab(message.tabId);
});

connectNative();
setInterval(publishState, 1000);
