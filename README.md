# react-native-txc-player

React Native Fabric view that wraps [Tencent Cloud LiteAV Player Premium](https://cloud.tencent.com/document/product/266/118642) (`TXLiteAVSDK_Player_Premium`) for iOS and Android. It renders the underlying `TXVodPlayer` directly (no bundled SuperPlayer UI) and provides a minimal API for supplying a source, listening to playback events, and issuing commands from JS.

The player automatically releases its native resources when the React component unmounts to avoid GC pressure on Android.

## Installation

```sh
yarn add react-native-txc-player
# or
npm install react-native-txc-player
```

### iOS

```sh
cd ios && pod install
```

The iOS target links the `TXLiteAVSDK_Player_Premium` CocoaPod and requires that you set a licence before playback (see [Licence](#licence) below).

### Android

No manual steps are required. The library depends on `com.tencent.liteav:LiteAVSDK_Player_Premium:latest.release`, which uses LiteAV's automatic AAR loader. Make sure your Gradle repositories include either Tencent's public mirror or the official LiteAV artifact host (`https://liteavsdk-1252463788.cos.ap-guangzhou.myqcloud.com/release`) so the loader can fetch the Premium package.

## Licence

Before mounting the player, initialise the LiteAV SDK licence exactly once in your app lifecycle:

```ts
import { setTXCLicense } from 'react-native-txc-player';

setTXCLicense('https://your-license-url', 'your-license-key');
```

## Usage

```tsx
import { useRef, useState } from 'react';
import { Pressable, StyleSheet } from 'react-native';
import { TxcPlayerView, type TxcPlayerViewRef } from 'react-native-txc-player';

export default function Player() {
  const ref = useRef<TxcPlayerViewRef>(null);
  const [playing, setPlaying] = useState(true);

  const toggle = () => {
    setPlaying((current) => !current);
  };

  return (
    <Pressable style={styles.player} onPress={toggle}>
      <TxcPlayerView
        ref={ref}
        paused={!playing}
        source={{
          appId: '1500039285',
          fileId: '5145403699454155159',
          psign: 'your-psign',
        }}
        onPlayerEvent={(evt) => {
          console.log('[txc-player]', evt.nativeEvent);
        }}
        style={StyleSheet.absoluteFill}
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  player: {
    height: 220,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#000',
  },
});
```

## Props

| Prop | Type | Description |
| --- | --- | --- |
| `paused` | `boolean` (default `false`) | When `true` the player is paused; set to `false` to play/resume. |
| `source` | `{ url?: string; appId?: string; fileId?: string; psign?: string }` | Either pass a direct URL **or** a VOD `fileId` with the corresponding `appId`/`psign`. |
| `onPlayerEvent` | `(event) => void` | Receives events such as `begin`, `firstFrame`, `progress`, `end`, `loadingEnd`, `error`.  The payload also contains `code`/`message` when available. |
| `onProgress` | `(event) => void` | Fires with `{ position }` updates for the current playback position (in seconds). |


## Commands

```ts
import { Commands } from 'react-native-txc-player';

Commands.pause(ref);
Commands.resume(ref);
Commands.reset(ref); // stops and resets the underlying native player
Commands.seek(ref, 42); // jump to 42 seconds (best-effort)
Commands.destroy(ref); // releases the native player instance and clears its source
```

### Auto-destroy helpers

For list or carousel UIs where you want to automatically release the previously playing instance when a new cell becomes active, use the `useTxcPlayerAutoDestroy` hook. It destroys the native player when the component unmounts and (by default) ensures only one player stays active at a time.

```tsx
import { useRef, useMemo } from 'react';
import {
  TxcPlayerView,
  type TxcPlayerViewRef,
  useTxcPlayerAutoDestroy,
} from 'react-native-txc-player';

function FeedPlayer({ itemId, activeId, source }: Props) {
  const ref = useRef<TxcPlayerViewRef>(null);
  const isActive = useMemo(() => activeId === itemId, [activeId, itemId]);

  useTxcPlayerAutoDestroy(ref, { active: isActive, destroyOnDeactivate: true, exclusive: true });

  return (
    <TxcPlayerView
      ref={ref}
      paused={!isActive}
      source={source}
    />
  );
}
```

## Events

Event payload example:

```json
{
  "type": "error",
  "code": -2301,
  "message": "Network disconnected"
}
```

`type` values currently emitted: `begin`, `firstFrame`, `loadingEnd`, `end`, `error`, and `progress`.

- `progress` is delivered roughly every 250 ms with the current `position`, full `duration`, and buffered amount (`buffered`) in seconds. Use it to drive custom progress UIs without polling native state.

## Android resource management

The Android view registers as a `LifecycleEventListener` and automatically stops playback, destroys the `TXCloudVideoView`, and releases the `TXVodPlayer` when the React view unmounts or the host Activity is destroyed. This mirrors the recommendations in Tencent's documentation to prevent leaked native surfaces and GC pressure.

## Example

The repository ships with an example app (located in the `example` workspace) that demonstrates licence initialisation and tap-to-pause/resume behaviour.

```sh
yarn install
yarn example ios   # or `yarn example android`
```

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
