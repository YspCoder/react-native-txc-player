#import "RNTXCPreDownloadModule.h"

#import <React/RCTConvert.h>
#import <React/RCTUtils.h>
#import <TXLiteAVSDK_Player_Premium/TXPlayerAuthParams.h>

@interface RNTXCPreDownloadModule ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *taskMeta;
@end

@implementation RNTXCPreDownloadModule

RCT_EXPORT_MODULE(RNTXCPreDownloadModule);

- (instancetype)init
{
  if ((self = [super init])) {
    _taskMeta = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[ @"txcPreDownload" ];
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

RCT_REMAP_METHOD(startPreDownload,
                 startWithOptions:(NSDictionary *)options
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  NSString *url = [RCTConvert NSString:options[@"url"]];
  NSString *fileId = [RCTConvert NSString:options[@"fileId"]];
  NSString *psign = [RCTConvert NSString:options[@"psign"]];

  NSString *appIdString = nil;
  id appIdValue = options[@"appId"];
  if ([appIdValue respondsToSelector:@selector(stringValue)]) {
    appIdString = [appIdValue stringValue];
  } else {
    appIdString = [RCTConvert NSString:appIdValue];
  }

  double preloadSizeValue = options[@"preloadSizeMB"] ? [options[@"preloadSizeMB"] doubleValue] : 10.0;
  double preferredResolutionValue = options[@"preferredResolution"] ? [options[@"preferredResolution"] doubleValue] : -1.0;

  if (url.length == 0 && (fileId.length == 0 || appIdString.length == 0)) {
    reject(@"E_INVALID_SOURCE", @"Either `url` or (`appId` + `fileId`) must be provided.", nil);
    return;
  }

  float preloadSize = preloadSizeValue > 0 ? (float)preloadSizeValue : 0.f;
  long preferredResolution = preferredResolutionValue > 0 ? (long)preferredResolutionValue : -1L;

  int taskId = -1;
  if (url.length > 0) {
    taskId = [[TXVodPreloadManager sharedManager] startPreload:url
                                                  preloadSize:preloadSize
                                          preferredResolution:preferredResolution
                                                     delegate:self];
  } else {
    int appId = appIdString.intValue;
    if (appId <= 0) {
      reject(@"E_INVALID_SOURCE", @"Invalid `appId` value.", nil);
      return;
    }
    TXPlayerAuthParams *params = [[TXPlayerAuthParams alloc] init];
    params.appId = appId;
    params.fileId = fileId;
    if (psign.length > 0) {
      params.sign = psign;
    }
    taskId = [[TXVodPreloadManager sharedManager] startPreloadWithModel:params
                                                            preloadSize:preloadSize
                                                    preferredResolution:preferredResolution
                                                               delegate:self];
  }

  if (taskId <= 0) {
    reject(@"E_START_FAILED", @"Failed to start pre-download task.", nil);
    return;
  }

  @synchronized (self) {
    self.taskMeta[@(taskId)] = @{
      @"url": url ?: @"",
      @"fileId": fileId ?: @""
    };
  }

  resolve(@(taskId));
}

RCT_EXPORT_METHOD(stopPreDownload:(NSInteger)taskId)
{
  [[TXVodPreloadManager sharedManager] stopPreload:(int)taskId];
  @synchronized (self) {
    [self.taskMeta removeObjectForKey:@(taskId)];
  }
}

#pragma mark - TXVodPreloadManagerDelegate

- (void)onStart:(int)taskID fileId:(NSString *)fileId url:(NSString *)url param:(NSDictionary *)param
{
  [self cacheMeta:url fileId:fileId task:taskID];
  [self emitEventWithType:@"start" taskId:taskID url:url fileId:fileId code:0 message:nil];
}

- (void)onComplete:(int)taskID url:(NSString *)url
{
  NSDictionary *meta = [self popMetaForTask:taskID];
  NSString *fileId = meta[@"fileId"];
  [self emitEventWithType:@"complete" taskId:taskID url:(url.length ? url : meta[@"url"]) fileId:fileId code:0 message:nil];
}

- (void)onError:(int)taskID url:(NSString *)url error:(NSError *)error
{
  NSDictionary *meta = [self popMetaForTask:taskID];
  NSString *fileId = meta[@"fileId"];
  [self emitEventWithType:@"error"
                   taskId:taskID
                      url:(url.length ? url : meta[@"url"])
                   fileId:fileId
                     code:error.code
                  message:error.localizedDescription];
}

#pragma mark - Helpers

- (void)cacheMeta:(NSString *)url fileId:(NSString *)fileId task:(int)taskId
{
  @synchronized (self) {
    self.taskMeta[@(taskId)] = @{
      @"url": url ?: @"",
      @"fileId": fileId ?: @""
    };
  }
}

- (NSDictionary *)popMetaForTask:(int)taskId
{
  @synchronized (self) {
    NSDictionary *meta = self.taskMeta[@(taskId)];
    [self.taskMeta removeObjectForKey:@(taskId)];
    return meta ?: @{};
  }
}

- (void)emitEventWithType:(NSString *)type
                   taskId:(int)taskId
                      url:(NSString *)url
                   fileId:(NSString *)fileId
                     code:(NSInteger)code
                  message:(NSString *)message
{
  NSMutableDictionary *payload = [@{
    @"type": type,
    @"taskId": @(taskId)
  } mutableCopy];

  if (url.length > 0) {
    payload[@"url"] = url;
  }
  if (fileId.length > 0) {
    payload[@"fileId"] = fileId;
  }
  if ([type isEqualToString:@"error"]) {
    payload[@"code"] = @(code);
    if (message.length > 0) {
      payload[@"message"] = message;
    }
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [self sendEventWithName:@"txcPreDownload" body:payload];
  });
}

@end
