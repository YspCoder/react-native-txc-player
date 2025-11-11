import {
  DeviceEventEmitter,
  NativeEventEmitter,
  NativeModules,
  Platform,
  type EmitterSubscription,
} from 'react-native';

const { RNTXCPreDownloadModule } = NativeModules;

const EVENT_NAME = 'txcPreDownload';

const emitter =
  Platform.OS === 'ios'
    ? new NativeEventEmitter(RNTXCPreDownloadModule)
    : DeviceEventEmitter;

export type PreDownloadOptions = Readonly<{
  url?: string;
  appId?: string | number;
  fileId?: string;
  psign?: string;
  preloadSizeMB?: number;
  preferredResolution?: number;
}>;

export type PreDownloadEvent =
  | Readonly<{
      type: 'start' | 'complete';
      taskId: number;
      url?: string | null;
      fileId?: string | null;
    }>
  | Readonly<{
      type: 'error';
      taskId: number;
      url?: string | null;
      fileId?: string | null;
      code?: number;
      message?: string | null;
    }>;

/**
 * Starts a LiteAV VOD pre-download task.
 * Resolves with the native task identifier.
 */
export function startPreDownload(options: PreDownloadOptions): Promise<number> {
  if (!RNTXCPreDownloadModule?.startPreDownload) {
    return Promise.reject(
      new Error('[TXCPlayer] Pre-download module not linked.')
    );
  }
  return RNTXCPreDownloadModule.startPreDownload(options);
}

/**
 * Stops a running pre-download task (best-effort).
 */
export function stopPreDownload(taskId: number) {
  if (typeof taskId !== 'number') {
    return;
  }
  RNTXCPreDownloadModule?.stopPreDownload?.(taskId);
}

/**
 * Subscribes to native pre-download lifecycle events.
 */
export function addPreDownloadListener(
  listener: (event: PreDownloadEvent) => void
): EmitterSubscription {
  return emitter.addListener(EVENT_NAME, listener);
}
