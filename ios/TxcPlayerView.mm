#import "TxcPlayerView.h"

#import <react/renderer/components/TxcPlayerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/TxcPlayerViewSpec/EventEmitters.h>
#import <react/renderer/components/TxcPlayerViewSpec/Props.h>
#import <react/renderer/components/TxcPlayerViewSpec/RCTComponentViewHelpers.h>

#import <React/RCTConversions.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>

#import <SuperPlayer/SuperPlayer.h> // SuperPlayerView / SuperPlayerModel / SuperPlayerVideoId
#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

@interface TxcPlayerView () <RCTTxcPlayerViewViewProtocol, SuperPlayerDelegate>
@property (nonatomic, strong) SuperPlayerView *playerView;
@end

@implementation TxcPlayerView {
  BOOL _autoplay;
  NSDictionary *_Nullable _source;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<TxcPlayerViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const TxcPlayerViewProps>();
    _props = defaultProps;

    _playerView = [SuperPlayerView new];
    _playerView.delegate = self;
    _playerView.fatherView = self;

    self.contentView = _playerView;
    self.clipsToBounds = YES;

    _autoplay = YES; // 默认自动播放
  }
  return self;
}

- (void)dealloc
{
  @try { [_playerView resetPlayer]; } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _playerView.frame = self.bounds;
}

#pragma mark - Props（Fabric / Codegen）

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<TxcPlayerViewProps const>(_props);
  const auto &newViewProps = *std::static_pointer_cast<TxcPlayerViewProps const>(props);

  _autoplay = newViewProps.autoplay;

  // source（对象，需要从 RawValue 转 NSDictionary 使用）
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  if (!newViewProps.source.url.empty()) {
    dict[@"url"] = RCTNSStringFromString(newViewProps.source.url);
  }
  if (!newViewProps.source.appId.empty())  {
    dict[@"appId"]  = RCTNSStringFromString(newViewProps.source.appId);
  } // 你要求 string
  if (!newViewProps.source.fileId.empty()) {
    dict[@"fileId"] = RCTNSStringFromString(newViewProps.source.fileId);
  }
  if (!newViewProps.source.psign.empty())  {
    dict[@"psign"]  = RCTNSStringFromString(newViewProps.source.psign);
  }
  _source = dict;


  // 在更新完 props 后再调用父类
  [super updateProps:props oldProps:oldProps];

  // 自动播放
  if (_autoplay) {
    [self maybePlay];
  }
}

#pragma mark - Commands（Fabric：codegen -> handleCommand）

- (void)handleCommand:(NSString *)commandName args:(NSArray *)args
{
  if ([commandName isEqualToString:@"pause"]) {
    [self pause];
  } else if ([commandName isEqualToString:@"resume"]) {
    [self resume];
  } else if ([commandName isEqualToString:@"reset"]) {
    [self reset];
  } else {
    [super handleCommand:commandName args:args];
  }
}

#pragma mark - 控制 & 播放

- (void)pause { [_playerView pause]; }
- (void)resume { [_playerView resume]; }
- (void)reset  { [_playerView resetPlayer]; }

- (void)maybePlay
{
  if (!_autoplay || !_source) return;

  SuperPlayerModel *model = [SuperPlayerModel new];

  // 1) URL
  NSString *url = _source[@"url"];
  if ([url isKindOfClass:[NSString class]] && url.length > 0) {
    model.videoURL = url;
    [_playerView playWithModelNeedLicence:model];
    return;
  }

  // 2) FileId（✅ appId 现在是 string）
  NSString *appIdStr = _source[@"appId"];
  NSString *fileId   = _source[@"fileId"];

  if ([appIdStr isKindOfClass:[NSString class]] &&
      appIdStr.length > 0 &&
      [fileId isKindOfClass:[NSString class]] &&
      fileId.length > 0) {

    // 尽量稳妥地把字符串转成无符号整型（支持较大数值）
    unsigned long long appIdULL = 0;
    NSScanner *scanner = [NSScanner scannerWithString:appIdStr];
    if ([scanner scanUnsignedLongLong:&appIdULL]) {
      model.appId = (UInt32)appIdULL; // SuperPlayerModel.appId 为 UInt32，截断在 SDK 侧定义
    } else {
      RCTLogWarn(@"[TxcPlayerView] invalid appId string: %@", appIdStr);
      return;
    }

    SuperPlayerVideoId *vid = [SuperPlayerVideoId new];
    vid.fileId = fileId;

    NSString *psign = _source[@"psign"];
    if ([psign isKindOfClass:[NSString class]] && psign.length > 0) {
      vid.psign = psign;
    }
    model.videoId = vid;

    [_playerView playWithModelNeedLicence:model];
    return;
  }

  RCTLogWarn(@"[TxcPlayerView] invalid source: %@", _source);
}


#pragma mark - 事件（Fabric EventEmitter）

- (void)emitChangeWithType:(NSString *)type code:(NSNumber * _Nullable)code message:(NSString * _Nullable)message
{
  NSLog(@"[TXC] superPlayerError code=%d msg=%@", code, message);
  auto emitter = std::static_pointer_cast<const TxcPlayerViewEventEmitter>(_eventEmitter);
  if (!emitter) return;

  TxcPlayerViewEventEmitter::OnPlayerEvent event{
    .type = RCTStringFromNSString(type),
    .code = code ? code.intValue : 0,
    .message = message ? RCTStringFromNSString(message) : std::string()
  };
  emitter->onPlayerEvent(event);
}

- (void)superPlayerFullScreenChanged:(SuperPlayerView *)player { [self emitChangeWithType:@"fullscreenChange" code:nil message:nil]; }
- (void)superPlayerBackAction:(SuperPlayerView *)player       { [self emitChangeWithType:@"back" code:nil message:nil]; }
- (void)superPlayerError:(SuperPlayerView *)player errCode:(int)code errMessage:(NSString *)why
{
  [self emitChangeWithType:@"error" code:@(code) message:why ?: @""];
}

#pragma mark - Utils


@end

// 工厂注册（保持不变）
Class<RCTComponentViewProtocol> TxcPlayerViewCls(void) { return TxcPlayerView.class; }
