package us.dkaliinin505.capacitorjs.plugins.nativeaudio;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.util.Log;

public class WiFiLockManager {
    private static final String TAG = "WiFiLockManager";
    private WifiManager.WifiLock wifiLock;
    private WifiManager wifiManager;

    public WiFiLockManager(Context context) {
        wifiManager = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager != null) {
            wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "AudioPlayer:WiFiLock"
            );
        }
    }

    public void acquireLock() {
        if (wifiLock != null && !wifiLock.isHeld()) {
            wifiLock.acquire();
            Log.d(TAG, "WiFi lock acquired for high performance");
        }
    }

    public void releaseLock() {
        if (wifiLock != null && wifiLock.isHeld()) {
            wifiLock.release();
            Log.d(TAG, "WiFi lock released");
        }
    }

    public boolean isLockHeld() {
        return wifiLock != null && wifiLock.isHeld();
    }
}