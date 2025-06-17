import { WebPlugin } from '@capacitor/core';
import type { AudioPlayerDefaultParams, AudioPlayerListenerParams, AudioPlayerListenerResult, AudioPlayerPlugin, AudioPlayerPrepareParams } from './definitions';
export declare class AudioPlayerWeb extends WebPlugin implements AudioPlayerPlugin {
    onPlayNext(params: { audioId: string; }, callback: () => void): Promise<{ callbackId: string; }>;
    onPlayPrevious(params: { audioId: string; }, callback: () => void): Promise<{ callbackId: string; }>;
    onAudioStalled(params: AudioPlayerListenerParams, callback: (result: { reason: 'playback_stalled' | 'buffer_empty' | 'stall_resolved' | 'likely_to_keep_up'; currentTime: number; duration: number; networkAvailable: boolean; bufferEmpty?: boolean; likelyToKeepUp?: boolean; }) => void): Promise<AudioPlayerListenerResult>;
    create(params: AudioPlayerPrepareParams): Promise<{
        success: boolean;
    }>;
    initialize(params: AudioPlayerDefaultParams): Promise<{
        success: boolean;
    }>;
    changeAudioSource(params: AudioPlayerDefaultParams & {
        source: string;
    }): Promise<void>;
    changeMetadata(params: AudioPlayerDefaultParams & {
        friendlyTitle?: string;
        artworkSource?: string;
    }): Promise<void>;
    getDuration(params: AudioPlayerDefaultParams): Promise<{
        duration: number;
    }>;
    getCurrentTime(params: AudioPlayerDefaultParams): Promise<{
        currentTime: number;
    }>;
    play(params: AudioPlayerDefaultParams): Promise<void>;
    pause(params: AudioPlayerDefaultParams): Promise<void>;
    seek(params: AudioPlayerDefaultParams & {
        timeInSeconds: number;
    }): Promise<void>;
    stop(params: AudioPlayerDefaultParams): Promise<void>;
    setVolume(params: AudioPlayerDefaultParams & {
        volume: number;
    }): Promise<void>;
    setRate(params: AudioPlayerDefaultParams & {
        rate: number;
    }): Promise<void>;
    isPlaying(params: AudioPlayerDefaultParams): Promise<{
        isPlaying: boolean;
    }>;
    destroy(params: AudioPlayerDefaultParams): Promise<void>;
    onAppGainsFocus(params: AudioPlayerListenerParams, callback: () => void): Promise<AudioPlayerListenerResult>;
    onAppLosesFocus(params: AudioPlayerListenerParams, callback: () => void): Promise<AudioPlayerListenerResult>;
    onAudioReady(params: AudioPlayerListenerParams, callback: () => void): Promise<AudioPlayerListenerResult>;
    onAudioEnd(params: AudioPlayerListenerParams, callback: () => void): Promise<AudioPlayerListenerResult>;
    onPlaybackStatusChange(params: AudioPlayerListenerParams, callback: (result: {
        status: 'playing' | 'paused' | 'stopped';
    }) => void): Promise<AudioPlayerListenerResult>;
}
