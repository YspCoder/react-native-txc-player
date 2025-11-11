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

### 1. Initialise the LiteAV licence

Call `setTXCLicense` once when your application starts. The SDK requires a
licence URL/key pair before any playback can begin.

```ts
import { setTXCLicense } from 'react-native-txc-player';

setTXCLicense('https://your-license-url', 'your-license-key');
```

### 2. Render a player view

The snippet below shows how to wire up a basic player with tap-to-pause,
progress updates, and a couple of imperative commands.

```tsx
import { useCallback, useMemo, useRef, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import {
  Commands,
  TxcPlayerView,
  type ChangeEvent,
  type ProgressEvent,
  type TxcPlayerViewRef,
} from 'react-native-txc-player';

const SOURCE = {
  appId: 'your-app-id',
  fileId: 'your-file-id',
  psign: 'your-psign',
};

type PlayerStatus = 'buffering' | 'playing' | 'paused' | 'ended' | 'error';

export default function PlayerCard() {
  const playerRef = useRef<TxcPlayerViewRef>(null);
  const [status, setStatus] = useState<PlayerStatus>('buffering');
  const [paused, setPaused] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [message, setMessage] = useState<string | null>(null);

  const formattedProgress = useMemo(() => {
    const total = duration > 0 ? duration.toFixed(1) : '??';
    return `${position.toFixed(1)}s / ${total}s`;
  }, [duration, position]);

  const handlePlayerEvent = useCallback((event: { nativeEvent: ChangeEvent }) => {
    const evt = event.nativeEvent;
    setMessage(evt.message ?? null);

    if (typeof evt.duration === 'number') {
      setDuration(evt.duration);
    }

    switch (evt.type) {
      case 'begin':
      case 'firstFrame':
      case 'loadingEnd':
        setStatus(paused ? 'paused' : 'playing');
        break;
      case 'end':
        setStatus('ended');
        setPaused(true);
        break;
      case 'error':
        setStatus('error');
        setPaused(true);
        Alert.alert('Playback error', `code=${evt.code}, message=${evt.message}`);
        break;
      default:
        break;
    }
  }, [paused]);

  const handleProgress = useCallback((event: { nativeEvent: ProgressEvent }) => {
    if (typeof event.nativeEvent.position === 'number') {
      setPosition(event.nativeEvent.position);
    }
  }, []);

  const togglePlayback = useCallback(() => {
    setPaused((current) => {
      const next = !current;
      setStatus(next ? 'paused' : 'playing');
      return next;
    });
  }, []);

  const restart = useCallback(() => {
    if (playerRef.current) {
      Commands.seek(playerRef.current, 0);
    }
  }, []);

  return (
    <View style={styles.container}>
      <Pressable style={styles.player} onPress={togglePlayback}>
        <TxcPlayerView
          ref={playerRef}
          paused={paused}
          source={SOURCE}
          onPlayerEvent={handlePlayerEvent}
          onProgress={handleProgress}
          style={StyleSheet.absoluteFill}
        />
      </Pressable>

      <Text style={styles.metaText}>{`Status: ${status}`}</Text>
      <Text style={styles.metaText}>{`Progress: ${formattedProgress}`}</Text>
      {message && <Text style={styles.metaText}>{`Message: ${message}`}</Text>}

      <Pressable onPress={restart} style={styles.button}>
        <Text style={styles.buttonLabel}>Seek to 0s</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    padding: 16,
    borderRadius: 12,
    backgroundColor: '#101010',
  },
  player: {
    aspectRatio: 16 / 9,
    borderRadius: 10,
    overflow: 'hidden',
    backgroundColor: '#000',
  },
  metaText: {
    color: '#fff',
  },
  button: {
    alignSelf: 'flex-start',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.15)',
  },
  buttonLabel: {
    color: '#fff',
    fontWeight: '600',
  },
});
```

## Props

| Prop | Type | Description |
| --- | --- | --- |
| `paused` | `boolean` (default `false`) | When `true` the player is paused; set to `false` to play/resume. |
| `source` | `{ url?: string; appId?: string; fileId?: string; psign?: string }` | Either pass a direct URL **or** a VOD `fileId` with the corresponding `appId`/`psign`. |
| `playbackRate` | `number` | Playback speed multiplier (default `1`). Applies equally on iOS/Android via `TXVodPlayer.setRate`. |
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

### 预下载（Pre-download）

通过 LiteAV 的 `TXVodPreloadManager` 可以把即将播放的视频数据提前缓存到本地，降低首帧等待。库内提供跨平台的辅助方法，参考 [官方文档](https://cloud.tencent.com/document/product/266/83142#download)。

```ts
import {
  startPreDownload,
  stopPreDownload,
  addPreDownloadListener,
  type PreDownloadEvent,
} from 'react-native-txc-player';

// 1. 启动预下载（支持 URL 或 fileId）
const taskId = await startPreDownload({
  url: 'https://example.com/video.m3u8',
  // 或者:
  // appId: '123456789',
  // fileId: '528589080xxxxxxx',
  // psign: 'xxx', // 可选
  preloadSizeMB: 10,
  preferredResolution: 1920 * 1080,
});

// 2. 监听进度（start / complete / error）
const sub = addPreDownloadListener((event: PreDownloadEvent) => {
  console.log('pre-download', event);
});

// 3. 取消任务
stopPreDownload(taskId);

// 4. 组件卸载时清理监听
sub.remove();
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
