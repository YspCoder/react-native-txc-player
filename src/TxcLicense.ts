import { NativeModules } from 'react-native';

const { RNTXCLicenseModule } = NativeModules;

/**
 * 设置 TXLiteAV（Player Premium）License 信息
 * @param url  腾讯云控制台 License URL
 * @param key  License Key
 */
export function setTXCLicense(url: string, key: string) {
  if (!RNTXCLicenseModule?.setLicense) {
    console.warn('[TXCPlayer] License module not found, make sure iOS bridge is linked.');
    return;
  }
  RNTXCLicenseModule.setLicense(url, key);
}
