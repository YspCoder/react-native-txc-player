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

const PLAYBACK_OPTIONS = [0.5, 1, 1.25, 1.5, 2] as const;
const ACCELERATED_RATE = 2;

type PlayerStatus =
  | 'idle'
  | 'buffering'
  | 'playing'
  | 'paused'
  | 'ended'
  | 'error';

type PlayerSnapshot = {
  status: PlayerStatus;
  position: number;
  duration: number;
  message: string | null;
};

const INITIAL_SNAPSHOT: PlayerSnapshot = {
  status: 'buffering',
  position: 0,
  duration: 0,
  message: null,
};

const formatSeconds = (value: number) => value.toFixed(1);

export default function App() {
  const playerRef = useRef<TxcPlayerViewRef>(null);
  const [ready, setReady] = useState(false);
  const [snapshot, setSnapshot] = useState<PlayerSnapshot>(INITIAL_SNAPSHOT);
  const [paused, setPaused] = useState(false);
  const [key, setKey] = useState(0);
  const [selectedRate, setSelectedRate] = useState(1);
  const [playbackRate, setPlaybackRate] = useState(1);
  const longPressActiveRef = useRef(false);
  const skipPressUntilRef = useRef(0);

  useEffect(() => {
    setTXCLicense(
      'https://license.vod2.myqcloud.com/license/v2/1314161253_1/v_cube.license',
      '99c843cd9e1a46a589fbd1a76cd244f6'
    );
    setReady(true);
  }, []);

  const formattedProgress = useMemo(() => {
    const total =
      snapshot.duration > 0 ? formatSeconds(snapshot.duration) : '??';
    return `${formatSeconds(snapshot.position)}s / ${total}s`;
  }, [snapshot.duration, snapshot.position]);

  const handlePlayerEvent = useCallback(
    (event: { nativeEvent: ChangeEvent }) => {
      const evt = event.nativeEvent;

      setSnapshot((current) => {
        const next: PlayerSnapshot = {
          status: current.status,
          position: current.position,
          duration:
            typeof evt.duration === 'number' ? evt.duration : current.duration,
          message: evt.message ?? null,
        };

        switch (evt.type) {
          case 'begin':
          case 'firstFrame':
          case 'loadingEnd':
            next.status = paused ? 'paused' : 'playing';
            break;
          case 'end':
            next.status = 'ended';
            break;
          case 'error':
            next.status = 'error';
            break;
          default:
            break;
        }

        return next;
      });

      if (evt.type === 'error') {
        setPaused(true);
        Alert.alert('播放错误', `code=${evt.code}, message=${evt.message}`);
      } else if (evt.type === 'end') {
        setPaused(true);
      }
    },
    [paused]
  );

  const handleProgress = useCallback(
    (event: { nativeEvent: ProgressEvent }) => {
      const { position } = event.nativeEvent;

      if (typeof position === 'number') {
        setSnapshot((current) => ({
          ...current,
          position,
        }));
      }
    },
    []
  );

  const togglePlayback = useCallback(() => {
    let shouldRestart = false;

    setPaused((currentPaused) => {
      const nextPaused = !currentPaused;

      setSnapshot((current) => {
        if (current.status === 'error') {
          return current;
        }

        if (current.status === 'ended' && !nextPaused) {
          shouldRestart = true;
          return {
            ...current,
            status: 'playing',
            position: 0,
          };
        }

        return {
          ...current,
          status: nextPaused ? 'paused' : 'playing',
        };
      });

      return nextPaused;
    });

    if (shouldRestart && playerRef.current) {
      Commands.seek(playerRef.current, 0);
    }
  }, [playerRef]);

  const seekToStart = useCallback(() => {
    if (playerRef.current) {
      Commands.seek(playerRef.current, 0);
    }
  }, [playerRef]);

  const jumpForward = useCallback(() => {
    if (!playerRef.current) {
      return;
    }

    const target =
      snapshot.duration > 0
        ? Math.min(snapshot.position + 15, snapshot.duration)
        : snapshot.position + 15;

    Commands.seek(playerRef.current, target);
  }, [playerRef, snapshot.duration, snapshot.position]);

  const destroyPlayer = useCallback(() => {
    if (playerRef.current) {
      Commands.destroy(playerRef.current);
    }

    setSnapshot(INITIAL_SNAPSHOT);
    setPaused(false);
    setSelectedRate(1);
    setPlaybackRate(1);
    setKey((value) => value + 1);
  }, [playerRef]);

  const selectRate = useCallback((value: number) => {
    setSelectedRate(value);
    setPlaybackRate(value);
  }, []);

  const handleAccelerate = useCallback(() => {
    if (paused) {
      return;
    }

    longPressActiveRef.current = true;
    setPlaybackRate(ACCELERATED_RATE);
  }, [paused]);

  const handlePressOut = useCallback(() => {
    if (!longPressActiveRef.current) {
      return;
    }

    setPlaybackRate(selectedRate);
    longPressActiveRef.current = false;
    skipPressUntilRef.current = Date.now() + 200;
  }, [selectedRate]);

  const handlePlayerPress = useCallback(() => {
    if (skipPressUntilRef.current > Date.now()) {
      skipPressUntilRef.current = 0;
      return;
    }

    togglePlayback();
  }, [togglePlayback]);

  if (!ready) {
    return (
      <View style={styles.center}>
        <Text style={styles.messageText}>正在初始化 License…</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Pressable
        onPress={handlePlayerPress}
        onLongPress={handleAccelerate}
        onPressOut={handlePressOut}
        delayLongPress={150}
        style={styles.player}
      >
        <TxcPlayerView
          key={key}
          ref={playerRef}
          paused={paused}
          playbackRate={playbackRate}
          source={PLAYER_SOURCE}
          onPlayerEvent={handlePlayerEvent}
          onProgress={handleProgress}
          style={StyleSheet.absoluteFill}
        />
      </Pressable>

      <View style={styles.infoPanel}>
        <Text style={styles.infoText}>{`状态：${snapshot.status}`}</Text>
        <Text style={styles.infoText}>{`进度：${formattedProgress}`}</Text>
        {!!snapshot.message && (
          <Text style={styles.infoText}>{`信息：${snapshot.message}`}</Text>
        )}
      </View>

      <View style={styles.rateRow}>
        {PLAYBACK_OPTIONS.map((option) => (
          <Pressable
            key={option}
            onPress={() => selectRate(option)}
            style={[
              styles.rateButton,
              option === selectedRate && styles.rateButtonActive,
            ]}
          >
            <Text style={styles.controlText}>{`${option}x`}</Text>
          </Pressable>
        ))}
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
  rateRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    marginBottom: 12,
  },
  controlButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.15)',
    marginHorizontal: 8,
  },
  rateButton: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.1)',
    marginHorizontal: 4,
  },
  rateButtonActive: {
    backgroundColor: 'rgba(255,255,255,0.3)',
  },
  controlText: {
    color: '#fff',
    fontWeight: '600',
  },
  messageText: {
    color: '#fff',
  },
});
