package com.voicebeta.voice_messenger

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.provider.CalendarContract
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val locationChannelName = "voice_messenger/location"
    private val ttsChannelName = "voice_messenger/briefing_tts"
    private val externalCalendarChannelName = "voice_messenger/external_calendar"
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            locationChannelName
        ).setMethodCallHandler { call, result ->
            if (call.method != "currentLocation") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val location = currentLocation()
            if (location == null) {
                result.error(
                    "location_unavailable",
                    "Current location is unavailable.",
                    null
                )
                return@setMethodCallHandler
            }
            result.success(
                mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy.toDouble()
                )
            )
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ttsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text")?.trim().orEmpty()
                    val language = call.argument<String>("language") ?: "ko-KR"
                    if (text.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    speakBriefing(text, language, result)
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            externalCalendarChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "addEvent" -> openCalendarInsert(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }

    private fun speakBriefing(
        text: String,
        language: String,
        result: MethodChannel.Result
    ) {
        val speaker = tts
        if (speaker != null && ttsReady) {
            result.success(speakNow(speaker, text, language))
            return
        }

        tts = TextToSpeech(this) { status ->
            val initializedSpeaker = tts
            if (status != TextToSpeech.SUCCESS || initializedSpeaker == null) {
                result.error("tts_unavailable", "Text to speech is unavailable.", null)
                return@TextToSpeech
            }
            ttsReady = true
            result.success(speakNow(initializedSpeaker, text, language))
        }
    }

    private fun speakNow(speaker: TextToSpeech, text: String, language: String): Boolean {
        speaker.language = localeFor(language)
        speaker.setSpeechRate(0.95f)
        val status = speaker.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "calendar-briefing-${System.currentTimeMillis()}"
        )
        return status == TextToSpeech.SUCCESS
    }

    private fun localeFor(language: String): Locale {
        val parts = language.split("-", "_")
        return if (parts.size >= 2) {
            Locale(parts[0], parts[1])
        } else {
            Locale.KOREAN
        }
    }

    private fun openCalendarInsert(arguments: Any?, result: MethodChannel.Result) {
        val data = arguments as? Map<*, *>
        val title = data?.get("title") as? String
        val startAtMillis = (data?.get("startAtMillis") as? Number)?.toLong()
        val endAtMillis = (data?.get("endAtMillis") as? Number)?.toLong()
        val description = data?.get("description") as? String
        val target = data?.get("target") as? String
        if (title.isNullOrBlank() || startAtMillis == null || endAtMillis == null) {
            result.error("invalid_argument", "Calendar event payload is invalid.", null)
            return
        }

        val intent = Intent(Intent.ACTION_INSERT)
            .setDataAndType(
                CalendarContract.Events.CONTENT_URI,
                "vnd.android.cursor.item/event"
            )
            .putExtra(CalendarContract.Events.TITLE, title)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startAtMillis)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endAtMillis)
            .putExtra(CalendarContract.Events.DESCRIPTION, description.orEmpty())

        if (target == "google" && isPackageInstalled("com.google.android.calendar")) {
            intent.setPackage("com.google.android.calendar")
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            if (intent.`package` != null) {
                intent.setPackage(null)
                try {
                    startActivity(intent)
                    result.success(true)
                    return
                } catch (_: ActivityNotFoundException) {
                    // Report the original failure below.
                }
            }
            result.error("calendar_unavailable", "No calendar app can handle the event.", null)
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun currentLocation(): Location? {
        if (
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )
        return providers
            .mapNotNull { provider ->
                if (manager.isProviderEnabled(provider)) {
                    manager.getLastKnownLocation(provider)
                } else {
                    null
                }
            }
            .maxByOrNull { it.time }
    }
}
