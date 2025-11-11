package com.txcplayer

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.tencent.rtmp.TXPlayInfoParams
import com.tencent.rtmp.downloader.ITXVodFilePreloadListener
import com.tencent.rtmp.downloader.ITXVodPreloadListener
import com.tencent.rtmp.downloader.TXVodPreloadManager
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class TxcPreDownloadModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  private data class TaskMeta(
    val url: String?,
    val fileId: String?
  )

  private val executor = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, "txc-pre-download").apply { isDaemon = true }
  }
  private val tasks = ConcurrentHashMap<Int, TaskMeta>()

  override fun getName(): String = "RNTXCPreDownloadModule"

  @ReactMethod
  fun startPreDownload(options: ReadableMap, promise: Promise) {
    val url = options.getStringSafe("url")
    val fileId = options.getStringSafe("fileId")
    val appIdRaw = options.getStringish("appId")
    val psign = options.getStringSafe("psign")
    val preloadSizeMb = options.getDoubleSafe("preloadSizeMB", 10.0).toFloat().coerceAtLeast(0f)
    val preferredResolution =
      options.getDoubleSafe("preferredResolution", -1.0).toLong().let { if (it <= 0) -1 else it }

    if (url.isNullOrBlank() && (fileId.isNullOrBlank() || appIdRaw.isNullOrBlank())) {
      promise.reject(
        "E_INVALID_SOURCE",
        "Either `url` or (`appId` + `fileId`) must be provided."
      )
      return
    }

    executor.execute {
      try {
        val manager = TXVodPreloadManager.getInstance(reactApplicationContext)
        val taskId = if (!url.isNullOrBlank()) {
          manager.startPreload(
            url,
            preloadSizeMb,
            preferredResolution,
            object : ITXVodPreloadListener {
              override fun onComplete(taskID: Int, taskUrl: String) {
                tasks.remove(taskID)
                emitEvent("complete", taskID, taskUrl, null, null, null)
              }

              override fun onError(taskID: Int, taskUrl: String, code: Int, message: String) {
                tasks.remove(taskID)
                emitEvent("error", taskID, taskUrl, null, code, message)
              }
            }
          )
        } else {
          val appId = appIdRaw!!.toLongOrNull()?.toInt()
            ?: throw IllegalArgumentException("Invalid `appId` value.")
          val params = TXPlayInfoParams(appId, fileId, psign)
          manager.startPreload(
            params,
            preloadSizeMb,
            preferredResolution,
            object : ITXVodFilePreloadListener() {
              override fun onStart(
                taskID: Int,
                fid: String?,
                taskUrl: String,
                param: android.os.Bundle?
              ) {
                tasks[taskID] = TaskMeta(taskUrl, fid)
                emitEvent("start", taskID, taskUrl, fid, null, null)
              }

              override fun onComplete(taskID: Int, taskUrl: String) {
                val meta = tasks.remove(taskID)
                emitEvent("complete", taskID, taskUrl, meta?.fileId, null, null)
              }

              override fun onError(taskID: Int, taskUrl: String, code: Int, message: String) {
                val meta = tasks.remove(taskID)
                emitEvent("error", taskID, taskUrl, meta?.fileId, code, message)
              }
            }
          )
        }

        if (taskId <= 0) {
          promise.reject("E_START_FAILED", "Failed to start pre-download task.")
          return@execute
        }

        if (!url.isNullOrBlank()) {
          tasks[taskId] = TaskMeta(url, null)
          emitEvent("start", taskId, url, null, null, null)
        }

        UiThreadUtil.runOnUiThread { promise.resolve(taskId) }
      } catch (t: Throwable) {
        promise.reject("E_START_FAILED", t.message, t)
      }
    }
  }

  @ReactMethod
  fun stopPreDownload(taskId: Int) {
    executor.execute {
      try {
        TXVodPreloadManager.getInstance(reactApplicationContext).stopPreload(taskId)
      } catch (_: Throwable) {
      } finally {
        tasks.remove(taskId)
      }
    }
  }

  private fun emitEvent(
    type: String,
    taskId: Int,
    url: String?,
    fileId: String?,
    code: Int?,
    message: String?
  ) {
    val params = Arguments.createMap().apply {
      putString("type", type)
      putInt("taskId", taskId)
      if (url != null) {
        putString("url", url)
      }
      if (fileId != null) {
        putString("fileId", fileId)
      }
      code?.let { putInt("code", it) }
      message?.let { putString("message", it) }
    }
    UiThreadUtil.runOnUiThread {
      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit("txcPreDownload", params)
    }
  }
}

private fun ReadableMap.getDoubleSafe(key: String, fallback: Double): Double {
  return if (hasKey(key) && !isNull(key)) getDouble(key) else fallback
}

private fun ReadableMap.getStringSafe(key: String): String? {
  return if (hasKey(key) && !isNull(key)) getString(key) else null
}

private fun ReadableMap.getStringish(key: String): String? {
  if (!hasKey(key) || isNull(key)) {
    return null
  }
  return when (getType(key)) {
    ReadableType.String -> getString(key)
    ReadableType.Number -> {
      val value = getDouble(key)
      if (value % 1.0 == 0.0) {
        value.toLong().toString()
      } else {
        value.toString()
      }
    }
    else -> null
  }
}
