package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import static androidx.media3.common.Player.*;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.util.Log;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;

public class PlayerEventListener implements Player.Listener {

    private static final String TAG = "PlayerEventListener";

    private AudioPlayerPlugin plugin;
    private AudioSource audioSource;

    public PlayerEventListener(AudioPlayerPlugin plugin, AudioSource audioSource) {
        this.plugin = plugin;
        this.audioSource = audioSource;
        this.audioSource.setEventListener(this);
    }

    @Override
    public void onIsPlayingChanged(boolean isPlaying) {
        String status = "stopped";

        if (audioSource.isInitialized()) {
            if (
                audioSource.getPlayer().getPlaybackState() == STATE_READY &&
                !audioSource.getPlayer().getPlayWhenReady() &&
                !audioSource.isStopped()
            ) {
                status = "paused";
                audioSource.setIsPaused();
            } else if (isPlaying || audioSource.isPlaying()) {
                status = "playing";
                audioSource.setIsPlaying();
            }
        }

        makeCall(
            audioSource.onPlaybackStatusChangeCallbackId,
            new JSObject().put("status", status)
        );
    }

    @Override
    public void onPlaybackStateChanged(@State int playbackState) {
        Log.d(TAG, "Playback state changed to: " + playbackState + " for audio: " + audioSource.id);

        switch (playbackState) {
            case STATE_READY:
                makeCall(audioSource.onReadyCallbackId);
                // Check if we recovered from stalling
                handleAudioStalled("likely_to_keep_up", false, true);
                break;

            case STATE_ENDED:
                audioSource.getPlayer().stop();
                audioSource.getPlayer().seekToDefaultPosition();
                audioSource.setIsStopped();
                makeCall(audioSource.onEndCallbackId);
                break;

            case STATE_BUFFERING:
                // Audio is buffering/stalling
                handleAudioStalled("buffer_empty", true, false);
                break;

            case STATE_IDLE:
                // Player is idle
                break;
        }
    }

    @Override
    public void onPlayerError(PlaybackException error) {
        Log.e(TAG, "Player error for audio: " + audioSource.id, error);
        handleAudioStalled("playback_stalled", false, false);
    }

    @Override
    public void onLoadingChanged(boolean isLoading) {
        if (isLoading) {
            handleAudioStalled("buffer_empty", true, false);
        } else {
            // Check if we can likely keep up
            Player player = audioSource.getPlayer();
            if (player != null) {
                boolean likelyToKeepUp = player.getPlaybackState() == Player.STATE_READY;
                if (likelyToKeepUp) {
                    handleAudioStalled("likely_to_keep_up", false, true);
                } else {
                    handleAudioStalled("stall_resolved", false, false);
                }
            }
        }
    }

    private void handleAudioStalled(String reason, boolean bufferEmpty, boolean likelyToKeepUp) {
        if (audioSource.onAudioStalledCallbackId != null) {
            try {
                JSObject result = new JSObject();
                result.put("reason", reason);
                result.put("currentTime", audioSource.getCurrentTime());
                result.put("duration", audioSource.getDuration());
                result.put("networkAvailable", isNetworkAvailable());

                if (reason.equals("buffer_empty") || reason.equals("stall_resolved")) {
                    result.put("bufferEmpty", bufferEmpty);
                }

                if (reason.equals("likely_to_keep_up")) {
                    result.put("likelyToKeepUp", likelyToKeepUp);
                }

                makeCall(audioSource.onAudioStalledCallbackId, result);
                Log.d(TAG, "Audio stalled callback triggered with reason: " + reason);
            } catch (Exception ex) {
                Log.e(TAG, "Error triggering audio stalled callback", ex);
            }
        }
    }

    private boolean isNetworkAvailable() {
        try {
            ConnectivityManager connectivityManager = (ConnectivityManager)
                plugin.getContext().getSystemService(Context.CONNECTIVITY_SERVICE);

            if (connectivityManager != null) {
                NetworkInfo activeNetworkInfo = connectivityManager.getActiveNetworkInfo();
                return activeNetworkInfo != null && activeNetworkInfo.isConnected();
            }
        } catch (Exception ex) {
            Log.w(TAG, "Error checking network availability", ex);
        }

        return false;
    }

    private void makeCall(String callbackId) {
        makeCall(callbackId, new JSObject());
    }

    private void makeCall(String callbackId, JSObject data) {
        if (callbackId == null) {
            return;
        }

        PluginCall call = plugin.getBridge().getSavedCall(callbackId);

        if (call == null) {
            return;
        }

        if (data.length() == 0) {
            call.resolve();
        } else {
            call.resolve(data);
        }
    }
}