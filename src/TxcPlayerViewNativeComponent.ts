import {
  codegenNativeCommands,
  codegenNativeComponent,
  type HostComponent,
  type ViewProps,
} from 'react-native';
import type * as React from 'react';
// @ts-ignore
import type {Int32, Float ,DirectEventHandler, WithDefault} from 'react-native/Libraries/Types/CodegenTypes';

export type ChangeEvent = Readonly<{
  type: string;
  code?: Int32;
  event?: Int32;
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

export type ProgressEvent = Readonly<{
  position: Float;
  duration?: Float;
  buffered?: Float;
}>;

interface NativeProps extends ViewProps {
  paused?: WithDefault<boolean, false>;
  source?: Source;
  playbackRate?: Float;
  onPlayerEvent?: DirectEventHandler<ChangeEvent>;
  onProgress?: DirectEventHandler<ProgressEvent>;
}

type NativeComponent = HostComponent<NativeProps>;

interface NativeCommands {
  pause(ref: React.ElementRef<NativeComponent>): void;
  resume(ref: React.ElementRef<NativeComponent>): void;
  reset(ref: React.ElementRef<NativeComponent>): void;
  seek(ref: React.ElementRef<NativeComponent>, position: Float): void;
  prepare(ref: React.ElementRef<NativeComponent>): void;
  destroy(ref: React.ElementRef<NativeComponent>): void;
}

export const Commands = codegenNativeCommands<NativeCommands>({
  supportedCommands: [
    'pause',
    'resume',
    'reset',
    'seek',
    'prepare',
    'destroy',
  ],
});

export default codegenNativeComponent<NativeProps>('TxcPlayerView', {
  interfaceOnly: false,
  paperComponentName: 'TxcPlayerView',
});

export type TxcPlayerViewRef = React.ElementRef<NativeComponent>;
