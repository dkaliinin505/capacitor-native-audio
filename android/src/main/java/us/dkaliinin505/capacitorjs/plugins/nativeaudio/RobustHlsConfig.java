package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import android.content.Context;
import androidx.media3.common.C;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.common.MediaItem;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.exoplayer.DefaultLoadControl;

public class RobustHlsConfig {

    public static DefaultHttpDataSource.Factory createRobustHttpDataSourceFactory() {
        // Create HTTP data source with aggressive timeouts and retries
        return new DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(60000)      // 60 seconds connect timeout
            .setReadTimeoutMs(60000)         // 60 seconds read timeout
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent("YourMusicApp/1.0 (Android)")
            .setKeepPostFor302Redirects(true);
    }

    public static HlsMediaSource.Factory createRobustHlsFactory(Context context) {
        DefaultDataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(
            context,
            createRobustHttpDataSourceFactory()
        );

        return new HlsMediaSource.Factory(dataSourceFactory)
            .setAllowChunklessPreparation(true)
            .setUseSessionKeys(false);
    }

    public static LoadControl createRobustLoadControl() {
        return new DefaultLoadControl.Builder()
            // Increase buffer sizes significantly
            .setBufferDurationsMs(
                60000,   // Min buffer: 60 seconds
                300000,  // Max buffer: 5 minutes
                2500,    // Buffer for playback: 2.5 seconds
                5000     // Buffer for playback after rebuffer: 5 seconds
            )
            .setTargetBufferBytes(
                DefaultLoadControl.DEFAULT_TARGET_BUFFER_BYTES * 4  // 4x default buffer
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(
                60000,   // Keep 60 seconds of back buffer
                true     // Retain back buffer from keyframe
            )
            .build();
    }
}