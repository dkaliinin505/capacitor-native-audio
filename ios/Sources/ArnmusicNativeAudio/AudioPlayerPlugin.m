#import <Capacitor/Capacitor.h>

CAP_PLUGIN(AudioPlayerPlugin, "AudioPlayerPlugin",
    // Core methods
    CAP_PLUGIN_METHOD(create, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(createMultiple, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(changeAudioSource, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(changeMetadata, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(play, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(pause, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(stop, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(seek, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getCurrentTime, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getDuration, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(playNext, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(playPrevious, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(setVolume, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(setRate, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(isPlaying, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(destroy, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getCurrentAudio, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(setAudioSources, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(showAirPlayMenu, CAPPluginReturnPromise);

    // Focus Callbacks
    CAP_PLUGIN_METHOD(onAppGainsFocus, CAPPluginReturnCallback);
    CAP_PLUGIN_METHOD(onAppLosesFocus, CAPPluginReturnCallback);

    // Playback Callbacks
    CAP_PLUGIN_METHOD(onAudioReady, CAPPluginReturnCallback);
    CAP_PLUGIN_METHOD(onAudioEnd, CAPPluginReturnCallback);
    CAP_PLUGIN_METHOD(onPlaybackStatusChange, CAPPluginReturnCallback);
    CAP_PLUGIN_METHOD(onPlayNext, CAPPluginReturnCallback);
    CAP_PLUGIN_METHOD(onPlayPrevious, CAPPluginReturnCallback);
    CAP_PLUGIN_METHOD(onSeek, CAPPluginReturnCallback);

    // AirPlay Menu
    CAP_PLUGIN_METHOD(showAirPlayMenu, CAPPluginReturnPromise);
)