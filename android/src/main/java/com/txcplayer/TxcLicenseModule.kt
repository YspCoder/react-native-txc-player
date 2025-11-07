package com.txcplayer

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.tencent.rtmp.TXLiveBase

class TxcLicenseModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String = "RNTXCLicenseModule"

  @ReactMethod
  fun setLicense(url: String?, key: String?) {
    if (url.isNullOrEmpty() || key.isNullOrEmpty()) {
      return
    }
    TXLiveBase.getInstance().setLicence(reactApplicationContext, url, key)
  }
}
