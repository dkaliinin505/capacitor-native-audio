package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import android.content.Context;
import android.net.Uri;
import android.os.Binder;
import android.util.Log;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.MediaSource;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;

public class AudioSource extends Binder {

    private static final String TAG = "AudioSource";

    public String id;
    public String source;
    public AudioMetadata audioMetadata;
    public boolean useForNotification;
    public boolean isBackgroundMusic;
    public boolean loopAudio = false;

    public String onPlaybackStatusChangeCallbackId;
    public String onReadyCallbackId;
    public String onEndCallbackId;
    public String onPlayNextCallbackId;
    public String onPlayPreviousCallbackId;
    public String onAudioStalledCallbackId;

    public AudioPlayerPlugin pluginOwner;

    private Player player;
    private PlayerEventListener playerEventListener;
    private Context context;

    private boolean isPlaying = false;
    private boolean isStopped = true;

    public AudioSource(
        AudioPlayerPlugin pluginOwner,
        String id,
        String source,
        AudioMetadata audioMetadata,
        boolean useForNotification,
        boolean isBackgroundMusic,
        boolean loopAudio
    ) {
        this.pluginOwner = pluginOwner;
        this.id = id;
        this.source = source;
        this.audioMetadata = audioMetadata;
        this.useForNotification = useForNotification;
        this.isBackgroundMusic = isBackgroundMusic;
        this.loopAudio = loopAudio;
    }

    public void initialize(Context context) {
        if (useForNotification || player != null) {
            return;
        }

        this.context = context;
        setIsStopped();

        // Create ExoPlayer with robust configuration for long playback sessions
        player = new ExoPlayer.Builder(context)
            .setLoadControl(RobustHlsConfig.createRobustLoadControl())
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build();

        setPlayerAttributes();
        player.prepare();
    }

    public void setPlayerAttributes() {
        player.setAudioAttributes(
            new AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(
                    useForNotification ? C.AUDIO_CONTENT_TYPE_SPEECH : C.AUDIO_CONTENT_TYPE_MUSIC
                )
                .build(),
            useForNotification
        );

        player.setMediaItem(buildMediaItem());
        player.setRepeatMode(loopAudio ? ExoPlayer.REPEAT_MODE_ONE : ExoPlayer.REPEAT_MODE_OFF);
        player.setPlayWhenReady(false);

        // Add event listener with retry logic
        playerEventListener = new PlayerEventListener(pluginOwner, this);
        player.addListener(playerEventListener);
    }

    public void changeAudioSource(String newSource) {
        source = newSource;

        Player player = getPlayer();

        // Update the media item instead of setting media source directly
        player.setMediaItem(buildMediaItem());
        player.setPlayWhenReady(false);
        player.prepare();

        // Reset retry count when changing sources
        if (playerEventListener != null) {
            playerEventListener.resetRetryCount();
        }
    }

    public void changeMetadata(AudioMetadata metadata) {
        this.audioMetadata = metadata;

        var currentMediaItem = getPlayer().getCurrentMediaItem();
        if (currentMediaItem != null) {
            var newMediaItem = currentMediaItem
                .buildUpon()
                .setMediaMetadata(getMediaMetadata())
                .build();

            getPlayer().replaceMediaItem(0, newMediaItem);
        }
    }

    public float getDuration() {
        long duration = getPlayer().getDuration();

        if (duration == C.TIME_UNSET) {
            return -1;
        }

        return duration / 1000;
    }

    public float getCurrentTime() {
        return getPlayer().getCurrentPosition() / 1000;
    }

    public void play() {
        setIsPlaying();

        Player player = getPlayer();

        if (player.getPlaybackState() == Player.STATE_IDLE) {
            player.prepare();
        }

        player.play();
    }

    public void pause() {
        setIsPaused();
        getPlayer().pause();
    }

    public void seek(long timeInSeconds) {
        getPlayer().seekTo(timeInSeconds * 1000);
    }

    public void stop() {
        setIsStopped();

        Player player = getPlayer();
        player.pause();
        player.seekToDefaultPosition();
    }

    public void setVolume(float volume) {
        getPlayer().setVolume(volume);
    }

    public void setRate(float rate) {
        getPlayer().setPlaybackSpeed(rate);
    }

    public void setOnReady(String callbackId) {
        onReadyCallbackId = callbackId;
    }

    public void setOnEnd(String callbackId) {
        onEndCallbackId = callbackId;
    }

    public void setOnPlaybackStatusChange(String callbackId) {
        onPlaybackStatusChangeCallbackId = callbackId;
    }

    public void setOnPlayNext(String callbackId) {
        onPlayNextCallbackId = callbackId;
    }

    public void setOnPlayPrevious(String callbackId) {
        onPlayPreviousCallbackId = callbackId;
    }

    public void setOnAudioStalled(String callbackId) {
        onAudioStalledCallbackId = callbackId;
    }

    public boolean isPlaying() {
        if (getPlayer() == null) {
            return false;
        }

        return isPlaying;
    }

    public boolean isPaused() {
        return !isPlaying && !isStopped;
    }

    public boolean isStopped() {
        return isStopped;
    }

    public void setIsPlaying() {
        this.isStopped = false;
        this.isPlaying = true;
    }

    public void setIsPaused() {
        this.isStopped = false;
        this.isPlaying = false;
    }

    public void setIsStopped() {
        this.isStopped = true;
        this.isPlaying = false;
    }

    public Player getPlayer() {
        return player;
    }

    public void setPlayer(Player player) {
        this.player = player;
    }

    public void releasePlayer() {
        if (player != null) {
            if (playerEventListener != null) {
                player.removeListener(playerEventListener);
            }
            player.release();
            player = null;
            playerEventListener = null;
        }
    }

    public void setEventListener(PlayerEventListener listener) {
        playerEventListener = listener;
    }

    public PlayerEventListener getEventListener() {
        return playerEventListener;
    }

    public boolean isInitialized() {
        return getPlayer() != null;
    }

    public MediaItem buildMediaItem() {
        return new MediaItem.Builder().setMediaMetadata(getMediaMetadata()).setUri(source).build();
    }

    private MediaMetadata getMediaMetadata() {
        MediaMetadata.Builder builder = new MediaMetadata.Builder()
            .setAlbumTitle(audioMetadata.albumTitle == null ? "" : audioMetadata.albumTitle)
            .setArtist(audioMetadata.artistName == null ? "" : audioMetadata.artistName)
            .setTitle(audioMetadata.songTitle == null ? "" : audioMetadata.songTitle);

        if (useForNotification && audioMetadata.artworkSource != null) {
            try {
                if (audioMetadata.artworkSource.startsWith("https:")) {
                    builder.setArtworkUri(Uri.parse(audioMetadata.artworkSource));
                } else {
                    int bufferLength = 4 * 0x400; // 4KB
                    byte[] buffer = new byte[bufferLength];
                    int readLength;
                    ByteArrayOutputStream outputStream = new ByteArrayOutputStream();

                    InputStream inputStream = pluginOwner
                        .getContext()
                        .getAssets()
                        .open("public/" + audioMetadata.artworkSource);

                    while ((readLength = inputStream.read(buffer, 0, bufferLength)) != -1) {
                        outputStream.write(buffer, 0, readLength);
                    }

                    inputStream.close();

                    builder.maybeSetArtworkData(
                        outputStream.toByteArray(),
                        MediaMetadata.PICTURE_TYPE_OTHER
                    );
                }
            } catch (Exception ex) {
                Log.w(TAG, "Could not load the artwork source.", ex);
            }
        }

        return builder.build();
    }
}