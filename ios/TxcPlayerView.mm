#import "TxcPlayerView.h"

#import <react/renderer/components/TxcPlayerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/TxcPlayerViewSpec/EventEmitters.h>
#import <react/renderer/components/TxcPlayerViewSpec/Props.h>
#import <react/renderer/components/TxcPlayerViewSpec/RCTComponentViewHelpers.h>

#import <React/RCTConversions.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>

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
    dict[@"url"] = RCTNSStringFromString(newViewProps.source.url);
  }
  if (!newViewProps.source.appId.empty()) {
    dict[@"appId"] = RCTNSStringFromString(newViewProps.source.appId);
  }
  if (!newViewProps.source.fileId.empty()) {
    dict[@"fileId"] = RCTNSStringFromString(newViewProps.source.fileId);
  }
  if (!newViewProps.source.psign.empty()) {
    dict[@"psign"] = RCTNSStringFromString(newViewProps.source.psign);
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
  } else {
    [super handleCommand:commandName args:args];
  }
}

#pragma mark - Playback control

- (void)pause
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.player pause];
  });
}

- (void)resume
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self->_source) {
      return;
    }
    if (self->_hasStartedPlayback) {
      [self.player resume];
    } else {
      [self startPlaybackWithCurrentSource];
    }
  });
}

- (void)applyPlaybackRate
{
  double rate = _playbackRate > 0 ? _playbackRate : 1.0;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.player setRate:(float)rate];
  });
}

- (void)reset
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self stopPlaybackPreservingSurface:YES];
    self->_shouldStartPlayback = (self->_source != nil);
    self->_hasStartedPlayback = NO;
    self->_hasRenderedFirstFrame = NO;
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
    self->_source = nil;
    self->_shouldStartPlayback = NO;
    self->_hasStartedPlayback = NO;
    self->_hasRenderedFirstFrame = NO;
  });
}

- (void)seekToSeconds:(double)seconds
{
  dispatch_async(dispatch_get_main_queue(), ^{
    double target = seconds < 0 ? 0 : seconds;
    [self.player seek:(float)target];
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
    [self startPlaybackWithCurrentSource];
  });
}

- (void)startPlaybackWithCurrentSource
{
  if (_destroyed || !_source || _paused) {
    return;
  }

  [self stopPlaybackPreservingSurface:YES];
  [_player removeVideoWidget];
  [_player setupVideoWidget:_renderView insertIndex:0];

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
    return;
  }

  if (result < 0) {
    [self emitChangeWithType:@"error" code:@(result) message:@"Failed to start playback"];
    return;
  }

  _shouldStartPlayback = NO;
  _hasStartedPlayback = YES;
  _hasRenderedFirstFrame = NO;
  _lastProgressEventTs = 0;
  [self applyPlaybackRate];
}

- (void)stopPlaybackPreservingSurface:(BOOL)preserve
{
  [_player stopPlay];
  _hasStartedPlayback = NO;
  _hasRenderedFirstFrame = NO;
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
  TxcPlayerViewEventEmitter::OnProgress event{ .position = position.doubleValue };
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
  if (!_hasRenderedFirstFrame) {
    _hasRenderedFirstFrame = YES;
  }
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
  [self emitChangeWithType:@"begin" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)txc_handlePlayEndEvent:(int)EvtID param:(NSDictionary *)param
{
  _hasStartedPlayback = NO;
  _hasRenderedFirstFrame = NO;
  [self emitChangeWithType:@"end" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)txc_handleLoadingEndEvent:(int)EvtID param:(NSDictionary *)param
{
  [self emitChangeWithType:@"loadingEnd" code:@(EvtID) message:[self txc_eventMessageFromParam:param]];
}

- (void)onPlayEvent:(TXVodPlayer *)player event:(int)EvtID withParam:(NSDictionary *)param
{
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
  (void)player;
  (void)param;
}

#pragma mark - Utils

@end

Class<RCTComponentViewProtocol> TxcPlayerViewCls(void) { return TxcPlayerView.class; }
