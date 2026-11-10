package com.vexoapp.vexo.audio

import android.content.Context
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import java.io.File

/** Records a voice note to a cache .m4a file. Call start(), then stop() which returns the file. */
class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var outFile: File? = null

    fun start() {
        val file = File(context.cacheDir, "voice_${System.currentTimeMillis()}.m4a")
        val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION") MediaRecorder()
        }
        rec.setAudioSource(MediaRecorder.AudioSource.MIC)
        rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        rec.setAudioEncodingBitRate(64_000)
        rec.setAudioSamplingRate(44_100)
        rec.setOutputFile(file.absolutePath)
        rec.prepare()
        rec.start()
        recorder = rec
        outFile = file
    }

    /** Stops and returns the file URI, or null if nothing was recorded. */
    fun stop(): Uri? {
        val rec = recorder ?: return null
        return try {
            rec.stop()
            outFile?.let { Uri.fromFile(it) }
        } catch (e: RuntimeException) {
            // stop() throws if recording was too short; discard it.
            outFile?.delete()
            null
        } finally {
            rec.release()
            recorder = null
        }
    }

    fun cancel() {
        recorder?.let {
            runCatching { it.stop() }
            it.release()
        }
        recorder = null
        outFile?.delete()
    }
}
