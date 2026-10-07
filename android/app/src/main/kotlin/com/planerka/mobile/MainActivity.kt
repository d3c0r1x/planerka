package com.planerka.mobile

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

object LocalAiNative {
    init {
        System.loadLibrary("planerka_llama")
    }

    external fun generate(modelPath: String, prompt: String, maxTokens: Int): String
    external fun cancel()
    external fun loadModel(modelPath: String): Boolean
    external fun unload()
}

class MainActivity : FlutterActivity() {
    private val inference = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "planerka/local_ai")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "generate" -> {
                        val modelPath = call.argument<String>("modelPath")
                        val prompt = call.argument<String>("prompt")
                        val maxTokens = call.argument<Int>("maxTokens") ?: 256
                        if (modelPath.isNullOrBlank() || prompt.isNullOrBlank()) {
                            result.error("invalid_request", "Model path and prompt are required", null)
                        } else {
                            inference.execute {
                                try {
                                    val answer = LocalAiNative.generate(modelPath, prompt, maxTokens)
                                    mainHandler.post { result.success(answer) }
                                } catch (error: Throwable) {
                                    mainHandler.post {
                                        result.error("inference_failed", error.message, null)
                                    }
                                }
                            }
                        }
                    }
                    "cancel" -> {
                        LocalAiNative.cancel()
                        result.success(null)
                    }
                    "loadModel" -> {
                        val modelPath = call.argument<String>("modelPath")
                        if (modelPath.isNullOrBlank()) {
                            result.error("invalid_model", "Verified model path is required", null)
                        } else {
                            inference.execute {
                                try {
                                    val loaded = LocalAiNative.loadModel(modelPath)
                                    mainHandler.post { result.success(loaded) }
                                } catch (error: Throwable) {
                                    mainHandler.post {
                                        result.error("load_failed", error.message, null)
                                    }
                                }
                            }
                        }
                    }
                    "unload" -> {
                        inference.execute {
                            LocalAiNative.unload()
                            mainHandler.post { result.success(null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        inference.shutdownNow()
        super.onDestroy()
    }
}
