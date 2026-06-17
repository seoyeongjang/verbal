package com.voicebeta.verbal

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.CalendarContract
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.Base64
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val debugSpeakAction = "com.voicebeta.verbal.DEBUG_SPEAK"
    private val debugVoiceDraftAction = "com.voicebeta.verbal.DEBUG_VOICE_DRAFT"
    private val debugVoiceChannelName = "verbal/debug_voice"
    private val locationChannelName = "verbal/location"
    private val ttsChannelName = "verbal/briefing_tts"
    private val externalCalendarChannelName = "verbal/external_calendar"
    private val freeSpeechChannelName = "verbal/free_speech_recognizer"
    private val pcmSpeechChannelName = "verbal/pcm_speech_recognizer"
    private lateinit var freeSpeechChannel: MethodChannel
    private lateinit var pcmSpeechChannel: MethodChannel
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var speechRecognizer: SpeechRecognizer? = null
    private var speechActive = false
    private var speechStopping = false
    private var speechLanguage = "ko-KR"
    private var speechPreferOnDevice = false
    private var speechUsingOnDevice = false
    private var speechPartial = ""
    private var pendingSpeechStopResult: MethodChannel.Result? = null
    private val speechSegments = mutableListOf<String>()
    private val speechRestartHandler = Handler(Looper.getMainLooper())
    private var pendingDebugVoiceDraft: Map<String, Any?>? = null
    private var pcmSpeechRecognizer: SpeechRecognizer? = null
    private var pcmSpeechReadFd: ParcelFileDescriptor? = null
    private var pcmSpeechWriteFd: ParcelFileDescriptor? = null
    private var pcmSpeechOutput: ParcelFileDescriptor.AutoCloseOutputStream? = null
    private var pcmSpeechExecutor: ExecutorService? = null
    private var pcmSpeechActive = false
    private var pcmSpeechStopping = false
    private var pcmSpeechPartial = ""
    private var pcmSpeechLanguage = "ko-KR"
    private var pendingPcmSpeechStopResult: MethodChannel.Result? = null
    private val pcmSpeechSegments = mutableListOf<String>()
    private val pcmSpeechHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleDebugIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDebugIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        freeSpeechChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            freeSpeechChannelName
        )
        freeSpeechChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startFreeSpeech(call.argument<String>("language") ?: "ko-KR", result)
                "stop" -> stopFreeSpeechForResult(result)
                "cancel" -> {
                    stopFreeSpeech()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        pcmSpeechChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pcmSpeechChannelName
        )
        pcmSpeechChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startPcmSpeech(call.argument<String>("language") ?: "ko-KR", result)
                "writeAudio" -> {
                    val bytes = call.arguments as? ByteArray
                    writePcmSpeechAudio(bytes)
                    result.success(bytes != null)
                }
                "stop" -> stopPcmSpeechForResult(result)
                "cancel" -> {
                    stopPcmSpeech()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            debugVoiceChannelName
        ).setMethodCallHandler { call, result ->
            if (call.method != "consumeNextVoiceDraft") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (!isDebuggable()) {
                result.success(null)
                return@setMethodCallHandler
            }
            val draft = pendingDebugVoiceDraft
            pendingDebugVoiceDraft = null
            result.success(draft)
        }

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
        stopFreeSpeech()
        stopPcmSpeech()
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }

    private fun startFreeSpeech(language: String, result: MethodChannel.Result) {
        speechPreferOnDevice = false
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.success(false)
            return
        }
        if (
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(false)
            return
        }

        stopFreeSpeech()
        speechLanguage = language
        speechSegments.clear()
        speechPartial = ""
        speechActive = true
        speechStopping = false
        speechRecognizer = createFreeSpeechRecognizer(preferOnDevice = speechPreferOnDevice).also {
            it.setRecognitionListener(freeSpeechListener)
        }
        startFreeSpeechListening()
        result.success(true)
    }

    private fun isOnDeviceSpeechAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
    }

    private fun createFreeSpeechRecognizer(preferOnDevice: Boolean): SpeechRecognizer {
        return if (preferOnDevice && isOnDeviceSpeechAvailable()) {
            speechUsingOnDevice = true
            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        } else {
            speechUsingOnDevice = false
            SpeechRecognizer.createSpeechRecognizer(this)
        }
    }

    private fun restartFreeSpeechRecognizer(preferOnDevice: Boolean) {
        speechRecognizer?.setRecognitionListener(null)
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = createFreeSpeechRecognizer(preferOnDevice).also {
            it.setRecognitionListener(freeSpeechListener)
        }
    }

    private fun stopFreeSpeech() {
        pendingSpeechStopResult?.success(currentFreeSpeechTranscript())
        pendingSpeechStopResult = null
        speechActive = false
        speechStopping = true
        speechRestartHandler.removeCallbacksAndMessages(null)
        speechRecognizer?.setRecognitionListener(null)
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
        speechPartial = ""
    }

    private fun stopFreeSpeechForResult(result: MethodChannel.Result) {
        val recognizer = speechRecognizer
        if (recognizer == null || !speechActive) {
            result.success(currentFreeSpeechTranscript())
            stopFreeSpeech()
            return
        }

        pendingSpeechStopResult?.success(currentFreeSpeechTranscript())
        pendingSpeechStopResult = result
        speechActive = false
        speechStopping = true
        speechRestartHandler.removeCallbacksAndMessages(null)

        try {
            recognizer.stopListening()
        } catch (_: RuntimeException) {
            finishFreeSpeechStop()
            return
        }
        speechRestartHandler.postDelayed({ finishFreeSpeechStop() }, 1600L)
    }

    private fun finishFreeSpeechStop() {
        val result = pendingSpeechStopResult ?: return
        val transcript = currentFreeSpeechTranscript()
        pendingSpeechStopResult = null
        speechActive = false
        speechStopping = true
        speechRestartHandler.removeCallbacksAndMessages(null)
        speechRecognizer?.setRecognitionListener(null)
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
        speechPartial = ""
        result.success(transcript)
    }

    private fun startFreeSpeechListening() {
        val recognizer = speechRecognizer ?: return
        if (!speechActive || speechStopping) {
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, speechLanguage)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, speechLanguage)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, speechUsingOnDevice)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 300)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1200)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 900)
        try {
            recognizer.startListening(intent)
        } catch (error: RuntimeException) {
            if (speechUsingOnDevice) {
                speechPreferOnDevice = false
                restartFreeSpeechRecognizer(preferOnDevice = false)
                scheduleFreeSpeechRestart(delayMs = 60L)
                return
            }
            emitFreeSpeechError("start_failed")
        }
    }

    private fun scheduleFreeSpeechRestart(delayMs: Long = 180L) {
        if (!speechActive || speechStopping) {
            return
        }
        speechRestartHandler.removeCallbacksAndMessages(null)
        speechRestartHandler.postDelayed({ startFreeSpeechListening() }, delayMs)
    }

    private val freeSpeechListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit

        override fun onError(error: Int) {
            emitFreeSpeechError(if (speechUsingOnDevice) "on_device_$error" else error.toString())
            speechPartial = ""
            if (pendingSpeechStopResult != null || speechStopping) {
                finishFreeSpeechStop()
                return
            }
            if (speechUsingOnDevice && speechSegments.isEmpty()) {
                speechPreferOnDevice = false
                restartFreeSpeechRecognizer(preferOnDevice = false)
                scheduleFreeSpeechRestart(delayMs = 60L)
                return
            }
            if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            ) {
                scheduleFreeSpeechRestart()
            }
        }

        override fun onResults(results: Bundle?) {
            val transcript = firstSpeechResult(results)
            if (transcript.isNotBlank()) {
                val previous = speechSegments.lastOrNull()
                if (previous != transcript) {
                    speechSegments.add(transcript)
                }
            }
            speechPartial = ""
            emitFreeSpeechTranscript()
            if (pendingSpeechStopResult != null || speechStopping) {
                finishFreeSpeechStop()
                return
            }
            scheduleFreeSpeechRestart()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            speechPartial = firstSpeechResult(partialResults)
            emitFreeSpeechTranscript()
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun firstSpeechResult(bundle: Bundle?): String {
        return bundle
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            .orEmpty()
    }

    private fun currentFreeSpeechTranscript(): String {
        return (speechSegments + listOf(speechPartial))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .trim()
    }

    private fun emitFreeSpeechTranscript() {
        val transcript = currentFreeSpeechTranscript()
        if (transcript.isNotEmpty()) {
            freeSpeechChannel.invokeMethod(
                "onTranscript",
                mapOf("transcript" to transcript)
            )
        }
    }

    private fun emitFreeSpeechError(code: String) {
        freeSpeechChannel.invokeMethod("onError", mapOf("code" to code))
    }

    private fun startPcmSpeech(language: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(false)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.success(false)
            return
        }

        stopPcmSpeech()
        val pipe = try {
            ParcelFileDescriptor.createPipe()
        } catch (_: IOException) {
            result.success(false)
            return
        }
        pcmSpeechReadFd = pipe[0]
        pcmSpeechWriteFd = pipe[1]
        pcmSpeechOutput = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
        pcmSpeechExecutor = Executors.newSingleThreadExecutor()
        pcmSpeechLanguage = language
        pcmSpeechSegments.clear()
        pcmSpeechPartial = ""
        pcmSpeechActive = true
        pcmSpeechStopping = false
        pcmSpeechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).also {
            it.setRecognitionListener(pcmSpeechListener)
        }
        try {
            startPcmSpeechListening()
            result.success(true)
        } catch (_: RuntimeException) {
            stopPcmSpeech()
            result.success(false)
        }
    }

    private fun startPcmSpeechListening() {
        val recognizer = pcmSpeechRecognizer ?: return
        val readFd = pcmSpeechReadFd ?: return
        if (!pcmSpeechActive || pcmSpeechStopping) {
            return
        }
        try {
            recognizer.startListening(pcmSpeechIntent(readFd, pcmSpeechLanguage))
        } catch (_: RuntimeException) {
            emitPcmSpeechError("start_failed")
        }
    }

    private fun schedulePcmSpeechRestart(delayMs: Long = 90L) {
        if (!pcmSpeechActive || pcmSpeechStopping) {
            return
        }
        pcmSpeechHandler.removeCallbacksAndMessages(null)
        pcmSpeechHandler.postDelayed({ startPcmSpeechListening() }, delayMs)
    }

    private fun pcmSpeechIntent(
        audioSource: ParcelFileDescriptor,
        language: String
    ): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 300)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 500)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 300)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, audioSource)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            .putExtra(
                RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                AudioFormat.ENCODING_PCM_16BIT
            )
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
            .putExtra(
                RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                RecognizerIntent.EXTRA_AUDIO_SOURCE
            )
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    putExtra(
                        RecognizerIntent.EXTRA_ENABLE_FORMATTING,
                        RecognizerIntent.FORMATTING_OPTIMIZE_LATENCY
                    )
                    putExtra(
                        RecognizerIntent.EXTRA_HIDE_PARTIAL_TRAILING_PUNCTUATION,
                        true
                    )
                }
            }
    }

    private fun writePcmSpeechAudio(bytes: ByteArray?) {
        if (bytes == null || bytes.isEmpty() || !pcmSpeechActive || pcmSpeechStopping) {
            return
        }
        val output = pcmSpeechOutput ?: return
        val executor = pcmSpeechExecutor ?: return
        val copy = bytes.copyOf()
        executor.execute {
            try {
                output.write(copy)
                output.flush()
            } catch (_: IOException) {
                emitPcmSpeechError("audio_write_failed")
            }
        }
    }

    private fun stopPcmSpeechForResult(result: MethodChannel.Result) {
        if (!pcmSpeechActive || pcmSpeechRecognizer == null) {
            result.success(currentPcmSpeechTranscript())
            stopPcmSpeech()
            return
        }
        pendingPcmSpeechStopResult?.success(currentPcmSpeechTranscript())
        pendingPcmSpeechStopResult = result
        pcmSpeechActive = false
        pcmSpeechStopping = true
        closePcmSpeechOutput()
        try {
            pcmSpeechRecognizer?.stopListening()
        } catch (_: RuntimeException) {
            finishPcmSpeechStop()
            return
        }
        pcmSpeechHandler.postDelayed({ finishPcmSpeechStop() }, 750L)
    }

    private fun finishPcmSpeechStop() {
        val result = pendingPcmSpeechStopResult ?: return
        val transcript = currentPcmSpeechTranscript()
        pendingPcmSpeechStopResult = null
        cleanupPcmSpeechRecognizer()
        result.success(transcript)
    }

    private fun stopPcmSpeech() {
        pendingPcmSpeechStopResult?.success(currentPcmSpeechTranscript())
        pendingPcmSpeechStopResult = null
        pcmSpeechActive = false
        pcmSpeechStopping = true
        pcmSpeechHandler.removeCallbacksAndMessages(null)
        closePcmSpeechOutput()
        cleanupPcmSpeechRecognizer()
        pcmSpeechPartial = ""
    }

    private fun closePcmSpeechOutput() {
        val output = pcmSpeechOutput
        pcmSpeechOutput = null
        val executor = pcmSpeechExecutor
        if (output != null && executor != null) {
            executor.execute {
                try {
                    output.close()
                } catch (_: IOException) {
                    // Already closed.
                }
            }
        }
    }

    private fun cleanupPcmSpeechRecognizer() {
        pcmSpeechHandler.removeCallbacksAndMessages(null)
        pcmSpeechRecognizer?.setRecognitionListener(null)
        pcmSpeechRecognizer?.cancel()
        pcmSpeechRecognizer?.destroy()
        pcmSpeechRecognizer = null
        try {
            pcmSpeechReadFd?.close()
        } catch (_: IOException) {
            // Already closed.
        }
        try {
            pcmSpeechWriteFd?.close()
        } catch (_: IOException) {
            // Already closed.
        }
        pcmSpeechReadFd = null
        pcmSpeechWriteFd = null
        pcmSpeechOutput = null
        pcmSpeechExecutor?.shutdownNow()
        pcmSpeechExecutor = null
        pcmSpeechActive = false
        pcmSpeechStopping = true
    }

    private val pcmSpeechListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit

        override fun onError(error: Int) {
            emitPcmSpeechError(error.toString())
            if (pendingPcmSpeechStopResult != null || pcmSpeechStopping) {
                finishPcmSpeechStop()
                return
            }
            if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            ) {
                pcmSpeechPartial = ""
                schedulePcmSpeechRestart()
            }
        }

        override fun onResults(results: Bundle?) {
            applyPcmSpeechResult(results, finalResult = true)
            if (pendingPcmSpeechStopResult != null || pcmSpeechStopping) {
                finishPcmSpeechStop()
                return
            }
            schedulePcmSpeechRestart()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            applyPcmSpeechResult(partialResults, finalResult = false)
        }

        override fun onSegmentResults(segmentResults: Bundle) {
            applyPcmSpeechResult(segmentResults, finalResult = true)
        }

        override fun onEndOfSegmentedSession() {
            if (pendingPcmSpeechStopResult != null || pcmSpeechStopping) {
                finishPcmSpeechStop()
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun applyPcmSpeechResult(results: Bundle?, finalResult: Boolean) {
        val transcript = firstSpeechResult(results)
        if (transcript.isBlank()) {
            return
        }
        if (finalResult) {
            if (pcmSpeechSegments.lastOrNull() != transcript) {
                pcmSpeechSegments.add(transcript)
            }
            pcmSpeechPartial = ""
        } else {
            pcmSpeechPartial = transcript
        }
        emitPcmSpeechTranscript()
    }

    private fun currentPcmSpeechTranscript(): String {
        return (pcmSpeechSegments + listOf(pcmSpeechPartial))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .trim()
    }

    private fun emitPcmSpeechTranscript() {
        val transcript = currentPcmSpeechTranscript()
        if (transcript.isNotEmpty()) {
            pcmSpeechChannel.invokeMethod(
                "onTranscript",
                mapOf("transcript" to transcript)
            )
        }
    }

    private fun emitPcmSpeechError(code: String) {
        pcmSpeechChannel.invokeMethod("onError", mapOf("code" to code))
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

    private fun handleDebugIntent(intent: Intent?) {
        if (!isDebuggable()) {
            return
        }
        when (intent?.action) {
            debugSpeakAction -> {
                val text = debugSpeakText(intent)
                if (text.isEmpty()) {
                    return
                }
                val language = intent.getStringExtra("language") ?: "ko-KR"
                speakForDebugTest(text, language)
            }
            debugVoiceDraftAction -> {
                val audioPath = intent.getStringExtra("audioPath")?.trim().orEmpty()
                if (audioPath.isEmpty()) {
                    return
                }
                pendingDebugVoiceDraft = mapOf(
                    "audioFilePath" to audioPath,
                    "durationMs" to intent.getLongExtra("durationMs", 0L),
                    "transcript" to intent.getStringExtra("transcript").orEmpty()
                )
            }
        }
    }

    private fun debugSpeakText(intent: Intent): String {
        val plain = intent.getStringExtra("text")?.trim().orEmpty()
        if (plain.isNotEmpty()) {
            return plain
        }
        val encoded = intent.getStringExtra("textBase64")?.trim().orEmpty()
        if (encoded.isEmpty()) {
            return ""
        }
        return try {
            String(Base64.decode(encoded, Base64.NO_WRAP), Charsets.UTF_8).trim()
        } catch (_: IllegalArgumentException) {
            ""
        }
    }

    private fun isDebuggable(): Boolean {
        return (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun speakForDebugTest(text: String, language: String) {
        val speaker = tts
        if (speaker != null && ttsReady) {
            speakNow(speaker, text, language)
            return
        }
        tts = TextToSpeech(this) { status ->
            val initializedSpeaker = tts
            if (status == TextToSpeech.SUCCESS && initializedSpeaker != null) {
                ttsReady = true
                speakNow(initializedSpeaker, text, language)
            }
        }
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
