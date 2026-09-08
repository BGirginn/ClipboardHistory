const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');

test('Chromium acknowledgements are finite and idle capture has no timer', () => {
  let connections = 0;
  const messages = [];
  const timers = new Set();
  const context = vm.createContext({
    navigator: { userAgent: 'Chrome' },
    setInterval: callback => { timers.add(callback); return callback; },
    clearInterval: callback => timers.delete(callback),
    setTimeout: () => {},
    chrome: { runtime: {
      onMessage: { addListener() {} },
      sendMessage: async () => {},
      connectNative() {
        connections++;
        return { onMessage: { addListener() {} }, onDisconnect: { addListener() {} },
          postMessage: message => messages.push(message) };
      }
    } }
  });
  vm.runInContext(fs.readFileSync(path.join(root, 'ClipboardHistory/Resources/ChromiumAudioExtension/offscreen.js'), 'utf8'), context);
  assert.equal(connections, 0);
  assert.equal(timers.size, 0);
  vm.runInContext(`captures.set(1, {tabId: 1, title: 'Synthetic', context: {currentTime: 0},
    gain: {gain: {value: 1, setValueAtTime(value) { this.value = value; }}}}); publishState();`, context);
  assert.equal(timers.size, 1);
  assert.equal(messages.length, 1);
  vm.runInContext(`for (let i = 0; i < 100; i++) handleNativeCommands({version: 1, commands: []});`, context);
  assert.equal(messages.length, 1);
  vm.runInContext(`for (let i = 0; i < 100; i++) handleNativeCommands({version: 1, commands: [{id: 'chromium:chrome:1', volume: 40}]});`, context);
  assert.equal(messages.length, 2);
  assert.equal(messages[1].tabs[0].volume, 40);
  vm.runInContext('captures.clear(); publishState();', context);
  assert.equal(timers.size, 0);
  assert.equal(messages.at(-1).tabs.length, 0);
});

test('Safari coalesces concurrent native requests and stops its idle heartbeat', async () => {
  let receive;
  let removed;
  let resolveResponse;
  const messages = [];
  const timers = new Set();
  const context = vm.createContext({
    setInterval: callback => { timers.add(callback); return callback; },
    clearInterval: callback => timers.delete(callback),
    browser: {
      runtime: {
        onMessage: { addListener: callback => { receive = callback; } },
        sendNativeMessage: (_, message) => {
          messages.push(message);
          return new Promise(resolve => { resolveResponse = resolve; });
        }
      },
      tabs: { onRemoved: { addListener: callback => { removed = callback; } } }
    }
  });
  vm.runInContext(fs.readFileSync(path.join(root, 'ClipboardHistorySafariExtension/Resources/background.js'), 'utf8'), context);
  assert.equal(messages.length, 0);
  assert.equal(timers.size, 0);
  for (let i = 0; i < 100; i++) receive({type: 'media-state', controllable: true, volume: 100}, {tab: {id: 1}});
  assert.equal(messages.length, 1);
  assert.equal(timers.size, 1);
  resolveResponse({version: 1, commands: []});
  await new Promise(setImmediate);
  assert.equal(messages.length, 2);
  resolveResponse({version: 1, commands: []});
  await new Promise(setImmediate);
  removed(1);
  assert.equal(timers.size, 0);
  assert.equal(messages.at(-1).tabs.length, 0);
  resolveResponse({version: 1, commands: []});
  await new Promise(setImmediate);
});
