package com.roundds.roundds

import android.media.audiofx.Visualizer
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot

class MainActivity : AudioServiceActivity() {
    private var visualizer: Visualizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val bands = 32

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "roundds/visualizer").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(messenger, "roundds/visualizer_ctrl").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sid = call.argument<Int>("sessionId") ?: 0
                    try {
                        startVisualizer(sid)
                        result.success(true)
                    } catch (e: Throwable) {
                        result.success(false)
                    }
                }
                "stop" -> {
                    stopVisualizer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVisualizer(sessionId: Int) {
        stopVisualizer()
        val v = Visualizer(sessionId)
        v.captureSize = Visualizer.getCaptureSizeRange()[1]
        v.setDataCaptureListener(
            object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(vis: Visualizer?, wf: ByteArray?, rate: Int) {}

                override fun onFftDataCapture(vis: Visualizer?, fft: ByteArray?, rate: Int) {
                    val data = fft ?: return
                    val out = DoubleArray(bands)
                    val n = data.size / 2
                    if (n <= 0) return
                    val perBand = (n / bands).coerceAtLeast(1)
                    for (b in 0 until bands) {
                        var sum = 0.0
                        for (k in 0 until perBand) {
                            val idx = (b * perBand + k) * 2
                            if (idx + 1 < data.size) {
                                val re = data[idx].toDouble()
                                val im = data[idx + 1].toDouble()
                                sum += hypot(re, im)
                            }
                        }
                        val mag = sum / perBand
                        // Перцептивная нормализация к 0..1 (fft-байты ~ -128..127).
                        out[b] = Math.sqrt(mag / 110.0).coerceIn(0.0, 1.0)
                    }
                    val list = out.toList()
                    runOnUiThread { eventSink?.success(list) }
                }
            },
            Visualizer.getMaxCaptureRate() / 2,
            false,
            true
        )
        v.enabled = true
        visualizer = v
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Throwable) {
        }
        visualizer = null
    }

    override fun onDestroy() {
        stopVisualizer()
        super.onDestroy()
    }
}
