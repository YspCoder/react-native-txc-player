package com.txcplayer

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.viewmanagers.TxcPlayerViewManagerInterface
import com.facebook.react.viewmanagers.TxcPlayerViewManagerDelegate

@ReactModule(name = TxcPlayerViewManager.NAME)
class TxcPlayerViewManager : SimpleViewManager<TxcPlayerView>(),
  TxcPlayerViewManagerInterface<TxcPlayerView> {
  private val mDelegate: ViewManagerDelegate<TxcPlayerView> = TxcPlayerViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<TxcPlayerView> {
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

  override fun setPlaybackRate(view: TxcPlayerView, rate: Float) {
    view.setPlaybackRate(rate.toDouble())
  }

  override fun prepare(view: TxcPlayerView) {
    view.preparePlayback()
  }

  override fun onDropViewInstance(view: TxcPlayerView) {
    super.onDropViewInstance(view)
    view.cleanup()
  }

  companion object {
    const val NAME = "TxcPlayerView"
  }
}
