package com.txcplayer

import android.content.Context
import android.os.Bundle
import android.os.SystemClock
import android.widget.FrameLayout
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.facebook.react.uimanager.events.RCTModernEventEmitter
import com.tencent.rtmp.ITXVodPlayListener
import com.tencent.rtmp.TXLiveConstants
import com.tencent.rtmp.TXPlayInfoParams
import com.tencent.rtmp.TXVodConstants
import com.tencent.rtmp.TXVodPlayer
import com.tencent.rtmp.ui.TXCloudVideoView

private const val EVT_PLAYABLE_DURATION = "EVT_PLAYABLE_DURATION"
private const val EVT_MSG = "EVT_MSG"

class TxcPlayerView(context: Context) : FrameLayout(context), LifecycleEventListener {
  private val reactContext: ThemedReactContext? = context as? ThemedReactContext
  private val playerView = TXCloudVideoView(context)
  private val player = TXVodPlayer(context)

  private var isReleased = false
  private var pausedByProp = false
  private var hasStartedPlayback = false
  private var currentSource: Source? = null
  private var playbackRate = 1.0f
  private var lastProgressTs = 0L
  private var isPreloading = false

  private data class Source(
    val url: String?,
    val appId: String?,
    val fileId: String?,
    val psign: String?
  )

  private val vodListener = object : ITXVodPlayListener {
    override fun onPlayEvent(player: TXVodPlayer?, event: Int, bundle: Bundle?) {
      when (event) {
        TXLiveConstants.PLAY_EVT_RCV_FIRST_I_FRAME -> {
          dispatchEvent(
            type = "firstFrame",
            eventId = event,
            code = event,
            message = bundle.eventMessage()
          )
        }
        TXLiveConstants.PLAY_EVT_PLAY_BEGIN -> {
          if (!handlePrepared(event, bundle)) {
            dispatchEvent(
              type = "begin",
              eventId = event,
              code = event,
              message = bundle.eventMessage()
            )
          }
        }
        TXLiveConstants.PLAY_EVT_PLAY_END -> {
          hasStartedPlayback = false
          isPreloading = false
          dispatchEvent(
            type = "end",
            eventId = event,
            code = event,
            message = bundle.eventMessage()
          )
        }
        TXLiveConstants.PLAY_EVT_VOD_LOADING_START -> {
          dispatchEvent(
            type = "loadingStart",
            eventId = event,
            code = event,
            message = bundle.eventMessage()
          )
        }
        TXLiveConstants.PLAY_EVT_VOD_LOADING_END -> {
          if (!handlePrepared(event, bundle)) {
            dispatchEvent(
              type = "loadingEnd",
              eventId = event,
              code = event,
              message = bundle.eventMessage()
            )
          }
        }
        TXLiveConstants.PLAY_EVT_PLAY_PROGRESS -> {
          handleProgressEvent(bundle)
        }
        else -> {
          if (event < 0) {
            dispatchEvent(
              type = "error",
              eventId = event,
              code = event,
              message = bundle?.eventMessage()
            )
          }
        }
      }
    }

    override fun onNetStatus(player: TXVodPlayer?, bundle: Bundle?) = Unit
  }

  init {
    layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
    addView(playerView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

    player.setRenderMode(TXLiveConstants.RENDER_MODE_FULL_FILL_SCREEN)
    player.setVodListener(vodListener)
    player.setAutoPlay(true)
    player.setPlayerView(playerView)
    reactContext?.addLifecycleEventListener(this)
  }

  fun setPaused(value: Boolean) {
    if (pausedByProp == value) return
    pausedByProp = value
    if (value) {
      pausePlayback()
    } else {
      resumePlayback()
    }
  }

  fun setSource(map: ReadableMap?) {
    if (map == null) return
    val url = map.getStringSafe("url")
    val appId = map.getStringSafe("appId")
    val fileId = map.getStringSafe("fileId")
    val psign = map.getStringSafe("psign")
    currentSource = Source(url, appId, fileId, psign)
    isPreloading = false
    maybeStartPlayback()
  }

  fun setPlaybackRate(rate: Double) {
    val clamped = if (rate > 0) rate else 1.0
    playbackRate = clamped.toFloat()
    UiThreadUtil.runOnUiThread {
      player.setRate(playbackRate)
    }
  }

  fun preparePlayback() {
    if (isReleased) return
    val source = currentSource ?: return
    UiThreadUtil.runOnUiThread {
      if (isReleased) return@runOnUiThread
      isPreloading = true
      player.setAutoPlay(false)
      startPlayback(source, autoPlay = false)
    }
  }

  fun pausePlayback() {
    if (isReleased) return
    UiThreadUtil.runOnUiThread { player.pause() }
  }

  fun resumePlayback() {
    if (isReleased || pausedByProp) return
    UiThreadUtil.runOnUiThread {
      if (!hasStartedPlayback) {
        val source = currentSource ?: return@runOnUiThread
        player.setAutoPlay(true)
        startPlayback(source)
      } else {
        isPreloading = false
        player.resume()
      }
    }
  }

  fun resetPlayback() {
    stopPlayback()
    if (!pausedByProp) {
      maybeStartPlayback()
    }
  }

  fun destroyPlayback() {
    stopPlayback()
    currentSource = null
    hasStartedPlayback = false
    isPreloading = false
  }

  fun seekTo(positionSeconds: Double) {
    if (isReleased) return
    val clamped = if (positionSeconds < 0.0) 0.0 else positionSeconds
    UiThreadUtil.runOnUiThread { player.seek(clamped.toFloat()) }
  }

  private fun maybeStartPlayback() {
    if (isReleased || pausedByProp) return
    val source = currentSource ?: return
    UiThreadUtil.runOnUiThread { startPlayback(source) }
  }

  private fun startPlayback(source: Source, autoPlay: Boolean = true) {
    stopPlayback()
    player.setPlayerView(playerView)
    player.setAutoPlay(autoPlay)
    var result: Int? = null
    if (!source.url.isNullOrBlank()) {
      result = player.startVodPlay(source.url)
    } else if (!source.fileId.isNullOrBlank() && !source.appId.isNullOrBlank()) {
      val appIdValue = source.appId.toLongOrNull()
      if (appIdValue == null || appIdValue <= 0L) {
        dispatchEvent(
          type = "error",
          eventId = -1,
          code = -1,
          message = "Invalid appId for fileId playback"
        )
        return
      }
      try {
        val params = TXPlayInfoParams(appIdValue.toInt(), source.fileId, source.psign)
        player.startVodPlay(params)
        result = 0
      } catch (e: Exception) {
        dispatchEvent(
          type = "error",
          eventId = -1,
          code = -1,
          message = e.message ?: "Invalid fileId source"
        )
        return
      }
    } else {
      dispatchEvent(
        type = "error",
        eventId = -1,
        code = -1,
        message = "Invalid source payload"
      )
      return
    }

    if (result != null && result < 0) {
      dispatchEvent(
        type = "error",
        eventId = result,
        code = result,
        message = "Failed to start playback (TXVodPlayer)"
      )
      player.setAutoPlay(true)
      isPreloading = false
      return
    }

    player.setRate(playbackRate)
    hasStartedPlayback = true
    lastProgressTs = 0L
    isPreloading = !autoPlay
    if (!autoPlay) {
      UiThreadUtil.runOnUiThread { player.pause() }
    }
  }

  private fun stopPlayback() {
    player.stopPlay(true)
    hasStartedPlayback = false
    isPreloading = false
    lastProgressTs = 0L
  }

  private fun handleProgressEvent(bundle: Bundle?) {
    val metrics = bundle.extractPlaybackMetrics()

    if (metrics.positionSeconds == null &&
      metrics.durationSeconds == null &&
      metrics.bufferedSeconds == null
    ) {
      return
    }
    val now = SystemClock.elapsedRealtime()
    if (lastProgressTs > 0 && (now - lastProgressTs) < 250L) {
      return
    }
    lastProgressTs = now

    val positionSeconds = metrics.positionSeconds
    val durationSeconds = metrics.durationSeconds
      ?: if (player.duration > 0) player.duration.toDouble() else null
    val bufferedSeconds = metrics.bufferedSeconds
    dispatchEvent(
      type = "progress",
      eventId = TXLiveConstants.PLAY_EVT_PLAY_PROGRESS,
      positionSeconds = positionSeconds,
      durationSeconds = durationSeconds,
      bufferedSeconds = bufferedSeconds
    )
    dispatchProgress(positionSeconds, durationSeconds, bufferedSeconds)
  }

  private fun dispatchEvent(
    type: String,
    eventId: Int? = null,
    code: Int? = null,
    message: String? = null,
    positionSeconds: Double? = null,
    durationSeconds: Double? = null,
    bufferedSeconds: Double? = null
  ) {
    val map = Arguments.createMap().apply {
      putString("type", type)
      code?.let { putInt("code", it) }
      eventId?.let { putInt("event", it) }
      message?.let { putString("message", it) }
      positionSeconds?.let { putDouble("position", it) }
      durationSeconds?.let { putDouble("duration", it) }
      bufferedSeconds?.let { putDouble("buffered", it) }
    }
    emitEvent("onPlayerEvent", map)
  }

  private fun dispatchProgress(
    positionSeconds: Double?,
    durationSeconds: Double?,
    bufferedSeconds: Double?
  ) {
    if (positionSeconds == null && durationSeconds == null && bufferedSeconds == null) {
      return
    }
    val map = Arguments.createMap().apply {
      putDouble("position", positionSeconds ?: 0.0)
      durationSeconds?.let { putDouble("duration", it) }
      bufferedSeconds?.let { putDouble("buffered", it) }
    }
    emitEvent("onProgress", map)
  }

  private fun handlePrepared(event: Int, bundle: Bundle?): Boolean {
    if (!isPreloading) {
      return false
    }
    isPreloading = false
    UiThreadUtil.runOnUiThread {
      player.pause()
      player.setAutoPlay(true)
    }
    val metrics = bundle.extractPlaybackMetrics()
    dispatchEvent(
      type = "prepared",
      eventId = event,
      code = event,
      message = bundle.eventMessage(),
      positionSeconds = metrics.positionSeconds,
      durationSeconds = metrics.durationSeconds,
      bufferedSeconds = metrics.bufferedSeconds
    )
    dispatchProgress(metrics.positionSeconds, metrics.durationSeconds, metrics.bufferedSeconds)
    return true
  }

  private data class PlaybackMetrics(
    val positionSeconds: Double?,
    val durationSeconds: Double?,
    val bufferedSeconds: Double?
  )

  private fun Bundle?.extractPlaybackMetrics(): PlaybackMetrics {
    if (this == null) {
      return PlaybackMetrics(null, null, null)
    }
    val progressMs = when {
      containsKey(TXVodConstants.EVT_PLAY_PROGRESS) -> getInt(TXVodConstants.EVT_PLAY_PROGRESS) * 1000
      containsKey("EVT_PLAY_PROGRESS_MS") -> getInt("EVT_PLAY_PROGRESS_MS")
      else -> -1
    }
    val durationMs = when {
      containsKey(TXVodConstants.EVT_PLAY_DURATION) -> getInt(TXVodConstants.EVT_PLAY_DURATION) * 1000
      containsKey("EVT_PLAY_DURATION_MS") -> getInt("EVT_PLAY_DURATION_MS")
      else -> -1
    }
    val playableMs = when {
      containsKey(TXVodConstants.EVT_PLAYABLE_DURATION) ->
        getInt(TXVodConstants.EVT_PLAYABLE_DURATION) * 1000
      containsKey(EVT_PLAYABLE_DURATION) -> getInt(EVT_PLAYABLE_DURATION) * 1000
      containsKey("EVT_PLAYABLE_DURATION_MS") -> getInt("EVT_PLAYABLE_DURATION_MS")
      else -> -1
    }
    val positionSeconds = if (progressMs >= 0) progressMs / 1000.0 else null
    val durationSeconds = if (durationMs >= 0) durationMs / 1000.0 else null
    val bufferedSeconds = if (playableMs >= 0) playableMs / 1000.0 else null
    return PlaybackMetrics(positionSeconds, durationSeconds, bufferedSeconds)
  }

  private fun emitEvent(eventName: String, params: WritableMap?) {
    val context = reactContext ?: return
    val surfaceId = UIManagerHelper.getSurfaceId(this)
    if (surfaceId > 0) {
      context.getJSModule(RCTModernEventEmitter::class.java)
        ?.receiveEvent(surfaceId, id, eventName, params)
    } else {
      @Suppress("DEPRECATION")
      context.getJSModule(RCTEventEmitter::class.java)
        ?.receiveEvent(id, eventName, params)
    }
  }

  fun cleanup() {
    if (isReleased) return
    player.setVodListener(null)
    player.stopPlay(true)
    player.setPlayerView(null as TXCloudVideoView?)
    playerView.onDestroy()
    isReleased = true
    isPreloading = false
    reactContext?.removeLifecycleEventListener(this)
  }

  override fun onHostResume() {
    if (!isReleased && !pausedByProp) {
      player.resume()
    }
    playerView.onResume()
  }

  override fun onHostPause() {
    playerView.onPause()
    if (!isReleased) {
      player.pause()
    }
  }

  override fun onHostDestroy() {
    cleanup()
  }

  private fun ReadableMap.getStringSafe(key: String): String? {
    return if (hasKey(key) && getType(key) == ReadableType.String) getString(key) else null
  }

  private fun Bundle?.eventMessage(): String? {
    return this?.getString(EVT_MSG) ?: this?.getString(TXLiveConstants.EVT_DESCRIPTION)
  }
}
