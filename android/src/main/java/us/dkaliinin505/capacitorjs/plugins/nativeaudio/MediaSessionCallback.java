package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.session.MediaSession;
import androidx.media3.session.SessionCommand;
import androidx.media3.session.SessionCommands;
import androidx.media3.session.SessionResult;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;

public class MediaSessionCallback implements MediaSession.Callback {

    private static final String TAG = "MediaSessionCallback";

    public static final String SET_AUDIO_SOURCES = "SetAudioSources";
    public static final String CREATE_PLAYER = "CreatePlayer";

    private AudioPlayerService audioService;

    public MediaSessionCallback(AudioPlayerService audioService) {
        this.audioService = audioService;
    }

    @OptIn(markerClass = UnstableApi.class)
    @Override
    public MediaSession.ConnectionResult onConnect(
        MediaSession session,
        MediaSession.ControllerInfo controller
    ) {
        SessionCommands sessionCommands =
            MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
                .add(new SessionCommand(SET_AUDIO_SOURCES, new Bundle()))
                .add(new SessionCommand(CREATE_PLAYER, new Bundle()))
                .build();

        return new MediaSession.ConnectionResult.AcceptedResultBuilder(session)
            .setAvailableSessionCommands(sessionCommands)
            .build();
    }

    @Override
    public ListenableFuture<SessionResult> onCustomCommand(
        MediaSession session,
        MediaSession.ControllerInfo controller,
        SessionCommand customCommand,
        Bundle args
    ) {
        try {
            if (customCommand.customAction.equals(SET_AUDIO_SOURCES)) {
                Bundle audioSourcesBundle = new Bundle();
                audioSourcesBundle.putBinder(
                    "audioSources",
                    customCommand.customExtras.getBinder("audioSources")
                );

                session.setSessionExtras(audioSourcesBundle);
                Log.d(TAG, "Audio sources set in session extras");

            } else if (customCommand.customAction.equals(CREATE_PLAYER)) {
                AudioSource source = (AudioSource) customCommand.customExtras.getBinder("audioSource");
                if (source != null) {
                    source.initialize(audioService);
                    Log.d(TAG, "Player created for audio source: " + source.id);
                }
            }
        } catch (Exception ex) {
            Log.e(TAG, "Error handling custom command: " + customCommand.customAction, ex);
            return Futures.immediateFuture(new SessionResult(SessionResult.RESULT_ERROR_UNKNOWN));
        }

        return Futures.immediateFuture(new SessionResult(SessionResult.RESULT_SUCCESS));
    }

    @Override
    public ListenableFuture<SessionResult> onPlayerCommandRequest(
        @NonNull MediaSession session,
        @NonNull MediaSession.ControllerInfo controller,
        @Player.Command int playerCommand
    ) {
        try {
            switch (playerCommand) {
                case Player.COMMAND_SEEK_TO_NEXT:
                case Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM:
                    handlePlayNext(session);
                    break;

                case Player.COMMAND_SEEK_TO_PREVIOUS:
                case Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM:
                    handlePlayPrevious(session);
                    break;

                default:
                    break;
            }
        } catch (Exception ex) {
            Log.e(TAG, "Error handling player command: " + playerCommand, ex);
        }

        return MediaSession.Callback.super.onPlayerCommandRequest(session, controller, playerCommand);
    }

    @OptIn(markerClass = UnstableApi.class)
    private void handlePlayNext(MediaSession session) {
        try {
            IBinder audioSourcesBinder = session.getSessionExtras().getBinder("audioSources");
            if (audioSourcesBinder != null) {
                AudioSources audioSources = (AudioSources) audioSourcesBinder;
                AudioSource notificationSource = audioSources.forNotification();

                if (notificationSource != null && notificationSource.onPlayNextCallbackId != null) {
                    notificationSource.pluginOwner.handlePlayNextCallback(notificationSource.onPlayNextCallbackId);
                    Log.d(TAG, "Play next callback triggered");
                }
            }
        } catch (Exception ex) {
            Log.e(TAG, "Error triggering play next callback", ex);
        }
    }

    @OptIn(markerClass = UnstableApi.class)
    private void handlePlayPrevious(MediaSession session) {
        try {
            IBinder audioSourcesBinder = session.getSessionExtras().getBinder("audioSources");
            if (audioSourcesBinder != null) {
                AudioSources audioSources = (AudioSources) audioSourcesBinder;
                AudioSource notificationSource = audioSources.forNotification();

                if (notificationSource != null && notificationSource.onPlayPreviousCallbackId != null) {
                    notificationSource.pluginOwner.handlePlayPreviousCallback(notificationSource.onPlayPreviousCallbackId);
                    Log.d(TAG, "Play previous callback triggered");
                }
            }
        } catch (Exception ex) {
            Log.e(TAG, "Error triggering play previous callback", ex);
        }
    }
}