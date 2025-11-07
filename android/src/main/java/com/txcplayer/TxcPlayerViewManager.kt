package com.txcplayer

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.viewmanagers.TxcPlayerViewManagerInterface
import com.facebook.react.viewmanagers.TxcPlayerViewManagerDelegate

@ReactModule(name = TxcPlayerViewManager.NAME)
class TxcPlayerViewManager : SimpleViewManager<TxcPlayerView>(),
  TxcPlayerViewManagerInterface<TxcPlayerView> {
  private val mDelegate: ViewManagerDelegate<TxcPlayerView>

  init {
    mDelegate = TxcPlayerViewManagerDelegate(this)
  }

  override fun getDelegate(): ViewManagerDelegate<TxcPlayerView>? {
    return mDelegate
  }

  override fun getName(): String {
    return NAME
  }

  public override fun createViewInstance(context: ThemedReactContext): TxcPlayerView {
    return TxcPlayerView(context)
  }

  override fun setPaused(view: TxcPlayerView, value: Boolean) {
    view.setPaused(value)
  }

  override fun setSource(view: TxcPlayerView, value: ReadableMap?) {
    view.setSource(value)
  }

  override fun setPlaybackRate(view: TxcPlayerView, value: Double) {
    view.setPlaybackRate(value)
  }

  override fun pause(view: TxcPlayerView) {
    view.pausePlayback()
  }

  override fun resume(view: TxcPlayerView) {
    view.resumePlayback()
  }

  override fun reset(view: TxcPlayerView) {
    view.resetPlayback()
  }

  override fun destroy(view: TxcPlayerView) {
    view.destroyPlayback()
  }

  override fun seek(view: TxcPlayerView, position: Float) {
    view.seekTo(position.toDouble())
  }

  override fun receiveCommand(view: TxcPlayerView, commandId: String?, args: ReadableArray?) {
    when (commandId) {
      "pause" -> view.pausePlayback()
      "resume" -> view.resumePlayback()
      "reset" -> view.resetPlayback()
      "destroy" -> view.destroyPlayback()
      "seek" -> {
        val position = args?.takeIf { it.size() > 0 }?.getDouble(0)
        if (position != null) {
          view.seekTo(position)
        }
      }
    }
  }

  override fun receiveCommand(view: TxcPlayerView, commandId: Int, args: ReadableArray?) {
    when (commandId) {
      1 -> view.pausePlayback()
      2 -> view.resumePlayback()
      3 -> view.resetPlayback()
      4 -> {
        val position = args?.takeIf { it.size() > 0 }?.getDouble(0)
        if (position != null) {
          view.seekTo(position)
        }
      }
      5 -> view.destroyPlayback()
    }
  }

  override fun getCommandsMap(): MutableMap<String, Int> {
    return mutableMapOf(
      "pause" to 1,
      "resume" to 2,
      "reset" to 3,
      "seek" to 4,
      "destroy" to 5
    )
  }

  override fun onDropViewInstance(view: TxcPlayerView) {
    super.onDropViewInstance(view)
    view.cleanup()
  }

  companion object {
    const val NAME = "TxcPlayerView"
  }
}
