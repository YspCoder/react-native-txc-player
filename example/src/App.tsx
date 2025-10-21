import { useEffect, useRef, useState } from 'react';
import { View, StyleSheet, Alert, Text, Pressable } from 'react-native';
import {
  setTXCLicense,
  TxcPlayerView,
  Commands,
  type TxcPlayerViewRef,
} from 'react-native-txc-player';

export default function App() {

  const ref = useRef<TxcPlayerViewRef>(null);
  const [ready, setReady] = useState(false);
  const [isPlaying, setIsPlaying] = useState(true);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);

  useEffect(() => {
    setTXCLicense(
      'https://license.vod2.myqcloud.com/license/v2/1314161253_1/v_cube.license',
      '99c843cd9e1a46a589fbd1a76cd244f6'
    );
    setReady(true);
    setIsPlaying(true);
  }, []);

  // 2) 只有 ready 才渲染播放器（防止先渲染后设置导致校验失败）
  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      {ready ? (
        <>
          <Pressable
            onPress={() => {
              if (!ref.current) return;
              if (isPlaying) {
                Commands.pause(ref.current);
              } else {
                Commands.resume(ref.current);
              }
              setIsPlaying(!isPlaying);
            }}
            style={styles.box}
          >
            <TxcPlayerView
              ref={ref}
              autoplay
              source={{
                appId: '1500039285',
                fileId: '5145403693842665329',
                psign:
                  'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJhcHBJZCI6MTUwMDAzOTI4NSwiZmlsZUlkIjoiNTE0NTQwMzY5Mzg0MjY2NTMyOSIsImNvbnRlbnRJbmZvIjp7ImF1ZGlvVmlkZW9UeXBlIjoiUHJvdGVjdGVkQWRhcHRpdmUiLCJkcm1BZGFwdGl2ZUluZm8iOnsicHJpdmF0ZUVuY3J5cHRpb25EZWZpbml0aW9uIjoxNjQ1OTk0fX0sImN1cnJlbnRUaW1lU3RhbXAiOjE3NjA5NTk3NjAsImV4cGlyZVRpbWVTdGFtcCI6MTc2MTIxODk2MCwidXJsQWNjZXNzSW5mbyI6eyJ0IjoiNjhmYTExOTAiLCJ1cyI6ImJjMTAxMzEyMzg4NDkyXzUxNDU0MDM2OTM4NDI2NjUzMjlfXzEifSwiZ2hvc3RXYXRlcm1hcmtJbmZvIjp7InRleHQiOiJcdTUyNjdcdTY2MWYifSwiZHJtTGljZW5zZUluZm8iOnsic3RyaWN0TW9kZSI6Mn19.ZfPtVuYbFHGsScuctHAA15jhprUuzfs2Fvw8lCh7IIE',
              }}
              config={{
                hideFullscreenButton: true,
                hideFloatWindowButton: true,
                hidePipButton: true,
                hideBackButton: true,
                hideResolutionButton: true,
                hidePlayButton: true,
                hideProgressBar: true,
                autoHideProgressBar: true,
                disableDownload: true,
                maxBufferSize: 120,
                maxPreloadSize: 20,
                coverUrl: 'https://main.qcloudimg.com/raw/9a3f830b73fab9142c078f2c0c666cce.png',
              }}
              onPlayerEvent={(e: any) => {
                const evt = e.nativeEvent;
                console.log('[TXC event]', evt);
                if (evt.type === 'begin' || evt.type === 'firstFrame') {
                  setIsPlaying(true);
                }
                if (evt.type === 'end' || evt.type === 'error') {
                  setIsPlaying(false);
                }
                if (evt.type === 'progress') {
                  if (typeof evt.position === 'number') {
                    setPosition(evt.position);
                  }
                  if (typeof evt.duration === 'number') {
                    setDuration(evt.duration);
                  }
                }
                if (evt.type === 'error') {
                  Alert.alert(
                    '播放错误',
                    `code=${evt.code}, message=${evt.message}`
                  );
                }
              }}
              style={StyleSheet.absoluteFill}
            />
          </Pressable>
        </>
      ) : (
        <Text style={{ color: '#fff' }}>正在初始化 License…</Text>
      )}
      <Text style={{ color: '#fff', padding: 12 }}>
        {`当前位置: ${position.toFixed(1)}s / ${duration > 0 ? duration.toFixed(1) : '??'}s`}
      </Text>
      <View style={styles.controls}>
        <Pressable
          onPress={() => {
            if (!ref.current) return;
            Commands.seek(ref.current, 0);
          }}
          style={styles.seekButton}
        >
          <Text style={styles.seekButtonText}>Seek 0s</Text>
        </Pressable>
        <Pressable
          onPress={() => {
            if (!ref.current) return;
            const target = duration > 0 ? Math.min(position + 15, duration) : position + 15;
            Commands.seek(ref.current, target);
          }}
          style={styles.seekButton}
        >
          <Text style={styles.seekButtonText}>+15s</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    flex: 1,
    marginVertical: 20,
  },
  controls: {
    flexDirection: 'row',
    justifyContent: 'center',
    paddingBottom: 24,
    paddingHorizontal: 16,
  },
  seekButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.15)',
    marginHorizontal: 8,
  },
  seekButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
});
