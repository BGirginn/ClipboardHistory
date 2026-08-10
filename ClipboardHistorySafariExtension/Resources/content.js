function controllableMedia() {
  return Array.from(document.querySelectorAll("audio,video")).filter(element =>
    !element.mediaKeys && element.readyState > 0
  );
}

function publishCapability() {
  const media = controllableMedia();
  browser.runtime.sendMessage({
    type: "media-state",
    controllable: media.length > 0,
    audible: media.some(element => !element.paused && !element.muted && element.volume > 0),
    volume: media.length ? Math.round(media[0].volume * 100) : 100
  }).catch(() => {});
}

browser.runtime.onMessage.addListener(message => {
  if (message.type !== "set-volume") return;
  const volume = Math.max(0, Math.min(100, Number(message.volume))) / 100;
  for (const media of controllableMedia()) {
    media.volume = volume;
    media.muted = volume === 0;
  }
  publishCapability();
});

new MutationObserver(publishCapability).observe(document.documentElement, { childList: true, subtree: true });
for (const event of ["play", "pause", "volumechange", "loadedmetadata", "emptied"]) {
  document.addEventListener(event, publishCapability, true);
}
publishCapability();
setInterval(publishCapability, 2000);
