const baselines = new WeakMap();
const controlledElements = new Set();
const internalChanges = new WeakSet();
let currentGain = 1;

function controllableMedia() {
  return Array.from(document.querySelectorAll("audio,video")).filter(element =>
    !element.mediaKeys && element.readyState > 0
  );
}

function rememberBaseline(element) {
  if (!baselines.has(element)) {
    baselines.set(element, { volume: element.volume, muted: element.muted });
  }
}

function applyGain(element) {
  rememberBaseline(element);
  const baseline = baselines.get(element);
  internalChanges.add(element);
  element.volume = Math.max(0, Math.min(1, baseline.volume * currentGain));
  element.muted = baseline.muted || currentGain === 0;
  queueMicrotask(() => internalChanges.delete(element));
  controlledElements.add(element);
}

function restoreBaseline(element) {
  const baseline = baselines.get(element);
  if (!baseline) return;
  internalChanges.add(element);
  element.volume = baseline.volume;
  element.muted = baseline.muted;
  queueMicrotask(() => internalChanges.delete(element));
  controlledElements.delete(element);
  baselines.delete(element);
}

function restoreAll() {
  for (const element of Array.from(controlledElements)) restoreBaseline(element);
  currentGain = 1;
}

function publishCapability() {
  const media = controllableMedia();
  browser.runtime.sendMessage({
    type: "media-state",
    controllable: media.length > 0,
    audible: media.some(element => !element.paused && !element.muted && element.volume > 0),
    volume: Math.round(currentGain * 100)
  }).catch(() => {});
}

browser.runtime.onMessage.addListener(message => {
  if (message.type === "release-volume-control") {
    restoreAll();
    publishCapability();
    return;
  }
  if (message.type !== "set-volume") return;
  currentGain = Math.max(0, Math.min(100, Number(message.volume))) / 100;
  for (const media of controllableMedia()) applyGain(media);
  publishCapability();
});

new MutationObserver(() => {
  for (const media of controllableMedia()) {
    if (currentGain !== 1) applyGain(media);
  }
  publishCapability();
}).observe(document.documentElement, { childList: true, subtree: true });

for (const event of ["play", "pause", "loadedmetadata", "emptied"]) {
  document.addEventListener(event, publishCapability, true);
}
document.addEventListener("volumechange", event => {
  const element = event.target;
  if (!(element instanceof HTMLMediaElement) || internalChanges.has(element)) return;
  if (controlledElements.has(element)) {
    baselines.set(element, { volume: element.volume, muted: element.muted });
    if (currentGain !== 1) applyGain(element);
  }
  publishCapability();
}, true);
window.addEventListener("pagehide", restoreAll, { once: true });
publishCapability();
