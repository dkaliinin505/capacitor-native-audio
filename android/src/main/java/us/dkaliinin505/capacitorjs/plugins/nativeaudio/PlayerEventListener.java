package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import static androidx.media3.common.Player.*;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.datasource.HttpDataSource;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;
import java.net.SocketTimeoutException;
import java.io.IOException;

public class PlayerEventListener implements Player.Listener {

    private static final String TAG = "PlayerEventListener";
    private static final int MAX_RETRY_ATTEMPTS = 3;
    private static final long RETRY_DELAY_MS = 2000; // 2 seconds

    private AudioPlayerPlugin plugin;
    private AudioSource audioSource;
    private int retryCount = 0;
    private Handler retryHandler = new Handler(Looper.getMainLooper());

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
                // Reset retry count on successful playback
                retryCount = 0;
                audioSource.setIsPlaying();
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
                Log.d(TAG, "Player idle for: " + audioSource.id);
                break;
        }
    }

    @Override
    public void onPlayerError(PlaybackException error) {
        Log.e(TAG, "Player error occurred for audio: " + audioSource.id, error);

        if (shouldRetryError(error) && retryCount < MAX_RETRY_ATTEMPTS) {
            Log.i(TAG, "Attempting retry " + (retryCount + 1) + "/" + MAX_RETRY_ATTEMPTS + " for audio: " + audioSource.id);
            retryCount++;

            // Schedule retry after delay
            retryHandler.postDelayed(() -> {
                retryPlayback();
            }, RETRY_DELAY_MS * retryCount); // Exponential backoff

        } else {
            Log.e(TAG, "Max retries exceeded or non-recoverable error for audio: " + audioSource.id);
            retryCount = 0;
            audioSource.setIsStopped();

            // Trigger error callback
            handleAudioStalled("playback_stalled", false, false);
            if (audioSource.onEndCallbackId != null) {
                makeCall(audioSource.onEndCallbackId);
            }
        }
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

    private boolean shouldRetryError(PlaybackException error) {
        // Check if this is a recoverable network error
        Throwable cause = error.getCause();

        // Retry for network timeouts and connection issues
        if (cause instanceof HttpDataSource.HttpDataSourceException) {
            HttpDataSource.HttpDataSourceException httpError = (HttpDataSource.HttpDataSourceException) cause;
            Throwable httpCause = httpError.getCause();

            return httpCause instanceof SocketTimeoutException ||
                   httpCause instanceof IOException ||
                   httpError.dataSpec != null; // Has data spec, likely recoverable
        }

        // Retry for source errors that might be temporary
        return error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
               error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
               error.errorCode == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS;
    }

    private void retryPlayback() {
        try {
            Player player = audioSource.getPlayer();
            if (player != null) {
                Log.i(TAG, "Retrying playback for audio: " + audioSource.id);

                // Stop current playback
                player.stop();

                // Re-prepare the media source
                player.prepare();

                // Resume playback if it was playing before
                if (audioSource.isPlaying()) {
                    player.play();
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to retry playback for audio: " + audioSource.id, e);
            retryCount = 0;
            audioSource.setIsStopped();
            makeCall(audioSource.onEndCallbackId);
        }
    }

    public void resetRetryCount() {
        retryCount = 0;
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
        if (callbackId == null || plugin == null) {
            return;
        }

        try {
            PluginCall call = plugin.getBridge().getSavedCall(callbackId);
            if (call == null) {
                return;
            }

            if (data.length() == 0) {
                call.resolve();
            } else {
                call.resolve(data);
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to trigger callback: " + callbackId, e);
        }
    }
}