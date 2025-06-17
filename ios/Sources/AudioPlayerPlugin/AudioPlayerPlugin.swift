import AVFAudio
import MediaPlayer
import Capacitor
import Foundation

@objc(AudioPlayerPlugin)
public class AudioPlayerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AudioPlayerPlugin"
    public let jsName = "AudioPlayer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "create", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "changeAudioSource", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "changeMetadata", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDuration", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentTime", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seek", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVolume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isPlaying", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "onAppGainsFocus", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAppLosesFocus", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAudioReady", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAudioEnd", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onPlaybackStatusChange", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onPlayNext", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onPlayPrevious", returnType: CAPPluginReturnCallback),
        CAPPluginMethod(name: "onAudioStalled", returnType: CAPPluginReturnCallback)
    ]

    let audioSession = AVAudioSession.sharedInstance()
    var audioSources = AudioSources()
    var onGainsFocusCallbackIds: [String: String] = [:]
    var onLosesFocusCallbackIds: [String: String] = [:]
    // ADD THESE NEW CALLBACK DICTIONARIES
    var onPlayNextCallbackIds: [String: String] = [:]
    var onPlayPreviousCallbackIds: [String: String] = [:]
    var onAudioStalledCallbackIds: [String: String] = [:]

    // ADD REMOTE COMMAND CENTER REFERENCE
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()

    override public func load() {
            super.load()

           do {
             try audioSession.setActive(false)
             try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth])
             try audioSession.setActive(true)

           } catch {
               print("Failed to set audio session category")
           }

            print("Listening to app background/foreground event changes")

            let notificationCenter = NotificationCenter.default

            notificationCenter.addObserver(
                self,
                selector: #selector(handleAppToBackground),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )

            notificationCenter.addObserver(
                self,
                selector: #selector(handleAppToForeground),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )

            // ADD REMOTE COMMAND CENTER SETUP
            setupRemoteCommandCenter()
        }

        // ADD THIS NEW METHOD TO SETUP MEDIA CONTROLS
        private func setupRemoteCommandCenter() {
            // Enable play command
            remoteCommandCenter.playCommand.addTarget { [weak self] event in
                self?.handleRemotePlay()
                return .success
            }

            // Enable pause command
            remoteCommandCenter.pauseCommand.addTarget { [weak self] event in
                self?.handleRemotePause()
                return .success
            }

            // Enable next track command - THIS IS THE KEY PART
            remoteCommandCenter.nextTrackCommand.isEnabled = true
            remoteCommandCenter.nextTrackCommand.addTarget { [weak self] event in
                self?.handleRemoteNext()
                return .success
            }

            // Enable previous track command
            remoteCommandCenter.previousTrackCommand.isEnabled = false
            remoteCommandCenter.previousTrackCommand.addTarget { [weak self] event in
                self?.handleRemotePrevious()
                return .success
            }

            // Disable skip forward/backward to replace with next/previous
            remoteCommandCenter.skipForwardCommand.isEnabled = false
            remoteCommandCenter.skipBackwardCommand.isEnabled = false
    }

    // ADD REMOTE COMMAND HANDLERS
        private func handleRemotePlay() {
            print("Remote play command received")
            // Find the notification audio source and play it
            if let notificationSource = audioSources.forNotification() {
                notificationSource.play()
            }
        }

        private func handleRemotePause() {
            print("Remote pause command received")
            // Find the notification audio source and pause it
            if let notificationSource = audioSources.forNotification() {
                notificationSource.pause()
            }
        }

        private func handleRemoteNext() {
            print("Remote next track command received")
            // Trigger all registered next track callbacks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Trigger all registered next track callbacks
                    for callbackId in self.onPlayNextCallbackIds.values {
                        self.bridge?.savedCall(withID: callbackId)?.resolve()
                    }
            }
        }

        private func handleRemotePrevious() {
            print("Remote previous track command received")
            // Trigger all registered previous track callbacks
            for callbackId in onPlayPreviousCallbackIds.values {
                bridge?.savedCall(withID: callbackId)?.resolve()
            }
        }

    @objc func create(_ call: CAPPluginCall) {
        do {
            let sourceId = try audioId(call)

            if audioSources.exists(sourceId: sourceId) {
                print("Audio source with ID \(sourceId) already exists - attempting cleanup")

                            // Try to cleanup the existing source first
                            if let existingSource = audioSources.get(sourceId: sourceId) {
                                print("Cleaning up existing source:")

                                existingSource.stop()
                                existingSource.destroy()
                                audioSources.remove(sourceId: sourceId)

                                // Clean up callbacks
                                onLosesFocusCallbackIds.removeValue(forKey: sourceId)
                                onGainsFocusCallbackIds.removeValue(forKey: sourceId)
                                onPlayNextCallbackIds.removeValue(forKey: sourceId)
                                onPlayPreviousCallbackIds.removeValue(forKey: sourceId)

                                print("Existing source cleaned up successfully")
                            }
            }

            guard let source = call.getString("audioSource") else {
                throw AudioPlayerError.invalidPath
            }
            guard let friendlyTitle = call.getString("friendlyTitle") else {
                throw AudioPlayerError.invalidFriendlyName
            }

            let audioSource = AudioSource(
                pluginOwner: self,
                id: sourceId,
                source: source,
                audioMetadata: AudioMetadata(
                    albumTitle: call.getString("albumTitle", ""),
                    artistName: call.getString("artistName", ""),
                    songTitle: friendlyTitle,
                    artworkSource: call.getString("artworkSource", "")
                ),
                useForNotification: call.getBool("useForNotification", false),
                isBackgroundMusic: call.getBool("isBackgroundMusic", false),
                loopAudio: call.getBool("loop", false),
                showSeekBackward: call.getBool("showSeekBackward", true),
                showSeekForward: call.getBool("showSeekForward", true)
            )

            if audioSources.count() == 0 && !audioSource.useForNotification {
                throw AudioPlayerError.runtimeError(
                    "An audio source with useForNotification = true must exist first."
                )
            }

            if audioSources.hasNotification() && audioSource.useForNotification {
                throw AudioPlayerError.runtimeError(
                    "An audio source with useForNotification = true already exists. There can only be one."
                )
            }

            try audioSources.add(source: audioSource)

            call.resolve()
        } catch {
            call.reject(
                "There was an issue creating the audio player [1].",
                nil,
                error
            )
        }
    }

    @objc func initialize(_ call: CAPPluginCall) {
        do {
            try getAudioSource(methodName: "initialize", call: call)
                .initialize()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing the audio player.",
                nil,
                error
            )
        }
    }

    @objc func changeAudioSource(_ call: CAPPluginCall) {
        do {
            guard let newSource = call.getString("source") else {
                throw AudioPlayerError.invalidSource
            }

            try getAudioSource(methodName: "changeAudioSource", call: call)
                .changeAudioSource(newSource: newSource)

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue changing the audio source.",
                nil,
                error
            )
        }
    }

    @objc func changeMetadata(_ call: CAPPluginCall) {
        do {
            try getAudioSource(methodName: "changeMetadata", call: call)
                .changeMetadata(
                    metadata: AudioMetadata(
                        albumTitle: call.getString("albumTitle", ""),
                        artistName: call.getString("artistName", ""),
                        songTitle: call.getString("friendlyTitle", ""),
                        artworkSource: call.getString("artworkSource", "")
                    )
                )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue changing the metadata.",
                nil,
                error
            )
        }
    }

    @objc func getDuration(_ call: CAPPluginCall) {
        do {
            let duration = try getAudioSource(
                methodName: "duration",
                call: call
            ).getDuration()

            call.resolve(["duration": duration])
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the duration for the audio source.",
                nil,
                error
            )
        }
    }

    @objc func getCurrentTime(_ call: CAPPluginCall) {
        do {
            let currentTime = try getAudioSource(
                methodName: "currentTime",
                call: call
            ).getCurrentTime()

            call.resolve(["currentTime": currentTime])
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the current time for the audio source.",
                nil,
                error
            )
        }
    }

    @objc func play(_ call: CAPPluginCall) {
        do {
            let audioSource = try getAudioSource(methodName: "play", call: call)

            if audioSource.useForNotification {
                try audioSession.setActive(true)
            }

            audioSource.play()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue playing the audio.", nil, error)
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        do {
            try getAudioSource(methodName: "pause", call: call).pause()

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue pausing the audio.", nil, error)
        }
    }

    @objc func seek(_ call: CAPPluginCall) {
        do {
            guard let timeInSeconds = call.getInt("timeInSeconds") else {
                throw AudioPlayerError.invalidSeekTime
            }

            try getAudioSource(methodName: "seek", call: call).seek(
                timeInSeconds: Int64(timeInSeconds),
                fromUi: true
            )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue seeking the audio.", nil, error)
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        do {
            let audioSource = try getAudioSource(methodName: "stop", call: call)

            audioSource.stop()

            if audioSource.useForNotification {
                try audioSession.setActive(false)
            }

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject("There was an issue stopping the audio.", nil, error)
        }
    }

    @objc func setVolume(_ call: CAPPluginCall) {
        do {
            guard let volume = call.getFloat("volume") else {
                throw AudioPlayerError.invalidSeekTime
            }

            try getAudioSource(methodName: "setVolume", call: call).setVolume(
                volume: volume
            )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue setting the audio volume.",
                nil,
                error
            )
        }
    }

    @objc func setRate(_ call: CAPPluginCall) {
        do {
            guard let rate = call.getFloat("rate") else {
                throw AudioPlayerError.invalidRate
            }

            try getAudioSource(methodName: "setRate", call: call).setRate(
                rate: rate
            )

            call.resolve()
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue setting the rate of the audio.",
                nil,
                error
            )
        }
    }

    @objc func isPlaying(_ call: CAPPluginCall) {
        do {
            let isPlaying = try getAudioSource(
                methodName: "isPlaying",
                call: call
            ).isPlaying()

            call.resolve(["isPlaying": isPlaying])
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue getting the playing status of the audio.",
                nil,
                error
            )
        }
    }

     @objc func destroy(_ call: CAPPluginCall) {
            do {
                let audioSource = try getAudioSource(
                    methodName: "destroy",
                    call: call
                )

                if audioSource.useForNotification {
                    try audioSession.setActive(false)
                }

                audioSource.stop()
                audioSource.destroy()

                let audioId = try audioId(call)

                audioSources.remove(sourceId: audioId)
                onLosesFocusCallbackIds.removeValue(forKey: audioId)
                onGainsFocusCallbackIds.removeValue(forKey: audioId)

                // ADD CLEANUP FOR NEW CALLBACKS
                onPlayNextCallbackIds.removeValue(forKey: audioId)
                onPlayPreviousCallbackIds.removeValue(forKey: audioId)
                onAudioStalledCallbackIds.removeValue(forKey: audioId)

                // Disable remote commands if no more audio sources
                if audioSources.count() == 0 {
                    remoteCommandCenter.nextTrackCommand.isEnabled = false
                    remoteCommandCenter.previousTrackCommand.isEnabled = false
                }

                call.resolve()
            } catch AudioPlayerError.missingAudioSource {
                return
            } catch {
                call.reject(
                    "There was an issue cleaning up the audio player.",
                    nil,
                    error
                )
            }
        }

    @objc func onAppGainsFocus(_ call: CAPPluginCall) {
        do {
            call.keepAlive = true
            bridge?.saveCall(call)

            onGainsFocusCallbackIds[try audioId(call)] = call.callbackId
        } catch {
            call.reject(
                "There was an issue registering onAppGainsFocus",
                nil,
                error
            )
        }
    }

    @objc func onAppLosesFocus(_ call: CAPPluginCall) {
        do {
            call.keepAlive = true
            bridge?.saveCall(call)

            onLosesFocusCallbackIds[try audioId(call)] = call.callbackId
        } catch {
            call.reject(
                "There was an issue registering onAppLosesFocus",
                nil,
                error
            )
        }
    }

    @objc func onAudioReady(_ call: CAPPluginCall) {
        call.keepAlive = true
        bridge?.saveCall(call)

        do {
            try getAudioSource(methodName: "onAudioReady", call: call)
                .setOnReady(callbackId: call.callbackId)
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing audio ready.",
                nil,
                error
            )
        }
    }

    @objc func onAudioEnd(_ call: CAPPluginCall) {
        print("Calling onAudioEnd");
        call.keepAlive = true
        bridge?.saveCall(call)

        print("onAudioEnd callback ID: \(call.callbackId)")
        do {
            try getAudioSource(methodName: "onAudioEnd", call: call).setOnEnd(
                callbackId: call.callbackId
            )
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing audio end.",
                nil,
                error
            )
        }

    }

    @objc func onPlaybackStatusChange(_ call: CAPPluginCall) {
        call.keepAlive = true
        bridge?.saveCall(call)

        do {
            try getAudioSource(methodName: "onPlaybackStatusChange", call: call)
                .setOnPlaybackStatusChange(callbackId: call.callbackId)
        } catch AudioPlayerError.missingAudioSource {
            return
        } catch {
            call.reject(
                "There was an issue initializing playback status change.",
                nil,
                error
            )
        }
    }

    @objc func handleAppToBackground() {
        print("Going to background")

        makeFocusChangeCallbackCalls(callbackIds: onLosesFocusCallbackIds)
    }

    @objc func handleAppToForeground() {
        print("Coming to foreground")

        makeFocusChangeCallbackCalls(callbackIds: onGainsFocusCallbackIds)
    }

    func audioId(_ call: CAPPluginCall) throws -> String {
        guard let audioId = call.getString("audioId") else {
            throw AudioPlayerError.invalidAudioId
        }

        return audioId
    }

    func getAudioSource(methodName: String, call: CAPPluginCall) throws
    -> AudioSource {
        return try getAudioSource(
            methodName: methodName,
            call: call,
            rejectIfError: true
        )
    }

    func getAudioSource(
        methodName: String,
        call: CAPPluginCall,
        rejectIfError: Bool
    ) throws -> AudioSource {
        let audioSource = audioSources.get(sourceId: try audioId(call))

        if audioSource == nil {
            print("Audio source with ID \(try audioId(call)) was not found.")

            if rejectIfError {
                call.reject(
                    "There was an issue trying to play the audio (\(methodName))"
                )
            }

            throw AudioPlayerError.missingAudioSource
        }

        return audioSource!
    }

    func makeFocusChangeCallbackCalls(callbackIds: [String: String]) {
        for callbackId in callbackIds.values {
            bridge?.savedCall(withID: callbackId)?.resolve()
        }
    }

   // ADD THESE NEW CALLBACK REGISTRATION METHODS
       @objc func onPlayNext(_ call: CAPPluginCall) {
           do {
               call.keepAlive = true
               bridge?.saveCall(call)

               let audioId = try audioId(call)
               onPlayNextCallbackIds[audioId] = call.callbackId

               // Enable the next track command when callback is registered
               remoteCommandCenter.nextTrackCommand.isEnabled = true

               print("Registered onPlayNext callback for audio ID: \(audioId)")
           } catch {
               call.reject(
                   "There was an issue registering onPlayNext",
                   nil,
                   error
               )
           }
       }

       @objc func onPlayPrevious(_ call: CAPPluginCall) {
           do {
               call.keepAlive = true
               bridge?.saveCall(call)

               let audioId = try audioId(call)
               onPlayPreviousCallbackIds[audioId] = call.callbackId

               print("Registered onPlayPrevious callback for audio ID: \(audioId)")
           } catch {
               call.reject(
                   "There was an issue registering onPlayPrevious",
                   nil,
                   error
               )
           }
       }

       // Add this method to register the stall callback
       @objc func onAudioStalled(_ call: CAPPluginCall) {
           do {
               call.keepAlive = true
               bridge?.saveCall(call)

               let audioId = try audioId(call)
               onAudioStalledCallbackIds[audioId] = call.callbackId

               // Set the callback on the audio source
               try getAudioSource(methodName: "onAudioStalled", call: call)
                   .setOnStalled(callbackId: call.callbackId)

               print("Registered onAudioStalled callback for audio ID: \(audioId)")
           } catch AudioPlayerError.missingAudioSource {
               return
           } catch {
               call.reject(
                   "There was an issue registering onAudioStalled",
                   nil,
                   error
               )
           }
       }
}
