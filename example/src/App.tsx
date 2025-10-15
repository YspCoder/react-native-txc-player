import { useEffect, useRef, useState } from 'react';
import { View, StyleSheet, Alert, Text, Pressable } from 'react-native';
import { setTXCLicense, TxcPlayerView, Commands } from 'react-native-txc-player';

export default function App() {

  const ref = useRef<React.ElementRef<typeof TxcPlayerView>>(null);
  const [ready, setReady] = useState(false);
  const [isPlaying, setIsPlaying] = useState(true);

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
              autoplay={true}
            source={{
              appId: "1500039285",
              fileId: "5145403699454155159",
              psign:
                "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJhcHBJZCI6MTUwMDAzOTI4NSwiZmlsZUlkIjoiNTE0NTQwMzY5OTQ1NDE1NTE1OSIsImNvbnRlbnRJbmZvIjp7ImF1ZGlvVmlkZW9UeXBlIjoiUHJvdGVjdGVkQWRhcHRpdmUiLCJkcm1BZGFwdGl2ZUluZm8iOnsicHJpdmF0ZUVuY3J5cHRpb25EZWZpbml0aW9uIjoxNjQ1OTk0fX0sImN1cnJlbnRUaW1lU3RhbXAiOjE3NjA0OTQzNTMsImV4cGlyZVRpbWVTdGFtcCI6MTc2MDU4MDc1MywidXJsQWNjZXNzSW5mbyI6eyJ0IjoiNjhmMDU0OTEiLCJ1cyI6ImJjMTAxMzEyMzg4NDkyXzUxNDU0MDM2OTk0NTQxNTUxNTlfXzEifSwiZ2hvc3RXYXRlcm1hcmtJbmZvIjp7InRleHQiOiJcdTUyNjdcdTY2MWYifSwiZHJtTGljZW5zZUluZm8iOnsic3RyaWN0TW9kZSI6Mn19.kdMKYL9cnZdUXx4xjwZN3vSIPHi4cVXz-13z6Sw-04Y",
            }}
            config={{
              hideFullscreenButton: true,
              hideFloatWindowButton: true,
              hidePipButton: true,
              disableDownload: true,
              coverUrl: 'https://main.qcloudimg.com/raw/9a3f830b73fab9142c078f2c0c666cce.png',
            }}
              onPlayerEvent={(e: any) => {
                const evt = e.nativeEvent;
                console.log('[TXC event]', evt);
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
    width: '100%',
    height: '100%',
    marginVertical: 20,
  },
});
