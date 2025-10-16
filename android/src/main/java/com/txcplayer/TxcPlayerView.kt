package com.txcplayer

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.view.isVisible
import com.facebook.drawee.generic.GenericDraweeHierarchyBuilder
import com.facebook.drawee.view.SimpleDraweeView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.modules.core.DeviceEventManagerModule.RCTEventEmitter
import com.facebook.react.uimanager.ThemedReactContext
import com.tencent.rtmp.ITXVodPlayListener
import com.tencent.rtmp.TXLiveConstants
import com.tencent.rtmp.TXPlayerAuthBuilder
import com.tencent.rtmp.TXVodPlayer
import com.tencent.rtmp.ui.TXCloudVideoView
import kotlin.math.roundToInt
import kotlin.random.Random

class TxcPlayerView(context: Context) : FrameLayout(context), LifecycleEventListener {
  private val reactContext: ThemedReactContext? = context as? ThemedReactContext
  private val handler = Handler(Looper.getMainLooper())
  private val playerView = TXCloudVideoView(context)
  private val coverView = SimpleDraweeView(context)
  private val watermarkView = TextView(context)
  private val player = TXVodPlayer(context)

  private var isReleased = false
  private var shouldAutoplay: Boolean = true
  private var currentSource: Source? = null
  private var config: PlayerConfig = PlayerConfig()
  private var watermarkRunnable: Runnable? = null
  private var hasStartedPlayback: Boolean = false

  private data class Source(
    val url: String?,
    val appId: String?,
    val fileId: String?,
    val psign: String?
  )

  private data class WatermarkConfig(
    val type: String?,
    val text: String,
    val durationSeconds: Float?,
    val fontSizeSp: Float?,
    val color: String?
  )

  private data class PlayerConfig(
    var hideFullscreenButton: Boolean = false,
    var hideFloatWindowButton: Boolean = false,
    var hidePipButton: Boolean = false,
    var disableDownload: Boolean = false,
    var coverUrl: String? = null,
    var watermark: WatermarkConfig? = null,
    var subtitles: List<SubtitleConfig> = emptyList()
  )

  private data class SubtitleConfig(
    val url: String,
    val name: String,
    val type: String?
  )

  private val vodListener = object : ITXVodPlayListener {
    override fun onPlayEvent(player: TXVodPlayer?, event: Int, bundle: Bundle?) {
      when (event) {
        TXLiveConstants.PLAY_EVT_RCV_FIRST_I_FRAME -> {
          coverView.visibility = View.GONE
          dispatchEvent("firstFrame", event, bundle?.getString(TXLiveConstants.EVT_DESCRIPTION))
        }
        TXLiveConstants.PLAY_EVT_PLAY_END -> {
          hasStartedPlayback = false
          dispatchEvent("end", event, bundle?.getString(TXLiveConstants.EVT_DESCRIPTION))
        }
        TXLiveConstants.PLAY_EVT_LOADING_END -> {
          dispatchEvent("loadingEnd", event, bundle?.getString(TXLiveConstants.EVT_DESCRIPTION))
        }
        TXLiveConstants.PLAY_EVT_PLAY_BEGIN -> {
          coverView.visibility = View.GONE
          dispatchEvent("begin", event, bundle?.getString(TXLiveConstants.EVT_DESCRIPTION))
        }
        else -> {
          if (event < 0) {
            dispatchEvent("error", event, bundle?.getString(TXLiveConstants.EVT_DESCRIPTION))
          }
        }
      }
    }

    override fun onNetStatus(player: TXVodPlayer?, bundle: Bundle?) = Unit
  }

  init {
    layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
    addView(playerView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

    coverView.hierarchy =
      GenericDraweeHierarchyBuilder(resources).setFadeDuration(200).build()
    coverView.visibility = View.GONE
    addView(coverView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

    watermarkView.visibility = View.GONE
    watermarkView.setTextColor(Color.WHITE)
    watermarkView.typeface = Typeface.DEFAULT_BOLD
    watermarkView.setShadowLayer(4f, 2f, 2f, Color.argb(90, 0, 0, 0))
    val watermarkParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
    watermarkParams.gravity = Gravity.TOP or Gravity.START
    addView(watermarkView, watermarkParams)

    player.setRenderMode(TXLiveConstants.RENDER_MODE_FILL_SCREEN)
    player.setVodListener(vodListener)
    player.setAutoPlay(true)
    player.setPlayerView(playerView)
    reactContext?.addLifecycleEventListener(this)
  }

  fun setAutoplay(value: Boolean) {
    shouldAutoplay = value
    player.setAutoPlay(value)
    maybeStartPlayback()
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

  fun setConfig(map: ReadableMap?) {
    if (map == null) {
      config = PlayerConfig()
      return
    }
    config.hideFullscreenButton = map.getBooleanSafe("hideFullscreenButton")
    config.hideFloatWindowButton = map.getBooleanSafe("hideFloatWindowButton")
    config.hidePipButton = map.getBooleanSafe("hidePipButton")
    config.disableDownload = map.getBooleanSafe("disableDownload")
    config.coverUrl = map.getStringSafe("coverUrl")
    config.subtitles = parseSubtitles(map)
    config.watermark = parseWatermark(map.getMapSafe("dynamicWatermark"))

    loadCover(config.coverUrl)
    applyWatermarkConfig(config.watermark)
  }

  fun pausePlayback() {
    if (isReleased) return
    player.pause()
  }

  fun resumePlayback() {
    if (isReleased) return
    if (!hasStartedPlayback) {
      val source = currentSource ?: return
      startPlayback(source)
    } else {
      player.resume()
    }
  }

  fun resetPlayback() {
    stopPlayback()
    if (shouldAutoplay) {
      maybeStartPlayback()
    }
  }

  private fun maybeStartPlayback() {
    if (isReleased || !shouldAutoplay) return
    val source = currentSource ?: return
    UiThreadUtil.runOnUiThread {
      startPlayback(source)
    }
  }

  private fun startPlayback(source: Source) {
    stopPlayback()
    if (!source.url.isNullOrBlank()) {
      player.startVodPlay(source.url)
    } else if (!source.fileId.isNullOrBlank() && !source.appId.isNullOrBlank()) {
      val appIdValue = source.appId.toLongOrNull()
      if (appIdValue == null || appIdValue <= 0L) {
        dispatchEvent("error", -1, "Invalid appId for fileId playback")
        return
      }
      try {
        val auth = TXPlayerAuthBuilder().apply {
          appId = appIdValue.toInt()
          fileId = source.fileId
          psign = source.psign
        }
        player.startVodPlay(auth)
      } catch (e: Exception) {
        dispatchEvent("error", -1, e.message ?: "Invalid fileId source")
      }
    }
    loadCover(config.coverUrl)
    applyWatermarkConfig(config.watermark)
    hasStartedPlayback = true
  }

  private fun stopPlayback() {
    player.stopPlay(true)
    hasStartedPlayback = false
  }

  private fun loadCover(url: String?) {
    if (url.isNullOrBlank()) {
      coverView.visibility = View.GONE
      return
    }
    coverView.visibility = View.VISIBLE
    runCatching { Uri.parse(url) }.onSuccess {
      coverView.setImageURI(it)
    }.onFailure {
      dispatchEvent("warning", -1, "Invalid coverUrl: ${it.message}")
    }
  }

  private fun applyWatermarkConfig(watermark: WatermarkConfig?) {
    handler.removeCallbacksAndMessages(null)
    watermarkRunnable = null
    if (watermark == null || watermark.text.isBlank()) {
      watermarkView.visibility = View.GONE
      return
    }
    watermarkView.visibility = View.VISIBLE
    watermarkView.text = watermark.text
    watermark.fontSizeSp?.let {
      val sizePx = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP,
        it,
        resources.displayMetrics
      )
      watermarkView.setTextSize(TypedValue.COMPLEX_UNIT_PX, sizePx)
    }
    watermark.color?.let {
      runCatching { Color.parseColor(it) }.onSuccess { color ->
        watermarkView.setTextColor(color)
      }
    }
    val alpha =
      if (watermark.type.equals("ghost", ignoreCase = true)) 0.3f else 0.6f
    watermarkView.alpha = alpha
    scheduleWatermarkMovement(watermark.durationSeconds ?: 4f)
  }

  private fun scheduleWatermarkMovement(intervalSeconds: Float) {
    if (!watermarkView.isVisible) return
    val intervalMs = (intervalSeconds * 1000f).coerceAtLeast(1500f)
    val runnable = object : Runnable {
      override fun run() {
        if (!watermarkView.isVisible || isReleased) return
        val parentWidth = width - watermarkView.width
        val parentHeight = height - watermarkView.height
        if (parentWidth > 0 && parentHeight > 0) {
          val targetX = Random.nextInt(parentWidth).toFloat()
          val targetY = Random.nextInt(parentHeight).toFloat()
          watermarkView.animate()
            .x(targetX)
            .y(targetY)
            .setDuration(800)
            .start()
        }
        handler.postDelayed(this, intervalMs.roundToInt().toLong())
      }
    }
    watermarkRunnable = runnable
    handler.post(runnable)
  }

  private fun parseWatermark(map: ReadableMap?): WatermarkConfig? {
    if (map == null) return null
    val text = map.getStringSafe("text") ?: return null
    val type = map.getStringSafe("type")
    val duration =
      if (map.hasKey("duration") && map.getType("duration") == ReadableType.Number) {
        map.getDouble("duration").toFloat()
      } else null
    val fontSize =
      if (map.hasKey("fontSize") && map.getType("fontSize") == ReadableType.Number) {
        map.getDouble("fontSize").toFloat()
      } else null
    val color = map.getStringSafe("color")
    return WatermarkConfig(type, text, duration, fontSize, color)
  }

  private fun parseSubtitles(map: ReadableMap): List<SubtitleConfig> {
    val array = map.getArraySafe("subtitles") ?: return emptyList()
    val result = mutableListOf<SubtitleConfig>()
    for (i in 0 until array.size()) {
      val item = array.getMap(i) ?: continue
      val url = item.getStringSafe("url") ?: continue
      val name = item.getStringSafe("name") ?: continue
      val type = item.getStringSafe("type")
      result.add(SubtitleConfig(url, name, type))
    }
    if (result.isNotEmpty()) {
      dispatchEvent(
        "subtitleNotice",
        0,
        "External subtitles provided (${result.size}) - please ensure LiteAV premium SDK is linked."
      )
    }
    return result
  }

  private fun dispatchEvent(type: String, code: Int?, message: String?) {
    val reactContext = this.reactContext ?: return
    val map = Arguments.createMap().apply {
      putString("type", type)
      code?.let { putInt("code", it) }
      message?.let { putString("message", it) }
    }
    reactContext.getJSModule(RCTEventEmitter::class.java)
      ?.receiveEvent(id, "onPlayerEvent", map)
  }

  fun cleanup() {
    if (isReleased) return
    handler.removeCallbacksAndMessages(null)
    watermarkRunnable = null
    player.setVodListener(null)
    player.stopPlay(true)
    player.setPlayerView(null)
    playerView.onDestroy()
    isReleased = true
    reactContext?.removeLifecycleEventListener(this)
  }

  override fun onDetachedFromWindow() {
    super.onDetachedFromWindow()
    handler.removeCallbacksAndMessages(null)
  }

  override fun onHostResume() {
    if (!isReleased && shouldAutoplay) {
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

  private fun ReadableMap.getBooleanSafe(key: String): Boolean {
    return if (hasKey(key) && getType(key) == ReadableType.Boolean) getBoolean(key) else false
  }

  private fun ReadableMap.getMapSafe(key: String): ReadableMap? {
    return if (hasKey(key) && getType(key) == ReadableType.Map) getMap(key) else null
  }

  private fun ReadableMap.getArraySafe(key: String): ReadableArray? {
    return if (hasKey(key) && getType(key) == ReadableType.Array) getArray(key) else null
  }
}
