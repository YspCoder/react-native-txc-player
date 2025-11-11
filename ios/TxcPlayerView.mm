#import "TxcPlayerView.h"

#import <react/renderer/components/TxcPlayerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/TxcPlayerViewSpec/EventEmitters.h>
#import <react/renderer/components/TxcPlayerViewSpec/Props.h>
#import <react/renderer/components/TxcPlayerViewSpec/RCTComponentViewHelpers.h>

#import <React/RCTLog.h>
#import <React/RCTConvert.h>

#import <QuartzCore/QuartzCore.h>
#import <limits.h>
#import <float.h>
#import <math.h>

#import <TXLiteAVSDK_Player_Premium/TXVodPlayer.h>
#import <TXLiteAVSDK_Player_Premium/TXPlayerAuthParams.h>
#import <TXLiteAVSDK_Player_Premium/TXVodSDKEventDef.h>

#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

@interface TxcPlayerView () <RCTTxcPlayerViewViewProtocol, TXVodPlayListener>
@property (nonatomic, strong) TXVodPlayer *player;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *renderView;
- (void)setPlaybackRateFromCommand:(double)rate;
- (NSNumber *_Nullable)txc_secondsValueForParam:(NSDictionary *)param
                                            key:(NSString *)key
                                    fallbackKey:(NSString *_Nullable)fallbackKey;
@end

@implementation TxcPlayerView {
  BOOL _paused;
  BOOL _shouldStartPlayback;
  BOOL _hasStartedPlayback;
  BOOL _hasRenderedFirstFrame;
  BOOL _destroyed;
  NSDictionary *_Nullable _source;
  CFTimeInterval _lastProgressEventTs;
  double _playbackRate;
  BOOL _hasProgressSnapshot;
  BOOL _lastProgressHasPosition;
  double _lastProgressPosition;
  BOOL _lastProgressHasDuration;
  double _lastProgressDuration;
  BOOL _lastProgressHasBuffered;
  double _lastProgressBuffered;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<TxcPlayerViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const TxcPlayerViewProps>();
    _props = defaultProps;

    _player = [[TXVodPlayer alloc] init];
    _player.vodDelegate = self;
    _player.enableHWAcceleration = YES;
    _player.isAutoPlay = YES;

    _containerView = [UIView new];
    _containerView.clipsToBounds = YES;

    _renderView = [UIView new];
    _renderView.backgroundColor = UIColor.blackColor;

    [_containerView addSubview:_renderView];
    self.contentView = _containerView;

    [_player setupVideoWidget:_renderView insertIndex:0];
    [_player setAutoPictureInPictureEnabled:YES];

    _paused = NO;
    _shouldStartPlayback = NO;
    _hasStartedPlayback = NO;
    _hasRenderedFirstFrame = NO;
    _destroyed = NO;
    _lastProgressEventTs = 0;
    _playbackRate = 1.0;
    _hasProgressSnapshot = NO;
    _lastProgressHasPosition = NO;
    _lastProgressHasDuration = NO;
    _lastProgressHasBuffered = NO;
  }
  return self;
}

- (void)dealloc
{
  [self cleanupPlayer];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _containerView.frame = self.bounds;
  _renderView.frame = _containerView.bounds;
}

#pragma mark - Props

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &newViewProps = *std::static_pointer_cast<TxcPlayerViewProps const>(props);

  BOOL wasPaused = _paused;
  _paused = newViewProps.paused;

  NSDictionary *previousSource = _source;
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  if (!newViewProps.source.url.empty()) {
    dict[@"url"] = [NSString stringWithUTF8String:newViewProps.source.url.c_str()];

  }
  if (!newViewProps.source.appId.empty()) {
    dict[@"appId"] = [NSString stringWithUTF8String:newViewProps.source.appId.c_str()];
  }
  if (!newViewProps.source.fileId.empty()) {
    dict[@"fileId"] = [NSString stringWithUTF8String:newViewProps.source.fileId.c_str()];
  }
  if (!newViewProps.source.psign.empty()) {
    dict[@"psign"] = [NSString stringWithUTF8String:newViewProps.source.psign.c_str()];
  }
  NSDictionary *newSource = dict.count > 0 ? [dict copy] : nil;

  BOOL sourceChanged = NO;
  if (previousSource != newSource) {
    if (!previousSource || !newSource) {
      sourceChanged = YES;
    } else {
      sourceChanged = ![previousSource isEqualToDictionary:newSource];
    }
  }
  _source = newSource;

  if (sourceChanged) {
    _shouldStartPlayback = (_source != nil);
    _hasStartedPlayback = NO;
    _hasRenderedFirstFrame = NO;
    _lastProgressEventTs = 0;
    _hasProgressSnapshot = NO;
  }

  double incomingRate = newViewProps.playbackRate;
  double desiredRate = incomingRate > 0 ? incomingRate : 1.0;
  BOOL rateChanged = fabs(desiredRate - _playbackRate) > DBL_EPSILON;
  _playbackRate = desiredRate;
  if (rateChanged) {
    [self applyPlaybackRate];
  }

  [super updateProps:props oldProps:oldProps];

  if (_paused) {
    [self pause];
  } else if (wasPaused && _hasStartedPlayback) {
    [self resume];
  } else {
    [self maybeStartPlayback];
  }

}

#pragma mark - Commands

- (void)handleCommand:(NSString *)commandName args:(NSArray *)args
{
  if ([commandName isEqualToString:@"pause"]) {
    [self pause];
  } else if ([commandName isEqualToString:@"resume"]) {
    [self resume];
  } else if ([commandName isEqualToString:@"reset"]) {
    [self reset];
  } else if ([commandName isEqualToString:@"destroy"]) {
    [self destroy];
  } else if ([commandName isEqualToString:@"seek"]) {
    NSNumber *value = args.count > 0 ? args[0] : nil;
    if ([value isKindOfClass:NSNumber.class]) {
      [self seekToSeconds:value.doubleValue];
    }
  } else if ([commandName isEqualToString:@"setPlaybackRate"]) {
    NSNumber *value = args.count > 0 ? args[0] : nil;
    if ([value isKindOfClass:NSNumber.class]) {
      [self setPlaybackRateFromCommand:value.doubleValue];
    }
  } else {
    [super handleCommand:commandName args:args];
  }
}

#pragma mark - Playback control

- (void)pause
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    [self.player pause];
  });
}

- (void)resume
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    if (!self->_source) {
      return;
    }
    if (self->_hasStartedPlayback) {
      [self.player resume];
    } else {
      [self startPlaybackWithCurrentSourceAllowAutoPlay:YES];
    }
  });
}

- (void)applyPlaybackRate
{
  double rate = _playbackRate > 0 ? _playbackRate : 1.0;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    [self.player setRate:(float)rate];
  });
}

- (void)setPlaybackRateFromCommand:(double)rate
{
  double desiredRate = rate > 0 ? rate : 1.0;
  if (fabs(desiredRate - _playbackRate) > DBL_EPSILON) {
    _playbackRate = desiredRate;
    [self applyPlaybackRate];
  }
}

- (void)reset
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    [self stopPlaybackPreservingSurface:YES];
    self->_shouldStartPlayback = (self->_source != nil);
    self->_hasStartedPlayback = NO;
    self->_hasRenderedFirstFrame = NO;
    self->_lastProgressEventTs = 0;
    self->_hasProgressSnapshot = NO;
  });
}

- (void)destroy
{
  if (_destroyed) {
    return;
  }
  _destroyed = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self stopPlaybackPreservingSurface:NO];
    [self.player removeVideoWidget];
    self.player.vodDelegate = nil;
    self.player = nil;
    self->_source = nil;
    self->_shouldStartPlayback = NO;
    self->_hasStartedPlayback = NO;
    self->_hasRenderedFirstFrame = NO;
    self->_lastProgressEventTs = 0;
    self->_hasProgressSnapshot = NO;
  });
}

- (void)seekToSeconds:(double)seconds
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    double target = seconds < 0 ? 0 : seconds;
    [self.player seek:(float)target];
    self->_hasProgressSnapshot = NO;
    self->_lastProgressEventTs = 0;
  });
}

#pragma mark - Playback helpers

- (void)maybeStartPlayback
{
  if (_destroyed || _paused || !_source) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed || self->_paused || !self->_source) {
      return;
    }
    if (!self->_shouldStartPlayback && self->_hasStartedPlayback) {
      return;
    }
    self->_hasProgressSnapshot = NO;
    [self startPlaybackWithCurrentSource];
  });
}

- (void)startPlaybackWithCurrentSource
{
  [self startPlaybackWithCurrentSourceAllowAutoPlay:!_paused];
}

- (void)startPlaybackWithCurrentSourceAllowAutoPlay:(BOOL)allowAutoPlay
{
  if (_destroyed || !_source) {
    return;
  }
  if (allowAutoPlay && _paused) {
    return;
  }

  [self stopPlaybackPreservingSurface:YES];
  [_player removeVideoWidget];
  [_player setupVideoWidget:_renderView insertIndex:0];

  _player.isAutoPlay = allowAutoPlay;

  NSString *url = [_source objectForKey:@"url"];
  NSString *fileId = [_source objectForKey:@"fileId"];
  NSString *appIdString = [_source objectForKey:@"appId"];
  NSString *psign = [_source objectForKey:@"psign"];

  int result = -1;
  if ([url isKindOfClass:NSString.class] && url.length > 0) {
    result = [_player startVodPlay:url];
  } else if ([fileId isKindOfClass:NSString.class] && fileId.length > 0 && [appIdString isKindOfClass:NSString.class] && appIdString.length > 0) {
    unsigned long long appIdValue = strtoull(appIdString.UTF8String, NULL, 10);
    if (appIdValue == 0 || appIdValue > INT_MAX) {
      RCTLogWarn(@"[TxcPlayerView] invalid appId for fileId playback: %@", appIdString);
      [self emitChangeWithType:@"error" code:@(-1) message:@"Invalid appId value"];
      return;
    }
    TXPlayerAuthParams *params = [TXPlayerAuthParams new];
    params.appId = (int)appIdValue;
    params.fileId = fileId;
    if ([psign isKindOfClass:NSString.class] && psign.length > 0) {
      params.sign = psign;
    }
    result = [_player startVodPlayWithParams:params];
  } else {
    RCTLogWarn(@"[TxcPlayerView] invalid source: %@", _source);
    [self emitChangeWithType:@"error" code:@(-1) message:@"Invalid source"];
    _player.isAutoPlay = YES;
    return;
  }

  if (result < 0) {
    [self emitChangeWithType:@"error" code:@(result) message:@"Failed to start playback"];
    _player.isAutoPlay = YES;
    return;
  }

  _shouldStartPlayback = NO;
  _hasStartedPlayback = YES;
  _hasRenderedFirstFrame = NO;
  _lastProgressEventTs = 0;
  _hasProgressSnapshot = NO;
  [self applyPlaybackRate];

  if (!allowAutoPlay) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.player pause];
      self.player.isAutoPlay = YES;
    });
  }
}

- (void)stopPlaybackPreservingSurface:(BOOL)preserve
{
  [_player stopPlay];
  _hasStartedPlayback = NO;
  _hasRenderedFirstFrame = NO;
  _lastProgressEventTs = 0;
  _hasProgressSnapshot = NO;
  if (!preserve) {
    [_player removeVideoWidget];
  }
}

- (void)cleanupPlayer
{
  [_player stopPlay];
  [_player removeVideoWidget];
  _player.vodDelegate = nil;
  _player = nil;
}

#pragma mark - Events

- (void)emitChangeWithType:(NSString *)type
                      code:(NSNumber *_Nullable)code
                     event:(NSNumber *_Nullable)eventId
                   message:(NSString *_Nullable)message
                  position:(NSNumber *_Nullable)position
                  duration:(NSNumber *_Nullable)duration
                  buffered:(NSNumber *_Nullable)buffered
{
  auto emitter = std::static_pointer_cast<const TxcPlayerViewEventEmitter>(_eventEmitter);
  if (!emitter || _destroyed) {
    return;
  }

  TxcPlayerViewEventEmitter::OnPlayerEvent event{
    .type = type ? std::string([type UTF8String]) : std::string(),
    .code = code ? code.intValue : 0,
    .event = eventId ? eventId.intValue : 0,
    .message = message ? std::string([message UTF8String]) : std::string(),
    .position = position ? position.doubleValue : 0.0,
    .duration = duration ? duration.doubleValue : 0.0,
    .buffered = buffered ? buffered.doubleValue : 0.0
  };

  emitter->onPlayerEvent(event);
}

- (void)emitChangeWithType:(NSString *)type
                       code:(NSNumber *_Nullable)code
                      message:(NSString *_Nullable)message
{
  [self emitChangeWithType:type
                      code:code
                     event:code
                   message:message
                  position:nil
                  duration:nil
                  buffered:nil];
}

- (void)emitProgressPosition:(NSNumber *_Nullable)position
                     duration:(NSNumber *_Nullable)duration
                     buffered:(NSNumber *_Nullable)buffered
{
  if (!position && !duration && !buffered) {
    return;
  }
  auto emitter = std::static_pointer_cast<const TxcPlayerViewEventEmitter>(_eventEmitter);
  if (!emitter || _destroyed) {
    return;
  }
  TxcPlayerViewEventEmitter::OnProgress event{
    .position = position ? position.doubleValue : 0.0,
    .duration = duration ? duration.doubleValue : 0.0,
    .buffered = buffered ? buffered.doubleValue : 0.0,
  };
  emitter->onProgress(event);
}

- (NSNumber *_Nullable)txc_secondsValueForParam:(NSDictionary *)param
                                           key:(NSString *)key
                                   fallbackKey:(NSString *_Nullable)fallbackKey
{
  id value = param[key];
  if ([value respondsToSelector:@selector(doubleValue)]) {
    return @([value doubleValue]);
  }
  if (fallbackKey) {
    id fallbackValue = param[fallbackKey];
    if ([fallbackValue respondsToSelector:@selector(doubleValue)]) {
      return @([fallbackValue doubleValue] / 1000.0);
    }
  }
  return nil;
}

- (void)emitProgressWithParam:(NSDictionary *)param
{
  NSTimeInterval now = CACurrentMediaTime();
  if (_lastProgressEventTs > 0 && (now - _lastProgressEventTs) < 0.25) {
    return;
  }

  NSNumber *progress = [self txc_secondsValueForParam:param
                                                  key:EVT_PLAY_PROGRESS
                                          fallbackKey:@"EVT_PLAY_PROGRESS_MS"];
  NSNumber *duration = [self txc_secondsValueForParam:param
                                                  key:EVT_PLAY_DURATION
                                          fallbackKey:@"EVT_PLAY_DURATION_MS"];
  NSNumber *playable = [self txc_secondsValueForParam:param
                                                  key:EVT_PLAYABLE_DURATION
                                          fallbackKey:@"EVT_PLAYABLE_DURATION_MS"];

  if (!progress && !duration && !playable) {
    return;
  }

  if (![self txc_shouldEmitProgressForPosition:progress duration:duration buffered:playable]) {
    return;
  }

  _lastProgressEventTs = now;

  [self emitChangeWithType:@"progress"
                      code:nil
                     event:@(VOD_PLAY_EVT_PLAY_PROGRESS)
                   message:nil
                  position:progress
                  duration:duration
                  buffered:playable];
  [self emitProgressPosition:progress duration:duration buffered:playable];
  if (!_hasRenderedFirstFrame) {
    _hasRenderedFirstFrame = YES;
  }
}

- (BOOL)txc_shouldEmitProgressForPosition:(NSNumber *_Nullable)position
                                 duration:(NSNumber *_Nullable)duration
                                 buffered:(NSNumber *_Nullable)buffered
{
  const double epsilon = 0.05;
  BOOL hasPosition = (position != nil);
  BOOL hasDuration = (duration != nil);
  BOOL hasBuffered = (buffered != nil);

  if (!_hasProgressSnapshot) {
    _hasProgressSnapshot = YES;
    _lastProgressHasPosition = hasPosition;
    _lastProgressPosition = hasPosition ? position.doubleValue : 0.0;
    _lastProgressHasDuration = hasDuration;
    _lastProgressDuration = hasDuration ? duration.doubleValue : 0.0;
    _lastProgressHasBuffered = hasBuffered;
    _lastProgressBuffered = hasBuffered ? buffered.doubleValue : 0.0;
    return YES;
  }

  BOOL differs = NO;

  if (_lastProgressHasPosition != hasPosition) {
    differs = YES;
  } else if (hasPosition) {
    differs = fabs(position.doubleValue - _lastProgressPosition) > epsilon;
  }

  if (!differs) {
    if (_lastProgressHasDuration != hasDuration) {
      differs = YES;
    } else if (hasDuration) {
      differs = fabs(duration.doubleValue - _lastProgressDuration) > epsilon;
    }
  }

  if (!differs) {
    if (_lastProgressHasBuffered != hasBuffered) {
      differs = YES;
    } else if (hasBuffered) {
      differs = fabs(buffered.doubleValue - _lastProgressBuffered) > epsilon;
    }
  }

  if (differs) {
    _lastProgressHasPosition = hasPosition;
    _lastProgressPosition = hasPosition ? position.doubleValue : 0.0;
    _lastProgressHasDuration = hasDuration;
    _lastProgressDuration = hasDuration ? duration.doubleValue : 0.0;
    _lastProgressHasBuffered = hasBuffered;
    _lastProgressBuffered = hasBuffered ? buffered.doubleValue : 0.0;
  }

  return differs;
}

#pragma mark - TXVodPlayListener

- (NSString *)txc_eventMessageFromParam:(NSDictionary *)param
{
  id value = param[EVT_MSG];
  if ([value isKindOfClass:NSString.class]) {
    return value;
  }
  return nil;
}

- (void)txc_handleFirstFrameEvent:(int)EvtID param:(NSDictionary *)param
{
  _hasRenderedFirstFrame = YES;
  [self emitChangeWithType:@"firstFrame" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)txc_handlePlayBeginEvent:(int)EvtID param:(NSDictionary *)param
{
  _hasRenderedFirstFrame = YES;
  _hasProgressSnapshot = NO;
  _lastProgressEventTs = 0;
  [self emitChangeWithType:@"begin" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)txc_handlePlayEndEvent:(int)EvtID param:(NSDictionary *)param
{
  _hasStartedPlayback = NO;
  _hasRenderedFirstFrame = NO;
  _hasProgressSnapshot = NO;
  _lastProgressEventTs = 0;
  [self emitChangeWithType:@"end" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)txc_handleLoadingEndEvent:(int)EvtID param:(NSDictionary *)param
{
  [self emitChangeWithType:@"loadingEnd" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)onPlayEvent:(TXVodPlayer *)player event:(int)EvtID withParam:(NSDictionary *)param
{
  if (_destroyed) {
    return;
  }
  switch (EvtID) {
    case VOD_PLAY_EVT_RCV_FIRST_I_FRAME:
      [self txc_handleFirstFrameEvent:EvtID param:param];
      break;
    case VOD_PLAY_EVT_PLAY_BEGIN:
      [self txc_handlePlayBeginEvent:EvtID param:param];
      break;
    case VOD_PLAY_EVT_PLAY_END:
      [self txc_handlePlayEndEvent:EvtID param:param];
      break;
    case VOD_PLAY_EVT_PLAY_LOADING:
      [self emitChangeWithType:@"loadingStart" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
      break;
    case VOD_PLAY_EVT_VOD_LOADING_END:
      [self txc_handleLoadingEndEvent:EvtID param:param];
      break;
    case VOD_PLAY_EVT_PLAY_PROGRESS:
      [self emitProgressWithParam:param];
      break;
    default:
      if (EvtID < 0) {
        [self emitChangeWithType:@"error" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
      }
      break;
  }
}

- (void)onNetStatus:(TXVodPlayer *)player withParam:(NSDictionary *)param
{
  if (_destroyed) {
    return;
  }
  (void)player;
  (void)param;
}

#pragma mark - Utils

@end

Class<RCTComponentViewProtocol> TxcPlayerViewCls(void) { return TxcPlayerView.class; }
