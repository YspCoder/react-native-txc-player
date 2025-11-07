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
          dispatchEvent("firstFrame", event, bundle.eventMessage())
        }
        TXLiveConstants.PLAY_EVT_PLAY_BEGIN -> {
          dispatchEvent("begin", event, bundle.eventMessage())
        }
        TXLiveConstants.PLAY_EVT_PLAY_END -> {
          hasStartedPlayback = false
          dispatchEvent("end", event, bundle.eventMessage())
        }
        TXLiveConstants.PLAY_EVT_VOD_LOADING_END -> {
          dispatchEvent("loadingEnd", event, bundle.eventMessage())
        }
        TXLiveConstants.PLAY_EVT_PLAY_PROGRESS -> {
          handleProgressEvent(bundle)
        }
        else -> {
          if (event < 0) {
            dispatchEvent("error", event, bundle?.eventMessage())
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
    maybeStartPlayback()
  }

  fun setPlaybackRate(rate: Double) {
    val clamped = if (rate > 0) rate else 1.0
    playbackRate = clamped.toFloat()
    UiThreadUtil.runOnUiThread {
      player.setRate(playbackRate)
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
        startPlayback(source)
      } else {
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

  private fun startPlayback(source: Source) {
    stopPlayback()
    player.setPlayerView(playerView)
    var result: Int? = null
    if (!source.url.isNullOrBlank()) {
      result = player.startVodPlay(source.url)
    } else if (!source.fileId.isNullOrBlank() && !source.appId.isNullOrBlank()) {
      val appIdValue = source.appId.toLongOrNull()
      if (appIdValue == null || appIdValue <= 0L) {
        dispatchEvent("error", -1, "Invalid appId for fileId playback")
        return
      }
      try {
        val params = TXPlayInfoParams(appIdValue.toInt(), source.fileId, source.psign)
        player.startVodPlay(params)
        result = 0
      } catch (e: Exception) {
        dispatchEvent("error", -1, e.message ?: "Invalid fileId source")
        return
      }
    } else {
      dispatchEvent("error", -1, "Invalid source payload")
      return
    }

    if (result != null && result < 0) {
      dispatchEvent("error", result, "Failed to start playback (TXVodPlayer)")
      return
    }

    player.setRate(playbackRate)
    hasStartedPlayback = true
  }

  private fun stopPlayback() {
    player.stopPlay(true)
    hasStartedPlayback = false
  }

  private fun handleProgressEvent(bundle: Bundle?) {
    val progressMs = bundle?.getInt(TXVodConstants.EVT_PLAY_PROGRESS)?.times(1000) ?: -1
    val durationMs = bundle?.getInt(TXVodConstants.EVT_PLAY_DURATION)?.times(1000) ?: -1
    val playableMs = bundle?.getInt(TXVodConstants.EVT_PLAYABLE_DURATION)?.times(1000)
      ?: bundle?.getInt(EVT_PLAYABLE_DURATION)?.times(1000)
      ?: -1

    if (progressMs < 0 && durationMs < 0 && playableMs < 0) {
      return
    }
    val now = SystemClock.elapsedRealtime()
    if (lastProgressTs > 0 && (now - lastProgressTs) < 250L) {
      return
    }
    lastProgressTs = now

    val positionSeconds = if (progressMs >= 0) progressMs / 1000.0 else null
    val durationSeconds = when {
      durationMs >= 0 -> durationMs / 1000.0
      player.duration > 0 -> player.duration.toDouble()
      else -> null
    }
    val bufferedSeconds = if (playableMs >= 0) playableMs / 1000.0 else null
    dispatchEvent(
      type = "progress",
      positionSeconds = positionSeconds,
      durationSeconds = durationSeconds,
      bufferedSeconds = bufferedSeconds
    )
    positionSeconds?.let { dispatchProgress(it) }
  }

  private fun dispatchEvent(
    type: String,
    code: Int? = null,
    message: String? = null,
    positionSeconds: Double? = null,
    durationSeconds: Double? = null,
    bufferedSeconds: Double? = null
  ) {
    val map = Arguments.createMap().apply {
      putString("type", type)
      code?.let { putInt("code", it) }
      message?.let { putString("message", it) }
      positionSeconds?.let { putDouble("position", it) }
      durationSeconds?.let { putDouble("duration", it) }
      bufferedSeconds?.let { putDouble("buffered", it) }
    }
    emitEvent("onPlayerEvent", map)
  }

  private fun dispatchProgress(positionSeconds: Double) {
    val map = Arguments.createMap().apply {
      putDouble("position", positionSeconds)
    }
    emitEvent("onProgress", map)
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
    reactContext?.removeLifecycleEventListener(this)
  }

  override fun onDetachedFromWindow() {
    super.onDetachedFromWindow()
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
