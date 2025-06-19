package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import android.os.Binder;
import android.util.Log;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import us.dkaliinin505.capacitorjs.plugins.nativeaudio.exceptions.AudioSourceAlreadyExistsException;

public class AudioSources extends Binder {

    private static final String TAG = "AudioSources";
    private HashMap<String, AudioSource> audioSources = new HashMap<>();

    public AudioSource get(String sourceId) {
        return audioSources.get(sourceId);
    }

    public void add(AudioSource source) throws AudioSourceAlreadyExistsException {
        if (exists(source)) {
            throw new AudioSourceAlreadyExistsException(source.id);
        }

        audioSources.put(source.id, source);
        Log.d(TAG, "Added audio source: " + source.id + ", total count: " + count());
    }

    public boolean remove(String sourceId) {
        if (!exists(sourceId)) {
            return false;
        }

        AudioSource removedSource = audioSources.remove(sourceId);
        if (removedSource != null) {
            // Clean up the audio source
            try {
                removedSource.releasePlayer();
            } catch (Exception e) {
                Log.w(TAG, "Error releasing player for source: " + sourceId, e);
            }
        }

        Log.d(TAG, "Removed audio source: " + sourceId + ", remaining count: " + count());
        return true;
    }

    public boolean exists(AudioSource source) {
        return exists(source.id);
    }

    public boolean exists(String sourceId) {
        return audioSources.containsKey(sourceId);
    }

    public boolean hasNotification() {
        return forNotification() != null;
    }

    public AudioSource forNotification() {
        for (AudioSource audioSource : audioSources.values()) {
            if (audioSource.useForNotification) {
                return audioSource;
            }
        }

        return null;
    }

    public int count() {
        return audioSources.size();
    }

    public void destroyAllNonNotificationSources() {
        List<AudioSource> sourcesToRemove = new ArrayList<>();

        for (AudioSource audioSource : audioSources.values()) {
            if (audioSource.useForNotification) {
                continue;
            }

            try {
                audioSource.releasePlayer();
            } catch (Exception e) {
                Log.w(TAG, "Error releasing player for source: " + audioSource.id, e);
            }

            sourcesToRemove.add(audioSource);
        }

        for (AudioSource sourceToRemove : sourcesToRemove) {
            audioSources.remove(sourceToRemove.id);
            Log.d(TAG, "Destroyed non-notification source: " + sourceToRemove.id);
        }

        Log.d(TAG, "Destroyed " + sourcesToRemove.size() + " non-notification sources");
    }

    public void destroyAllSources() {
        Log.d(TAG, "Destroying all " + count() + " audio sources");

        for (AudioSource audioSource : audioSources.values()) {
            try {
                audioSource.releasePlayer();
            } catch (Exception e) {
                Log.w(TAG, "Error releasing player for source: " + audioSource.id, e);
            }
        }

        audioSources.clear();
        Log.d(TAG, "All audio sources destroyed");
    }

    public List<AudioSource> getAllSources() {
        return new ArrayList<>(audioSources.values());
    }

    public boolean isEmpty() {
        return audioSources.isEmpty();
    }
}