#import "TxcPlayerView.h"

#import <react/renderer/components/TxcPlayerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/TxcPlayerViewSpec/EventEmitters.h>
#import <react/renderer/components/TxcPlayerViewSpec/Props.h>
#import <react/renderer/components/TxcPlayerViewSpec/RCTComponentViewHelpers.h>

#import <React/RCTConversions.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>

#import <SuperPlayer/SuperPlayer.h> // SuperPlayerView / SuperPlayerModel / SuperPlayerVideoId
#import <SuperPlayer/SuperPlayerSmallWindowManager.h>
#import <SuperPlayer/DynamicWaterModel.h>
#import <SuperPlayer/SuperPlayerSubtitles.h>
#import <SuperPlayer/UIView+Fade.h>
#import "TXLiveSDKTypeDef.h"
#import "TXVodPlayer.h"
#import <QuartzCore/QuartzCore.h>
#import <float.h>
#import <math.h>
#import <SDWebImage/UIImageView+WebCache.h>
#import <objc/runtime.h>
#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

static BOOL sTXCDisableFloatWindow = NO;

@interface SuperPlayerSmallWindowManager (TXCDisable)
- (void)txc_show;
@end

@implementation SuperPlayerSmallWindowManager (TXCDisable)
- (void)txc_show
{
  if (sTXCDisableFloatWindow) {
    return;
  }
  [self txc_show];
}
@end

static void TXCEnsureFloatWindowSwizzled(void)
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = [SuperPlayerSmallWindowManager class];
    if (!cls) {
      return;
    }
    Method original = class_getInstanceMethod(cls, @selector(show));
    Method swizzled = class_getInstanceMethod(cls, @selector(txc_show));
    if (!original || !swizzled) {
      return;
    }
    method_exchangeImplementations(original, swizzled);
  });
}

static UIColor *TXCColorFromHexString(NSString *input)
{
  if (input.length == 0) {
    return nil;
  }

  NSString *cleanString = [[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
  if ([cleanString hasPrefix:@"#"]) {
    cleanString = [cleanString substringFromIndex:1];
  } else if ([cleanString hasPrefix:@"0X"]) {
    cleanString = [cleanString substringFromIndex:2];
  }

  if (cleanString.length == 3) {
    // Expand RGB to RRGGBB.
    unichar r = [cleanString characterAtIndex:0];
    unichar g = [cleanString characterAtIndex:1];
    unichar b = [cleanString characterAtIndex:2];
    cleanString = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
  } else if (cleanString.length == 4) {
    // Expand ARGB to AARRGGBB.
    unichar a = [cleanString characterAtIndex:0];
    unichar r = [cleanString characterAtIndex:1];
    unichar g = [cleanString characterAtIndex:2];
    unichar b = [cleanString characterAtIndex:3];
    cleanString = [NSString stringWithFormat:@"%C%C%C%C%C%C%C%C", a, a, r, r, g, g, b, b];
  }

  unsigned int value = 0;
  NSScanner *scanner = [NSScanner scannerWithString:cleanString];
  if (![scanner scanHexInt:&value]) {
    return nil;
  }

  if (cleanString.length == 6) {
    CGFloat r = ((value >> 16) & 0xFF) / 255.0;
    CGFloat g = ((value >> 8) & 0xFF) / 255.0;
    CGFloat b = (value & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
  } else if (cleanString.length == 8) {
    CGFloat a = ((value >> 24) & 0xFF) / 255.0;
    CGFloat r = ((value >> 16) & 0xFF) / 255.0;
    CGFloat g = ((value >> 8) & 0xFF) / 255.0;
    CGFloat b = (value & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
  }

  return nil;
}

@interface TxcPlayerView () <RCTTxcPlayerViewViewProtocol, SuperPlayerDelegate, SuperPlayerPlayListener>
@property (nonatomic, strong) SuperPlayerView *playerView;
@end

@implementation TxcPlayerView {
  BOOL _autoplay;
  BOOL _paused;
  NSDictionary *_Nullable _source;
  BOOL _hideFullscreenButton;
  BOOL _hideFloatWindow;
  BOOL _hidePipButton;
  BOOL _hideBackButton;
  BOOL _hideResolutionButton;
  BOOL _hidePlayButton;
  BOOL _hideProgressBar;
  BOOL _autoHideProgressBar;
  BOOL _disableDownload;
  CGFloat _maxBufferSize;
  CGFloat _maxPreloadSize;
  NSString *_Nullable _coverURLString;
  DynamicWaterModel *_Nullable _watermarkConfig;
  NSArray<SuperPlayerSubtitles *> *_Nullable _externalSubtitleModels;
  CFTimeInterval _lastProgressEventTs;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<TxcPlayerViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    TXCEnsureFloatWindowSwizzled();

    static const auto defaultProps = std::make_shared<const TxcPlayerViewProps>();
    _props = defaultProps;

    _playerView = [SuperPlayerView new];
    _playerView.delegate = self;
    _playerView.playListener = self;
    _playerView.fatherView = self;

    self.contentView = _playerView;
    self.clipsToBounds = YES;

    _autoplay = YES; // 默认自动播放
    _paused = NO;
    _hideFullscreenButton = NO;
    _hideFloatWindow = NO;
    _hidePipButton = NO;
    _hideBackButton = NO;
    _hideResolutionButton = NO;
    _hidePlayButton = NO;
    _hideProgressBar = NO;
    _autoHideProgressBar = YES;
    _disableDownload = NO;
    _maxBufferSize = 0;
    _maxPreloadSize = 0;
    _coverURLString = nil;
    _watermarkConfig = nil;
    _externalSubtitleModels = nil;
    _lastProgressEventTs = 0;
  }
  return self;
}

- (void)dealloc
{
  @try { [_playerView resetPlayer]; } @catch (__unused NSException *e) {}
  _playerView.playListener = nil;
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
  BOOL wasPaused = _paused;
  _paused = newViewProps.paused;

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

  _hideFullscreenButton = NO;
  _hideFloatWindow = NO;
  _hidePipButton = NO;
  _hideBackButton = NO;
  _hideResolutionButton = NO;
  _hidePlayButton = NO;
  _hideProgressBar = NO;
  _autoHideProgressBar = YES;
  _disableDownload = NO;
  _maxBufferSize = 0;
  _maxPreloadSize = 0;
  _coverURLString = nil;
  _watermarkConfig = nil;
  _externalSubtitleModels = nil;

  const auto &cfg = newViewProps.config;
  _hideFullscreenButton = cfg.hideFullscreenButton || cfg.hideFullScreenButton;
  _hideFloatWindow = cfg.hideFloatWindowButton;
  _hidePipButton = cfg.hidePipButton;
  _hideBackButton = cfg.hideBackButton;
  _hideResolutionButton = cfg.hideResolutionButton;
  _hidePlayButton = cfg.hidePlayButton;
  _hideProgressBar = cfg.hideProgressBar;
  _autoHideProgressBar = cfg.autoHideProgressBar;
  _disableDownload = cfg.disableDownload;
  _maxBufferSize = cfg.maxBufferSize;
  _maxPreloadSize = cfg.maxPreloadSize;

  if (!cfg.coverUrl.empty()) {
    _coverURLString = RCTNSStringFromString(cfg.coverUrl);
  }

  const auto &wm = cfg.dynamicWatermark;
  NSString *watermarkText = RCTNSStringFromString(wm.text);
  if (watermarkText.length > 0) {
    DynamicWaterModel *model = [DynamicWaterModel new];
    model.dynamicWatermarkTip = watermarkText;

    NSString *typeString = RCTNSStringFromString(wm.type);
    if (typeString.length > 0 && [typeString caseInsensitiveCompare:@"ghost"] == NSOrderedSame) {
      model.showType = ghost;
    } else {
      model.showType = dynamic;
    }

    if (wm.fontSize > 0.0f) {
      model.textFont = (CGFloat)wm.fontSize;
    }
    if (wm.duration > 0.0f) {
      model.duration = (int)wm.duration;
    }
    if (!wm.color.empty()) {
      UIColor *color = TXCColorFromHexString(RCTNSStringFromString(wm.color));
      if (color) {
        model.textColor = color;
      }
    }
    _watermarkConfig = model;
  }

  if (!cfg.subtitles.empty()) {
    NSMutableArray<SuperPlayerSubtitles *> *subtitleModels = [NSMutableArray arrayWithCapacity:cfg.subtitles.size()];
    for (const auto &subtitle : cfg.subtitles) {
      NSString *url = RCTNSStringFromString(subtitle.url);
      NSString *name = RCTNSStringFromString(subtitle.name);
      if (url.length == 0 || name.length == 0) {
        continue;
      }

      SuperPlayerSubtitles *sub = [SuperPlayerSubtitles new];
      sub.subtitlesUrl = url;
      sub.subtitlesName = name;
      NSString *typeString = RCTNSStringFromString(subtitle.type);
      if (typeString.length > 0 && [typeString caseInsensitiveCompare:@"vtt"] == NSOrderedSame) {
        sub.subtitlesType = SUPER_PLAYER_MIMETYPE_TEXT_VTT;
      } else if (typeString.length > 0) {
        sub.subtitlesType = SUPER_PLAYER_MIMETYPE_TEXT_SRT;
      }
      [subtitleModels addObject:sub];
    }
    if (subtitleModels.count > 0) {
      _externalSubtitleModels = [subtitleModels copy];
    }
  }


  // 在更新完 props 后再调用父类
  [super updateProps:props oldProps:oldProps];

  // 自动播放
  if (_autoplay && !_paused) {
    [self maybePlay];
  }

  if (_paused) {
    [self pause];
  } else if (wasPaused) {
    [self resume];
  }

  [self applyUIConfig];
  [self updateCoverImageIfNeeded];
  [self scheduleApplyVodConfigIfNeeded];
}

#pragma mark - Config Helpers

- (void)applyUIConfig
{
  dispatch_async(dispatch_get_main_queue(), ^{
    SPDefaultControlView *controlView = nil;
    if ([self.playerView.controlView isKindOfClass:SPDefaultControlView.class]) {
      controlView = (SPDefaultControlView *)self.playerView.controlView;
    }

    if (controlView) {
      controlView.enableFadeAction = self->_autoHideProgressBar;
      if (!self->_autoHideProgressBar) {
        [controlView fadeShow];
        [controlView cancelFadeOut];
      }

      controlView.fullScreenBtn.hidden = self->_hideFullscreenButton;
      controlView.fullScreenBtn.enabled = !self->_hideFullscreenButton;
      [controlView setDisableOfflineBtn:self->_disableDownload];

      controlView.disableBackBtn = self->_hideBackButton;
      controlView.backBtn.hidden = self->_hideBackButton;
      controlView.backBtn.enabled = !self->_hideBackButton;

      controlView.disableResolutionBtn = self->_hideResolutionButton;
      controlView.resolutionBtn.hidden = self->_hideResolutionButton;
      controlView.resolutionBtn.enabled = !self->_hideResolutionButton;

      controlView.disablePipBtn = self->_hidePipButton;
      controlView.pipBtn.hidden = self->_hidePipButton;
      controlView.pipBtn.enabled = !self->_hidePipButton;

      controlView.startBtn.hidden = self->_hidePlayButton;
      controlView.startBtn.enabled = !self->_hidePlayButton;

      controlView.videoSlider.hidden = self->_hideProgressBar;
      controlView.videoSlider.userInteractionEnabled = !self->_hideProgressBar;
      controlView.currentTimeLabel.hidden = self->_hideProgressBar;
      controlView.totalTimeLabel.hidden = self->_hideProgressBar;
    }

    if (self->_hidePipButton) {
      self.playerView.playerConfig.pipAutomatic = NO;
      self.playerView.playerConfig.forcedPIP = NO;
    }

    sTXCDisableFloatWindow = self->_hideFloatWindow;
    if (self->_hideFloatWindow) {
      [SuperPlayerWindowShared hide];
    }
  });
}

- (void)updateCoverImageIfNeeded
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_coverURLString.length == 0) {
      self.playerView.coverImageView.image = nil;
      return;
    }
    NSURL *url = [NSURL URLWithString:self->_coverURLString];
    if (!url) {
      return;
    }
    self.playerView.coverImageView.hidden = NO;
    [self.playerView.coverImageView sd_setImageWithURL:url placeholderImage:nil options:SDWebImageAvoidDecodeImage];
  });
}

- (DynamicWaterModel *)watermarkModelCopy
{
  if (!_watermarkConfig) {
    return nil;
  }
  DynamicWaterModel *model = [DynamicWaterModel new];
  model.textFont = _watermarkConfig.textFont;
  model.dynamicWatermarkTip = [_watermarkConfig.dynamicWatermarkTip copy];
  model.textColor = _watermarkConfig.textColor;
  model.duration = _watermarkConfig.duration;
  model.showType = _watermarkConfig.showType;
  return model;
}

- (NSMutableArray<SuperPlayerSubtitles *> *)subtitleModelsCopy
{
  if (_externalSubtitleModels.count == 0) {
    return nil;
  }
  NSMutableArray<SuperPlayerSubtitles *> *result = [NSMutableArray arrayWithCapacity:_externalSubtitleModels.count];
  for (SuperPlayerSubtitles *item in _externalSubtitleModels) {
    SuperPlayerSubtitles *copy = [SuperPlayerSubtitles new];
    copy.subtitlesUrl = item.subtitlesUrl;
    copy.subtitlesName = item.subtitlesName;
    copy.subtitlesType = item.subtitlesType;
    [result addObject:copy];
  }
  return result;
}

- (TXVodPlayer *)txc_currentVodPlayer
{
  if (![self.playerView respondsToSelector:NSSelectorFromString(@"vodPlayer")]) {
    return nil;
  }
  @try {
    return [self.playerView valueForKey:@"vodPlayer"];
  } @catch (__unused NSException *exception) {
    return nil;
  }
}

- (void)applyVodConfigIfNeeded
{
  TXVodPlayer *vodPlayer = [self txc_currentVodPlayer];
  if (!vodPlayer) {
    return;
  }

  TXVodPlayConfig *config = vodPlayer.config ?: [[TXVodPlayConfig alloc] init];
  BOOL mutated = NO;
  CGFloat desiredBuffer = _maxBufferSize < 0 ? 0 : _maxBufferSize;
  CGFloat desiredPreload = _maxPreloadSize < 0 ? 0 : _maxPreloadSize;
  if (fabs(config.maxBufferSize - desiredBuffer) > DBL_EPSILON) {
    config.maxBufferSize = desiredBuffer;
    mutated = YES;
  }
  if (fabs(config.maxPreloadSize - desiredPreload) > DBL_EPSILON) {
    config.maxPreloadSize = desiredPreload;
    mutated = YES;
  }

  if (mutated) {
    vodPlayer.config = config;
  }
}

- (void)scheduleApplyVodConfigIfNeeded
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self applyVodConfigIfNeeded];
  });
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
  } else if ([commandName isEqualToString:@"seek"]) {
    NSNumber *value = args.count > 0 ? args[0] : nil;
    if ([value isKindOfClass:[NSNumber class]]) {
      [self seekToSeconds:value.doubleValue];
    }
  } else {
    [super handleCommand:commandName args:args];
  }
}

#pragma mark - 控制 & 播放

- (void)pause { [_playerView pause]; }
- (void)resume { [_playerView resume]; }
- (void)reset  { [_playerView resetPlayer]; }

- (void)seekToSeconds:(double)seconds
{
  if (!isfinite(seconds)) {
    return;
  }

  double clamped = seconds;
  if (clamped < 0.0) {
    clamped = 0.0;
  }

  _lastProgressEventTs = 0;

  dispatch_async(dispatch_get_main_queue(), ^{
    TXVodPlayer *vodPlayer = [self txc_currentVodPlayer];
    if (vodPlayer) {
      [vodPlayer seek:(float)clamped];
    } else {
      [self.playerView seekToTime:(NSInteger)llround(clamped)];
    }
  });
}

- (void)maybePlay
{
  if (!_autoplay || !_source || _paused) return;

  SuperPlayerModel *model = [SuperPlayerModel new];

  if (_coverURLString.length > 0) {
    model.customCoverImageUrl = _coverURLString;
  }
  if (DynamicWaterModel *watermark = [self watermarkModelCopy]) {
    model.dynamicWaterModel = watermark;
  }
  if (NSMutableArray<SuperPlayerSubtitles *> *subs = [self subtitleModelsCopy]) {
    model.subtitlesArray = subs;
  }

  // 1) URL
  NSString *url = _source[@"url"];
  if ([url isKindOfClass:[NSString class]] && url.length > 0) {
    model.videoURL = url;
    [_playerView playWithModelNeedLicence:model];
    [self scheduleApplyVodConfigIfNeeded];
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
    [self scheduleApplyVodConfigIfNeeded];
    return;
  }

  RCTLogWarn(@"[TxcPlayerView] invalid source: %@", _source);
}


#pragma mark - 事件（Fabric EventEmitter）

- (void)emitChangeWithType:(NSString *)type
                      code:(NSNumber *_Nullable)code
                   message:(NSString *_Nullable)message
                  position:(NSNumber *_Nullable)position
                  duration:(NSNumber *_Nullable)duration
                  buffered:(NSNumber *_Nullable)buffered
{
  auto emitter = std::static_pointer_cast<const TxcPlayerViewEventEmitter>(_eventEmitter);
  if (!emitter) {
    return;
  }

  TxcPlayerViewEventEmitter::OnPlayerEvent event{
    .type = RCTStringFromNSString(type),
    .code = code ? code.intValue : 0,
    .message = message ? RCTStringFromNSString(message) : std::string(),
    .position = position ? position.doubleValue : 0.0,
    .duration = duration ? duration.doubleValue : 0.0,
    .buffered = buffered ? buffered.doubleValue : 0.0
  };
  emitter->onPlayerEvent(event);
}

- (void)emitChangeWithType:(NSString *)type code:(NSNumber *_Nullable)code message:(NSString *_Nullable)message
{
  [self emitChangeWithType:type code:code message:message position:nil duration:nil buffered:nil];
}

- (void)emitProgressPosition:(NSNumber *_Nullable)position
{
  if (!position) {
    return;
  }

  auto emitter = std::static_pointer_cast<const TxcPlayerViewEventEmitter>(_eventEmitter);
  if (!emitter) {
    return;
  }

  TxcPlayerViewEventEmitter::OnProgress event{
    .position = position.doubleValue
  };
  emitter->onProgress(event);
}

- (void)emitProgressWithParam:(NSDictionary *)param
{
  NSTimeInterval now = CACurrentMediaTime();
  if (_lastProgressEventTs > 0 && (now - _lastProgressEventTs) < 0.25) {
    return;
  }
  _lastProgressEventTs = now;

  NSNumber *progress = param[EVT_PLAY_PROGRESS];
  NSNumber *duration = param[EVT_PLAY_DURATION];
  NSNumber *playable = param[EVT_PLAYABLE_DURATION];

  if (!progress && param[@"EVT_PLAY_PROGRESS_MS"]) {
    progress = @([param[@"EVT_PLAY_PROGRESS_MS"] doubleValue] / 1000.0);
  }
  if (!duration && param[@"EVT_PLAY_DURATION_MS"]) {
    duration = @([param[@"EVT_PLAY_DURATION_MS"] doubleValue] / 1000.0);
  }
  if (!playable && param[@"EVT_PLAYABLE_DURATION_MS"]) {
    playable = @([param[@"EVT_PLAYABLE_DURATION_MS"] doubleValue] / 1000.0);
  }

  if (!progress && !duration && !playable) {
    return;
  }

  [self emitChangeWithType:@"progress" code:nil message:nil position:progress duration:duration buffered:playable];
  [self emitProgressPosition:progress];
}

- (void)superPlayerFullScreenChanged:(SuperPlayerView *)player
{
  [self emitChangeWithType:@"fullscreenChange" code:nil message:nil];
  [self applyUIConfig];
}
- (void)superPlayerBackAction:(SuperPlayerView *)player       { [self emitChangeWithType:@"back" code:nil message:nil]; }
- (void)superPlayerError:(SuperPlayerView *)player errCode:(int)code errMessage:(NSString *)why
{
  [self emitChangeWithType:@"error" code:@(code) message:why ?: @""];
}

- (void)onVodPlayEvent:(TXVodPlayer *)player event:(int)EvtID withParam:(NSDictionary *)param
{
  if (EvtID == PLAY_EVT_PLAY_PROGRESS) {
    [self emitProgressWithParam:param];
  }
}

#pragma mark - Utils


@end

// 工厂注册（保持不变）
Class<RCTComponentViewProtocol> TxcPlayerViewCls(void) { return TxcPlayerView.class; }
