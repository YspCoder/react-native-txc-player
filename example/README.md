# react-native-txc-player Example

This workspace contains a minimal React Native app that exercises the library on both platforms. It shows how to initialise the Tencent LiteAV licence, render the Fabric `TxcPlayerView`, and toggle pause/resume by tapping anywhere on the video surface.

## Prerequisites

- Install the project dependencies from the monorepo root: `yarn install`
- Provide a valid LiteAV licence URL/key inside `example/src/App.tsx` by calling `setTXCLicense`. The repository is pre-populated with a public demo key – replace it with your own for production testing.

## Running the app

```sh
# from the repository root
yarn example ios     # run on the iOS simulator
yarn example android # run on Android (device or emulator)
```

Metro will start automatically. Press anywhere on the video to pause; press again to resume. Player events are printed to the Metro console for quick inspection.

## What the sample covers

- Autoplay for Tencent VOD `fileId` playback
- Custom `config` surface (cover image, ghost watermark, external subtitle descriptor)
- Tap-to-pause/resume implemented through `Commands.pause` and `Commands.resume`
- Automatic teardown of the native player when the React component unmounts (avoiding GC pressure on Android)

Feel free to adapt the example when integrating the library into your own app.
