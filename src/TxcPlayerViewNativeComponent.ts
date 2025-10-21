import {
  codegenNativeCommands,
  codegenNativeComponent,
  type HostComponent,
  type ViewProps,
} from 'react-native';
import type * as React from 'react';
// @ts-ignore
import type {
  Int32,
  Float,
  DirectEventHandler,
  WithDefault,
} from 'react-native/Libraries/Types/CodegenTypes';

export type ChangeEvent = Readonly<{
  type: string;
  code?: Int32;
  message?: string;
  position?: Float;
  duration?: Float;
  buffered?: Float;
}>;

export type Source = Readonly<{
  url?: string;
  appId?: string;
  fileId?: string;
  psign?: string;
}>;

export type Subtitle = Readonly<{
  url: string;
  name: string;
  type?: string;
}>;

export type WatermarkConfig = Readonly<{
  type?: string;
  text: string;
  duration?: Float;
  fontSize?: Float;
  color?: string;
}>;

export type PlayerConfig = Readonly<{
  hideFullscreenButton?: boolean;
  hideFullScreenButton?: boolean;
  hideFloatWindowButton?: boolean;
  hidePipButton?: boolean;
  hideBackButton?: boolean;
  hideResolutionButton?: boolean;
  hidePlayButton?: boolean;
  hideProgressBar?: boolean;
  autoHideProgressBar?: WithDefault<boolean, true>;
  maxBufferSize?: Float;
  maxPreloadSize?: Float;
  disableDownload?: boolean;
  coverUrl?: string;
  dynamicWatermark?: WatermarkConfig;
  subtitles?: readonly Subtitle[];
}>;

interface NativeProps extends ViewProps {
  autoplay?: boolean;
  source?: Source;
  config?: PlayerConfig;
  onPlayerEvent?: DirectEventHandler<ChangeEvent>;
}

type NativeComponent = HostComponent<NativeProps>;

interface NativeCommands {
  pause(ref: React.ElementRef<NativeComponent>): void;
  resume(ref: React.ElementRef<NativeComponent>): void;
  reset(ref: React.ElementRef<NativeComponent>): void;
  seek(ref: React.ElementRef<NativeComponent>, position: Float): void;
}

export const Commands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['pause', 'resume', 'reset', 'seek'],
});

export default codegenNativeComponent<NativeProps>('TxcPlayerView', {
  interfaceOnly: false,
  paperComponentName: 'TxcPlayerView',
});

export type TxcPlayerViewRef = React.ElementRef<NativeComponent>;
