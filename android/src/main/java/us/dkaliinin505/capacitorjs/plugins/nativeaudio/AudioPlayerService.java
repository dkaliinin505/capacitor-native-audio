package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import android.content.Intent;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;

public class AudioPlayerService extends MediaSessionService {

    private static final String TAG = "AudioPlayerService";
    public static final String PLAYBACK_CHANNEL_ID = "playback_channel";

    private MediaSession mediaSession = null;
    private PowerManager.WakeLock wakeLock = null;
    private WiFiLockManager wifiLockManager = null;

    @Override
    public void onCreate() {
        Log.i(TAG, "Service being created");
        super.onCreate();

        // Acquire wake lock to prevent network disconnections
        PowerManager powerManager = (PowerManager) getSystemService(POWER_SERVICE);
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "AudioPlayerService::WakeLock"
        );
        wakeLock.acquire(10 * 60 * 1000L /*10 minutes*/);

        // Acquire WiFi lock for stable streaming
        wifiLockManager = new WiFiLockManager(this);
        wifiLockManager.acquireLock();

        // Create ExoPlayer with robust configuration for long playback sessions
        ExoPlayer player = new ExoPlayer.Builder(this)
            .setLoadControl(RobustHlsConfig.createRobustLoadControl())
            .setAudioAttributes(
                new AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
                    .build(),
                true
            )
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setHandleAudioBecomingNoisy(true)  // Pause when headphones disconnected
            .build();

        player.setPlayWhenReady(false);

        mediaSession = new MediaSession.Builder(this, player)
            .setCallback(new MediaSessionCallback(this))
            .build();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "Service starting");

        // Return START_STICKY to restart service if killed by system
        return START_STICKY;
    }

    @Override
    public MediaSession onGetSession(MediaSession.ControllerInfo controllerInfo) {
        return mediaSession;
    }

    @Override
    public void onTaskRemoved(@Nullable Intent rootIntent) {
        Log.i(TAG, "Task removed");

        AudioSources audioSources = getAudioSourcesFromMediaSession();
        if (audioSources != null) {
            Log.i(TAG, "Destroying all non-notification audio sources");
            audioSources.destroyAllNonNotificationSources();
        }

        Player player = mediaSession.getPlayer();

        // Only stop if not playing notification audio
        if (player.getPlayWhenReady() && !hasNotificationAudio(audioSources)) {
            player.pause();
            stopSelf();
        }
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "Service being destroyed");

        // Release wake lock
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }

        // Release WiFi lock
        if (wifiLockManager != null) {
            wifiLockManager.releaseLock();
        }

        AudioSources audioSources = getAudioSourcesFromMediaSession();
        if (audioSources != null) {
            Log.i(TAG, "Destroying all non-notification audio sources");
            audioSources.destroyAllNonNotificationSources();
        }

        if (mediaSession != null) {
            mediaSession.getPlayer().release();
            mediaSession.release();
            mediaSession = null;
        }

        super.onDestroy();
    }

    @OptIn(markerClass = UnstableApi.class)
    private AudioSources getAudioSourcesFromMediaSession() {
        if (mediaSession == null) return null;

        IBinder sourcesBinder = mediaSession.getSessionExtras().getBinder("audioSources");
        if (sourcesBinder != null) {
            return (AudioSources) sourcesBinder;
        }
        return null;
    }

    private boolean hasNotificationAudio(AudioSources audioSources) {
        return audioSources != null && audioSources.hasNotification();
    }
}