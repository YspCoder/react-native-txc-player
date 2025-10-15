package com.txcplayer

import android.graphics.Color
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
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

  @ReactProp(name = "color")
  override fun setColor(view: TxcPlayerView?, color: String?) {
    view?.setBackgroundColor(Color.parseColor(color))
  }

  companion object {
    const val NAME = "TxcPlayerView"
  }
}
