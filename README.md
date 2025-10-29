# react-native-txc-player

React Native Fabric view that wraps [Tencent Cloud SuperPlayer](https://cloud.tencent.com/document/product/881/20208) for iOS and Android. It provides a declarative API for SuperPlayer UI features such as hiding built-in controls, feeding cover artwork, dynamic/ghost watermarks, and injecting external subtitles.

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

The iOS target links the `SuperPlayer` CocoaPod and requires that you set a licence before playback (see [Licence](#licence) below).

### Android

No manual steps are required. The library pulls in `com.tencent.liteav:LiteAVSDK_Player` and registers a Fabric view. If you work behind a firewall that blocks Tencent's Maven mirror, add a mirror that can resolve `LiteAVSDK_Player` to your root Gradle repositories.

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
        config={{
          coverUrl: 'https://example.com/cover.png',
          hideFullscreenButton: true,
          hideFloatWindowButton: true,
          hidePipButton: true,
          hideBackButton: true,
          hideResolutionButton: true,
          hidePlayButton: true,
          hideProgressBar: true,
          autoHideProgressBar: true,
          maxBufferSize: 120,
          maxPreloadSize: 20,
          disableDownload: true,
          dynamicWatermark: {
            type: 'ghost',
            text: 'Demo Watermark',
            color: '#80FFFFFF',
            fontSize: 18,
            duration: 5,
          },
          subtitles: [
            {
              url: 'https://media.w3.org/2010/05/sintel/track3_eng.vtt',
              name: 'English',
              type: 'vtt',
            },
          ],
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
| `config` | `PlayerConfig` | Optional UI/runtime tweaks (see below). |
| `onPlayerEvent` | `(event) => void` | Receives events such as `begin`, `firstFrame`, `progress`, `end`, `loadingEnd`, `error`, `subtitleNotice`.  The payload also contains `code`/`message` when available. |
| `onProgress` | `(event) => void` | Fires with `{ position }` updates for the current playback position (in seconds). |

`PlayerConfig`

| Field | Type | Notes |
| --- | --- | --- |
| `hideFullscreenButton` (`hideFullScreenButton`) | `boolean` | Hides the fullscreen button in the native SuperPlayer UI (iOS). Android uses a custom overlay, so the flag is informational only. |
| `hideFloatWindowButton` | `boolean` | Disables the floating-window control on iOS and prevents the Android view from attempting to enter float mode. |
| `hidePipButton` | `boolean` | Hides the Picture-in-Picture button and force-disables automatic PiP. |
| `hideBackButton` | `boolean` | Hides the back button in the default SuperPlayer control overlay (iOS only). |
| `hideResolutionButton` | `boolean` | Hides the clarity/resolution switcher button in the default SuperPlayer controls (iOS only). |
| `hidePlayButton` | `boolean` | Hides the central play/pause button that sits to the left of the progress slider (iOS only). |
| `hideProgressBar` | `boolean` | Completely hides the native progress slider and time labels (iOS only). |
| `autoHideProgressBar` | `boolean` | Keeps the SuperPlayer controls auto-hiding (default `true`). Set to `false` to pin the progress bar and toolbars on screen. |
| `maxBufferSize` | `number` | Maximum forward playback buffer size in MB. Mirrors `TXVodPlayConfig.maxBufferSize`. |
| `maxPreloadSize` | `number` | Maximum preroll/preload buffer size in MB. Mirrors `TXVodPlayConfig.maxPreloadSize`. |
| `disableDownload` | `boolean` | Hides the download button (iOS SuperPlayer UI). |
| `coverUrl` | `string` | Remote image displayed until the first video frame renders. |
| `dynamicWatermark` | `{ type?: 'dynamic' \| 'ghost'; text: string; duration?: number; fontSize?: number; color?: string }` | Adds a moving text watermark overlay. `ghost` lowers alpha to mimic the official ghost watermark style. `duration` controls how often the text changes position (seconds). |
| `subtitles` | `Array<{ url: string; name: string; type?: string }>` | External subtitle descriptors. iOS forwards them to SuperPlayer. Android surfaces a `subtitleNotice` event; loading external tracks requires the LiteAV premium package. |

## Commands

```ts
import { Commands } from 'react-native-txc-player';

Commands.pause(ref);
Commands.resume(ref);
Commands.reset(ref); // stops and resets the underlying native player
Commands.seek(ref, 42); // jump to 42 seconds (best-effort)
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

`type` values currently emitted: `begin`, `firstFrame`, `loadingEnd`, `end`, `error`, `warning`, `subtitleNotice`, `fullscreenChange`, `back`, and `progress`.

- `progress` is delivered roughly every 250 ms with the current `position`, full `duration`, and buffered amount (`buffered`) in seconds. Use it to drive custom progress UIs without polling native state.

## Android resource management

The Android view registers as a `LifecycleEventListener` and automatically stops playback, destroys the `TXCloudVideoView`, and releases the `TXVodPlayer` when the React view unmounts or the host Activity is destroyed. This mirrors the recommendations in Tencent's documentation to prevent leaked native surfaces and GC pressure.

## Example

The repository ships with an example app (located in the `example` workspace) that demonstrates licence initialisation, the configuration surface, and tap-to-pause/resume behaviour.

```sh
yarn install
yarn example ios   # or `yarn example android`
```

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
