import { codegenNativeCommands, codegenNativeComponent, type HostComponent, type ViewProps } from 'react-native';
// @ts-ignore
import type { Int32,DirectEventHandler } from 'react-native/Libraries/Types/CodegenTypes';

export type ChangeEvent = Readonly<{
  type: string;
  code?: Int32;
  message?: string;
}>;

export type Source = Readonly<{
  url?: string;
  appId?: string;
  fileId?: string;
  psign?: string;
}>;

interface NativeProps extends ViewProps {
  autoplay?: boolean;
  source?: Source;
  onPlayerEvent?: DirectEventHandler<ChangeEvent>;
}

type NativeComponent = HostComponent<NativeProps>;

interface NativeCommands {
  pause(ref: React.ElementRef<NativeComponent>): void;
  resume(ref: React.ElementRef<NativeComponent>): void;
  reset(ref: React.ElementRef<NativeComponent>): void;
}



export const Commands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['pause', 'resume', 'reset'],
});

export default codegenNativeComponent<NativeProps>('TxcPlayerView', {
  interfaceOnly: false,
  paperComponentName: 'TxcPlayerView',
});
