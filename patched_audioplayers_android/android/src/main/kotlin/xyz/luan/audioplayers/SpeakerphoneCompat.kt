package xyz.luan.audioplayers

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

/**
 * Sets the speakerphone state without triggering the deprecation warning for
 * [AudioManager.isSpeakerphoneOn], which was deprecated in API 31 (Android 12).
 *
 * On API 31+ we route audio to / from the built-in speaker via
 * [AudioManager.setCommunicationDevice] / [AudioManager.clearCommunicationDevice].
 * On older APIs we fall back to the original (deprecated but still functional) setter.
 */
fun AudioManager.setSpeakerphoneOnCompat(enabled: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        if (enabled) {
            val speaker = getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            if (speaker != null) {
                setCommunicationDevice(speaker)
            }
        } else {
            clearCommunicationDevice()
        }
    } else {
        @Suppress("DEPRECATION")
        isSpeakerphoneOn = enabled
    }
}
