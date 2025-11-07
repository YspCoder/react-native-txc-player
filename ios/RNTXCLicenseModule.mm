//
//  RNTXCLicenseModule.mm
//  
//
//  Created by LPF on 2025/10/15.
//

#import "RNTXCLicenseModule.h"
#import <TXLiteAVSDK_Player_Premium/TXLiveBase.h>

@implementation RNTXCLicenseModule

// 模块名会变成 JS 中的 NativeModules.RNTXCLicenseModule
RCT_EXPORT_MODULE(RNTXCLicenseModule);

// 允许主线程调用
+ (BOOL)requiresMainQueueSetup { return YES; }

// JS: NativeModules.RNTXCLicenseModule.setLicense(url, key)
RCT_EXPORT_METHOD(setLicense:(NSString *)url key:(NSString *)key)
{
  if (url.length == 0 || key.length == 0) {
    NSLog(@"[TXCPlayer] License 参数为空，忽略设置");
    return;
  }

  [TXLiveBase setLicenceURL:url key:key];
  NSLog(@"[TXCPlayer] License 已设置: %@", url);
}

@end
