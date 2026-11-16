package com.example.movie_player

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    // The link that opened the app before Flutter was ready to hear it.
    private var pendingLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(pendingLink)
                    pendingLink = null
                }
                else -> result.notImplemented()
            }
        }
        // The intent that started this activity (share or "open with").
        deliver(intent, toFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The app was already running and just received another share.
        deliver(intent, toFlutter = true)
    }

    // Pulls the shared/opened link out of [intent] and either hands it to
    // Flutter or keeps it until Flutter asks for it.
    private fun deliver(intent: Intent?, toFlutter: Boolean) {
        if (intent == null) return
        val link = when (intent.action) {
            Intent.ACTION_SEND -> linkIn(
                intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
            )
            Intent.ACTION_VIEW -> intent.dataString ?: return
            else -> return
        } ?: return

        val target = channel
        if (toFlutter && target != null) {
            target.invokeMethod("onSharedLink", link)
        } else {
            // Flutter has not started yet: it asks for the link later.
            pendingLink = link
        }
    }

    // The url inside a shared text, which can be a bare sentence or a
    // scheme-less host.
    private fun linkIn(text: String): String? {
        Regex("https?://[^\\s]+").find(text)?.let { return it.value }
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.contains(' ')) return null
        return if (trimmed.contains("://") || trimmed.contains('.')) trimmed else null
    }

    companion object {
        private const val CHANNEL = "movie_player/shared_link"
    }
}
