import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import {
  Commands,
  TxcPlayerView,
  setTXCLicense,
  type ChangeEvent,
  type ProgressEvent,
  type TxcPlayerViewRef,
} from 'react-native-txc-player';

const PLAYER_SOURCE = {
  appId: '1500024012',
  fileId: '3270835013523247456',
  psign:
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJhcHBJZCI6MTUwMDAyNDAxMiwiZmlsZUlkIjoiMzI3MDgzNTAxMzUyMzI0NzQ1NiIsImNvbnRlbnRJbmZvIjp7ImF1ZGlvVmlkZW9UeXBlIjoiUHJvdGVjdGVkQWRhcHRpdmUiLCJkcm1BZGFwdGl2ZUluZm8iOnsicHJpdmF0ZUVuY3J5cHRpb25EZWZpbml0aW9uIjoxNDgwNjc0fX0sImN1cnJlbnRUaW1lU3RhbXAiOjE3NjI0Mjk3MzUsImV4cGlyZVRpbWVTdGFtcCI6MTc2MjY4ODkzMSwidXJsQWNjZXNzSW5mbyI6eyJ0IjoiNjkxMDdmYTMiLCJ1cyI6ImJjMTAxMzEyMzg4NDkyXzMyNzA4MzUwMTM1MjMyNDc0NTZfXzEifSwiZ2hvc3RXYXRlcm1hcmtJbmZvIjp7InRleHQiOiJcdTUyNjdcdTY2MWYifSwiZHJtTGljZW5zZUluZm8iOnsic3RyaWN0TW9kZSI6Mn19.wPs1HUNmpytt0zugsPUAEym11rl1GnI-ZySwHhFMk7w',
} as const;

type PlayerStatus = 'idle' | 'buffering' | 'playing' | 'paused' | 'ended' | 'error';

export default function App() {
  const playerRef = useRef<TxcPlayerViewRef>(null);
  const [ready, setReady] = useState(false);
  const [status, setStatus] = useState<PlayerStatus>('playing');
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [message, setMessage] = useState<string | null>(null);
  const [key, setKey] = useState(0);

  useEffect(() => {
    setTXCLicense(
      'https://license.vod2.myqcloud.com/license/v2/1314161253_1/v_cube.license',
      '99c843cd9e1a46a589fbd1a76cd244f6'
    );
    setReady(true);
  }, []);

  const playing = useMemo(() => status === 'playing' || status === 'buffering', [status]);

  const handlePlayerEvent = useCallback((event: { nativeEvent: ChangeEvent }) => {
    const evt = event.nativeEvent;
    setMessage(evt.message ?? null);

    console.log(evt);
    

    if (typeof evt.duration === 'number') {
      setDuration(evt.duration);
    }

    switch (evt.type) {
      case 'firstFrame':
      case 'begin':
      case 'loadingEnd':
        setStatus('playing');
        break;
      case 'end':
        setStatus('ended');
        break;
      case 'error':
        setStatus('error');
        Alert.alert('播放错误', `code=${evt.code}, message=${evt.message}`);
        break;
      default:
        break;
    }
  }, []);

  const handleProgress = useCallback((event: { nativeEvent: ProgressEvent }) => {
    const current = event.nativeEvent.position;
    if (typeof current === 'number') {
      setPosition(current);
    }
  }, []);

  const togglePlayback = useCallback(() => {
    if (status === 'playing') {
      setStatus('paused');
    } else {
      setStatus('playing');
    }
  }, [status]);

  const seekToStart = useCallback(() => {
    if (playerRef.current) {
      Commands.seek(playerRef.current, 0);
    }
  }, []);

  const jumpForward = useCallback(() => {
    if (!playerRef.current) {
      return;
    }
    const target = duration > 0 ? Math.min(position + 15, duration) : position + 15;
    Commands.seek(playerRef.current, target);
  }, [duration, position]);

  const destroyPlayer = useCallback(() => {
    if (playerRef.current) {
      Commands.destroy(playerRef.current);
    }
    setStatus('idle');
    setPosition(0);
    setDuration(0);
    setMessage(null);
    setKey((value) => value + 1);
  }, []);

  if (!ready) {
    return (
      <View style={styles.center}>
        <Text style={styles.messageText}>正在初始化 License…</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Pressable onPress={togglePlayback} style={styles.player}>
        <TxcPlayerView
          key={key}
          ref={playerRef}
          paused={!playing}
          source={PLAYER_SOURCE}
          onPlayerEvent={handlePlayerEvent}
          onProgress={handleProgress}
          style={StyleSheet.absoluteFill}
        />
      </Pressable>

      <View style={styles.infoPanel}>
        <Text style={styles.infoText}>{`状态：${status}`}</Text>
        <Text style={styles.infoText}>
          {`进度：${position.toFixed(1)}s / ${
            duration > 0 ? duration.toFixed(1) : '??'
          }s`}
        </Text>
        {!!message && <Text style={styles.infoText}>{`信息：${message}`}</Text>}
      </View>

      <View style={styles.controls}>
        <Pressable onPress={seekToStart} style={styles.controlButton}>
          <Text style={styles.controlText}>Seek 0s</Text>
        </Pressable>
        <Pressable onPress={jumpForward} style={styles.controlButton}>
          <Text style={styles.controlText}>+15s</Text>
        </Pressable>
        <Pressable onPress={destroyPlayer} style={styles.controlButton}>
          <Text style={styles.controlText}>Destroy</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#000',
  },
  player: {
    flex: 1,
    marginVertical: 20,
    borderRadius: 12,
    overflow: 'hidden',
  },
  infoPanel: {
    paddingHorizontal: 16,
    paddingBottom: 12,
  },
  infoText: {
    color: '#fff',
    marginBottom: 4,
  },
  controls: {
    flexDirection: 'row',
    justifyContent: 'center',
    paddingBottom: 24,
    paddingHorizontal: 16,
  },
  controlButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.15)',
    marginHorizontal: 8,
  },
  controlText: {
    color: '#fff',
    fontWeight: '600',
  },
  messageText: {
    color: '#fff',
  },
});
