---
name: clipboardhistory-audio-mixer
description: Review or modify ClipboardHistory Audio Mixer, CoreAudio process discovery/control, process pipelines, browser audio bridge, Chromium/Safari integration, native messaging, gain/mute behavior, and audio runtime boundaries. Trigger for Audio Mixer or browser audio changes.
---

# Audio Mixer Safety Workflow

Read the complete path affected by the change:

```text
AudioMixerController
   |
process discovery
   |
process audio engine/pipeline
   |
CoreAudio

browser extension
   |
browser/native bridge
   |
AudioMixerController
```

## CoreAudio rules

- Use exact C/CoreAudio storage types and sizes.
- Do not ask a C API to write `T` bytes directly into `Optional<T>` storage.
- Verify `AudioObjectGetPropertyDataSize`/expected size where appropriate.
- Treat process disappearance between discovery and control as normal.
- Validate returned IDs/PIDs and property availability.
- Separate adapter-level failures from UI/controller state.

Protocol stubs prove controller behavior, not the real CoreAudio adapter.

Add native-adapter tests or a manual/platform validation plan for property access that cannot be meaningfully exercised in a pure unit test.

## Browser bridge

- Validate message schema and bounds.
- Do not trust arbitrary page/extension payloads as privileged commands.
- Keep browser/extension identity explicit.
- Handle reconnect/disconnect without duplicate ports/listeners.
- Do not let one browser namespace overwrite another unintentionally.

## Audio semantics

When applying gain/mute:
- distinguish app state from browser-tab state,
- avoid overwriting user-owned audio state where restoration is required,
- define what happens on process restart,
- define what happens if the app exits while a modified state is active.

## Verification

Run targeted Audio Mixer tests, static quality, and broader development tests for controller changes.

Real CoreAudio and browser-extension behavior must be called out as macOS/browser acceptance if not exercised.
