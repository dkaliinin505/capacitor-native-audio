import AVFoundation
import Capacitor
import MediaPlayer
import Network

public class AudioSource: NSObject, AVAudioPlayerDelegate {
    let STANDARD_SEEK_IN_SECONDS: Int = 5

    var id: String
    var source: String
    var audioMetadata: AudioMetadata
    var useForNotification: Bool
    var isBackgroundMusic: Bool

    var onPlaybackStatusChangeCallbackId: String = ""
    var onReadyCallbackId: String = ""
    var onEndCallbackId: String = ""

    private var pluginOwner: AudioPlayerPlugin
    @objc private var playerItem: AVPlayerItem!
    private var player: AVPlayer!
    @objc private var playerQueue: AVQueuePlayer!
    private var playerLooper: AVPlayerLooper!
    private var nowPlayingArtwork: MPMediaItemArtwork?

    private var loopAudio: Bool
    private var isPaused: Bool = false
    private var showSeekBackward: Bool
    private var showSeekForward: Bool

    private var audioReadyObservation: NSKeyValueObservation?
    private var audioOnEndObservation: Any?
    // Observations for duration changes
    private var durationObservation: NSKeyValueObservation?
    private var periodicTimeObserver: Any?
    // NEW: Add periodic end check observer reference
    private var periodicEndCheckObserver: Any?

    // NEW: Network monitoring variables ( for auto resume)
    private var networkMonitor: NWPathMonitor?
    private var networkQueue: DispatchQueue?
    private var wasPlayingBeforeNetworkLoss: Bool = false
    private var shouldAutoResume: Bool = false

    var onStalledCallbackId: String = ""

    // Add this property to track stall state
    private var isCurrentlyStalled: Bool = false
    private var stallCheckTimer: Timer?
    // Track network availability
    private var isNetworkAvailable: Bool = true
    private var hasTriggeredNetworkLoss: Bool = false

    public init(
        pluginOwner: AudioPlayerPlugin,
        id: String,
        source: String,
        audioMetadata: AudioMetadata,
        useForNotification: Bool,
        isBackgroundMusic: Bool,
        loopAudio: Bool,
        showSeekBackward: Bool,
        showSeekForward: Bool
    ) {
        self.pluginOwner = pluginOwner
        self.id = id
        self.source = source
        self.audioMetadata = audioMetadata
        self.useForNotification = useForNotification
        self.isBackgroundMusic = isBackgroundMusic
        self.loopAudio = loopAudio
        self.showSeekBackward = showSeekBackward
        self.showSeekForward = showSeekForward

        super.init()

        print("=== AUDIO SOURCE CREATED ===")
        print("ID: \(id)")
        print("Source: \(source)")
        print("Title: \(audioMetadata.songTitle)")
        print("Use for notification: \(useForNotification)")
        print("Loop audio: \(loopAudio)")
        print("===========================")
    }

    func initialize() throws {
        print("=== INITIALIZING AUDIO SOURCE ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")

        isPaused = false
        playerItem = try createPlayerItem()

        if loopAudio {
            print("Setting up looped audio playback")
            playerQueue = AVQueuePlayer()
            playerLooper = AVPlayerLooper.init(
                player: playerQueue,
                templateItem: playerItem
            )
            observeAudioReady()
        } else {
            print("Setting up standard audio playback")
            observeAudioReady()
            player = AVPlayer.init(playerItem: playerItem)

            // Observe duration changes for HLS streams
            observeDurationChanges()

            setupInterruptionNotifications()
        }

        setupNetworkMonitoring()

        print("Audio source initialized successfully")
        print("=================================")
    }

    func changeAudioSource(newSource: String) throws {
        print("=== CHANGING AUDIO SOURCE ===")
        print("Audio ID: \(id)")
        print("Old source: \(source)")
        print("New source: \(newSource)")

        audioReadyObservation?.invalidate()
        audioReadyObservation = nil

        removeOnEndObservation()

        source = newSource
        playerItem = try createPlayerItem()

        if loopAudio {
            playerQueue.removeAllItems()
            playerLooper = AVPlayerLooper.init(
                player: playerQueue,
                templateItem: playerItem
            )
            observeAudioReady()
        } else {
            observeAudioReady()
            player.replaceCurrentItem(with: playerItem)
        }

        print("Audio source changed successfully")
        print("=============================")
    }

    private func setupNetworkMonitoring() {
        print("Setting up network monitoring for audio ID: \(id)")

        networkMonitor = NWPathMonitor()
        networkQueue = DispatchQueue(label: "NetworkMonitor_\(id)")

        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let isNowAvailable = path.status == .satisfied

            DispatchQueue.main.async {
                // Only trigger callbacks if network state actually changed
                if self.isNetworkAvailable != isNowAvailable {
                    self.isNetworkAvailable = isNowAvailable

                    if isNowAvailable {
                        print("Network is available for audio ID: \(self.id)")
                        self.handleNetworkRestored()
                    } else {
                        print("Network is unavailable for audio ID: \(self.id)")
                        self.handleNetworkLost()
                    }
                }
            }
        }

        networkMonitor?.start(queue: networkQueue!)
    }

    func setOnStalled(callbackId: String) {
        print("Setting onStalled callback: \(callbackId) for audio ID: \(id)")
        onStalledCallbackId = callbackId
    }

    // Handle when network is lost
    private func handleNetworkLost() {
        print("=== NETWORK LOST ===")
        print("Audio ID: \(id)")
        print("Was playing: \(isPlaying())")

        // Remember if we were playing before network loss
        wasPlayingBeforeNetworkLoss = isPlaying()
        shouldAutoResume = wasPlayingBeforeNetworkLoss
        hasTriggeredNetworkLoss = true

        print("==================")
    }

   // Handle when network is restored
   private func handleNetworkRestored() {
       print("=== NETWORK RESTORED ===")
       print("Audio ID: \(id)")
       print("Should auto resume: \(shouldAutoResume)")
       print("Was playing before loss: \(wasPlayingBeforeNetworkLoss)")
       print("Current playing state: \(isPlaying())")
       print("Has triggered network loss: \(hasTriggeredNetworkLoss)")

       // Only proceed if we actually had a network loss event
       guard hasTriggeredNetworkLoss else {
           print("No network loss event recorded - skipping restoration")
           return
       }

       // Reset the network loss flag
       hasTriggeredNetworkLoss = false

       // If we were stalled and should auto-resume
       if shouldAutoResume && isCurrentlyStalled {
           print("Auto-resuming playback after network restoration")

           // Add a small delay to ensure network is stable
           DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
               guard let self = self else { return }

               // Double-check we still should resume
               if self.shouldAutoResume {
                   print("Executing auto-resume for audio ID: \(self.id)")

                   // Reset stall state first
                   self.isCurrentlyStalled = false

                   // Force play to resume
                   if self.loopAudio {
                       self.playerQueue.play()
                   } else {
                       self.player.play()
                   }

                   // Trigger stall resolution callback
                   self.makePluginCall(
                       callbackId: self.onStalledCallbackId,
                       data: [
                           "reason": "stall_resolved",
                           "currentTime": self.getCurrentTime(),
                           "duration": self.getDuration(),
                           "networkAvailable": true
                       ]
                   )

                   // Notify about status change
                   self.makePluginCall(
                       callbackId: self.onPlaybackStatusChangeCallbackId,
                       data: ["status": "playing", "reason": "network_restored"]
                   )

                   // Reset auto-resume flags
                   self.shouldAutoResume = false
                   self.wasPlayingBeforeNetworkLoss = false
               }
           }
       } else if isCurrentlyStalled {
           // Even if not auto-resuming, resolve the stall state
           print("Resolving stall state after network restoration")

           isCurrentlyStalled = false

           makePluginCall(
               callbackId: onStalledCallbackId,
               data: [
                   "reason": "stall_resolved",
                   "currentTime": getCurrentTime(),
                   "duration": getDuration(),
                   "networkAvailable": true
               ]
           )
       }

       print("====================")
   }

    func changeMetadata(metadata: AudioMetadata) {
        print("=== CHANGING METADATA ===")
        print("Audio ID: \(id)")
        print("Old title: \(audioMetadata.songTitle)")
        print("New title: \(metadata.songTitle)")

        audioMetadata = metadata
        nowPlayingArtwork = nil

        removeNowPlaying()
        setupNowPlaying()

        print("Metadata changed successfully")
        print("===========================")
    }

    func getDuration() -> TimeInterval {
        if loopAudio {
            return -1
        }

        guard let duration = player.currentItem?.duration else {
            print("getDuration() - No duration available, returning -1")
            return -1
        }

        if duration == CMTime.indefinite {
            print("getDuration() - Indefinite duration, returning -1")
            return -1
        }

        if !duration.isValid || duration.isIndefinite {
            print("getDuration() - Invalid duration, returning -1")
            return -1
        }

        let durationSeconds = duration.seconds

        return durationSeconds.isFinite ? durationSeconds : -1
    }

    func getCurrentTime() -> TimeInterval {
        if loopAudio {
            print("getCurrentTime() - Loop audio, returning -1")
            return -1
        }

        let currentTime = player.currentTime().seconds

        return currentTime
    }

    func play() {
        print("=== STARTING PLAYBACK ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Current time: \(getCurrentTime())")
        print("Duration: \(getDuration())")
        print("Was paused: \(isPaused)")

        shouldAutoResume = false
        wasPlayingBeforeNetworkLoss = false

        if loopAudio {
            playerQueue.play()
        } else {
            player.play()
        }

        if !isPaused {
            setupNowPlaying()
            setupRemoteTransportControls()
        } else {
            setNowPlayingCurrentTime()
        }

        isPaused = false
        setNowPlayingPlaybackState(state: .playing)

        print("Playback started successfully")
        print("========================")
    }

    func pause() {
        print("=== PAUSING PLAYBACK ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Current time: \(getCurrentTime())")

        // If paused manually, don't auto-resume
        shouldAutoResume = false
        wasPlayingBeforeNetworkLoss = false

        if loopAudio {
            playerQueue.pause()
        } else {
            player.pause()
        }

        isPaused = true
        setNowPlayingPlaybackState(state: .paused)

        print("Playback paused successfully")
        print("==========================")
    }

    func seek(timeInSeconds: Int64, fromUi: Bool = false) {
//         print("=== SEEKING ===")
//         print("Audio ID: \(id)")
//         print("Seek to: \(timeInSeconds) seconds")
//         print("From UI: \(fromUi)")
//
//         if loopAudio {
//             return
//         }
//
//         player.seek(to: getCmTime(seconds: timeInSeconds))
//
//         if fromUi {
//             removeRemoteTransportControls()
//             removeNowPlaying()
//
//             setupNowPlaying()
//             setupRemoteTransportControls()
//         } else {
//             setNowPlayingCurrentTime()
//         }
//
//         print("Seek completed")
//         print("=============")
           return
    }

    func stop() {
        print("=== STOPPING PLAYBACK ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Current time before stop: \(getCurrentTime())")
        print("Duration: \(getDuration())")
        print("Was playing: \(isPlaying())")

        shouldAutoResume = false
        wasPlayingBeforeNetworkLoss = false

        if loopAudio {
            playerQueue.pause()
            playerQueue.seek(to: getCmTime(seconds: 0))
        } else {
            player.pause()
            player.seek(to: getCmTime(seconds: 0))
        }

        isPaused = false
        setNowPlayingPlaybackState(state: .stopped)
        removeRemoteTransportControls()
        removeNowPlaying()

        print("Playback stopped successfully")
        print("========================")
    }

    func setVolume(volume: Float) {
        print("Setting volume to: \(volume) for audio ID: \(id)")

        if loopAudio {
            playerQueue.volume = volume
        } else {
            player.volume = volume
        }
    }

    func setRate(rate: Float) {
        print("Setting rate to: \(rate) for audio ID: \(id)")

        if loopAudio {
            return
        }

        player.rate = rate
    }

    func setOnReady(callbackId: String) {
        print("Setting onReady callback: \(callbackId) for audio ID: \(id)")
        onReadyCallbackId = callbackId
    }

    func setOnEnd(callbackId: String) {
        print("=== SETTING ON END CALLBACK ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Callback ID: \(callbackId)")

        onEndCallbackId = callbackId

        print("onEnd callback registered successfully")
        print("===============================")
    }

    func setOnPlaybackStatusChange(callbackId: String) {
        print("Setting onPlaybackStatusChange callback: \(callbackId) for audio ID: \(id)")
        onPlaybackStatusChangeCallbackId = callbackId
    }

     // This checks the actual AVPlayer state (for internal logic)
     private func isPlayerActuallyPlaying() -> Bool {
         if loopAudio {
             return playerQueue.rate > 0
                 || playerQueue.timeControlStatus == AVPlayer.TimeControlStatus.playing
                 || playerQueue.timeControlStatus == AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate
         }

         return player.rate > 0
             || player.timeControlStatus == AVPlayer.TimeControlStatus.playing
             || player.timeControlStatus == AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate
     }

     // This is the public method that considers stall state
     func isPlaying() -> Bool {
         if isCurrentlyStalled {
             return false
         }
         return isPlayerActuallyPlaying()
     }

    // Update the destroy method to clean up stall monitoring
    func destroy() {
        print("=== DESTROYING AUDIO SOURCE ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")

        // Stop stall monitoring
        stallCheckTimer?.invalidate()
        stallCheckTimer = nil
        isCurrentlyStalled = false

        removeOnEndObservation()

        // Clean up duration observers
        durationObservation?.invalidate()
        durationObservation = nil

        if let observer = periodicTimeObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            periodicTimeObserver = nil
        }

        // Clean up periodic end check observer
        if let observer = periodicEndCheckObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            periodicEndCheckObserver = nil
        }

        // Remove all notification observers for this instance
        NotificationCenter.default.removeObserver(self)

        isPaused = false
        removeRemoteTransportControls()
        removeNowPlaying()
        removeInterruptionNotifications()

        networkMonitor?.cancel()
        networkMonitor = nil
        networkQueue = nil

        print("Audio source destroyed successfully")
        print("===============================")
    }

    private func createPlayerItem() throws -> AVPlayerItem {
        let url = URL.init(string: source)

        if url == nil {
            throw AudioPlayerError.invalidPath
        }

        let player = AVPlayerItem.init(url: url.unsafelyUnwrapped)

        return player
    }

    private func setupInterruptionNotifications() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // ADD STALL DETECTION OBSERVERS
        if let currentPlayer = player, let currentItem = currentPlayer.currentItem {
            // Observe playback stalled
            notificationCenter.addObserver(
                self,
                selector: #selector(playerItemPlaybackStalled(_:)),
                name: .AVPlayerItemPlaybackStalled,
                object: currentItem
            )

            // Observe when playback likely to keep up changes
            notificationCenter.addObserver(
                self,
                selector: #selector(playerItemLikelyToKeepUp(_:)),
                name: .AVPlayerItemNewAccessLogEntry,
                object: currentItem
            )
        }

        // Start monitoring playback status
        startStallMonitoring()
    }



    private func removeInterruptionNotifications() {
        print("Removing interruption notifications for audio ID: \(id)")

        let notificationCenter = NotificationCenter.default

        notificationCenter.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        print("=== AUDIO INTERRUPTION ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")

        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey]
                as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            print("Could not parse interruption type")
            return
        }

        if type == .began {
            print("Audio interruption has begun")
            pause()

            makePluginCall(
                callbackId: onPlaybackStatusChangeCallbackId,
                data: [
                    "status": "paused"
                ]
            )
        }

        if type == .ended {
            print("Audio interruption has ended")
            play()

            makePluginCall(
                callbackId: onPlaybackStatusChangeCallbackId,
                data: [
                    "status": "playing"
                ]
            )
        }
        print("=========================")
    }

    private func observeAudioReady() {
        print("Setting up audio ready observation for audio ID: \(id)")

        if onReadyCallbackId == "" {
            print("No ready callback ID - skipping ready observation")
            return
        }

        if loopAudio {
            audioReadyObservation = observe(
                \.playerQueue?.currentItem?.status
            ) { _, _ in
                if self.playerQueue.currentItem?.status
                    == AVPlayerItem.Status.readyToPlay {
                    print("Loop audio ready - triggering callback")
                    self.makePluginCall(callbackId: self.onReadyCallbackId)
                    self.observeOnEnd()
                }
            }
        } else {
            audioReadyObservation = observe(
                \.playerItem?.status
            ) { _, _ in
                if self.playerItem.status == AVPlayerItem.Status.readyToPlay {
                    print("Standard audio ready - triggering callback")
                    self.makePluginCall(callbackId: self.onReadyCallbackId)
                    self.observeOnEnd()
                }
            }
        }
    }

    // ENHANCED END DETECTION WITH MULTIPLE STRATEGIES
    private func observeOnEnd() {
        print("=== SETTING UP AUDIO END OBSERVATION ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("onEndCallbackId: \(onEndCallbackId)")

        if onEndCallbackId == "" {
            print("No end callback ID provided - skipping end observation")
            return
        }

        if loopAudio {
            print("Loop audio enabled - skipping end observation")
            return
        }

        guard let currentItem = player.currentItem else {
            print("ERROR: No current item available for end observation")
            return
        }

        let duration = currentItem.duration
        print("Item duration: \(duration)")
        print("Duration valid: \(duration.isValid)")
        print("Duration indefinite: \(duration == CMTime.indefinite)")
        print("Duration seconds: \(duration.seconds)")

        if duration == CMTime.indefinite {
            print("Indefinite duration - setting up status-based end detection only")
            setupStatusBasedEndDetection()
            return
        }

        if !duration.isValid || duration.seconds <= 0 {
            print("Invalid duration - setting up status-based end detection only")
            setupStatusBasedEndDetection()
            return
        }

        // Primary method: Boundary time observer
        setupBoundaryTimeEndDetection(duration: duration)

        // Backup method: Status-based detection
        setupStatusBasedEndDetection()

        // For now, comment out periodic checking to avoid crashes
        // setupPeriodicEndDetection(duration: duration)

        print("========================================")
    }

    // Primary end detection method using boundary time observer
    private func setupBoundaryTimeEndDetection(duration: CMTime) {
        print("Setting up boundary time end detection for duration: \(duration.seconds)")

        // Add safety check for player availability
        guard let currentPlayer = player else {
            print("WARNING: Player not available for boundary time detection")
            return
        }

        // Remove existing observation first
        removeOnEndObservation()

        var times = [NSValue]()
        times.append(NSValue(time: duration))

        audioOnEndObservation = currentPlayer.addBoundaryTimeObserver(
            forTimes: times,
            queue: .main
        ) { [weak self] in
            guard let self = self else { return }

            print("=== BOUNDARY TIME OBSERVER TRIGGERED ===")
            print("Audio ID: \(self.id)")
            print("Track: \(self.audioMetadata.songTitle)")
            print("Current time: \(self.getCurrentTime())")
            print("Duration: \(self.getDuration())")
            print("Is playing: \(self.isPlaying())")
            print("App state: \(UIApplication.shared.applicationState.rawValue)")

            self.handleTrackEnd(source: "boundary_time_observer")
            print("========================================")
        }

        print("Boundary time observer set up successfully")
    }

    // Backup end detection using player item status observation
    private func setupStatusBasedEndDetection() {
        print("Setting up status-based end detection")

        // Add safety check for player availability
        guard let currentPlayer = player, let currentItem = currentPlayer.currentItem else {
            print("WARNING: Player or current item not available for status-based detection")
            return
        }

        // Observe when player item reaches end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: currentItem
        )

        // Also observe playback stalled (for network issues)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled(_:)),
            name: .AVPlayerItemPlaybackStalled,
            object: currentItem
        )

        print("Status-based observers registered")
    }

    // Additional periodic checking for end detection (SAFER VERSION)
    private func setupPeriodicEndDetection(duration: CMTime) {
        // Add safety check for player availability
        guard let currentPlayer = player else {
            print("WARNING: Player not available for periodic end detection")
            return
        }

        // Remove any existing periodic end check observer first
        if let existingObserver = periodicEndCheckObserver {
            currentPlayer.removeTimeObserver(existingObserver)
            periodicEndCheckObserver = nil
        }

        let checkInterval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        periodicEndCheckObserver = currentPlayer.addPeriodicTimeObserver(
            forInterval: checkInterval,
            queue: .main
        ) { [weak self] currentTime in
            guard let self = self else {
                print("Self deallocated during periodic check")
                return
            }

            // Additional safety check
            guard let strongPlayer = self.player else {
                print("Player deallocated during periodic check")
                return
            }

            let currentSeconds = currentTime.seconds
            let durationSeconds = duration.seconds

            // Check if we're within 2 seconds of the end (more conservative)
            if durationSeconds > 0 && currentSeconds >= (durationSeconds - 2.0) {
                print("=== PERIODIC END DETECTION TRIGGERED ===")
                print("Current: \(currentSeconds), Duration: \(durationSeconds)")
                print("Difference: \(durationSeconds - currentSeconds)")

                // Remove this observer to prevent multiple triggers
                if let observer = self.periodicEndCheckObserver {
                    strongPlayer.removeTimeObserver(observer)
                    self.periodicEndCheckObserver = nil
                }

                self.handleTrackEnd(source: "periodic_check")
                print("========================================")
            }
        }

        print("Periodic end detection set up successfully")
    }

    // Notification-based end detection methods
    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        print("=== PLAYER ITEM DID REACH END NOTIFICATION ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Current time: \(getCurrentTime())")
        print("Duration: \(getDuration())")
        print("Is playing: \(isPlaying())")
        print("App state: \(UIApplication.shared.applicationState.rawValue)")
        print("Notification object: \(notification.object)")

        handleTrackEnd(source: "did_reach_end_notification")
        print("===============================================")
    }

    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        print("=== PLAYER ITEM PLAYBACK STALLED ===")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Current time: \(getCurrentTime())")
        print("Duration: \(getDuration())")
        print("Is player playing: \(isPlayerActuallyPlaying())")
        print("Network available: \(isNetworkAvailable)")

        let currentTime = getCurrentTime()
        let duration = getDuration()

        // Determine if this is a real stall or end-of-track
        let isNearEnd = duration > 0 && currentTime >= (duration - 5.0)

        if !isNearEnd {
            // This is a genuine stall
            isCurrentlyStalled = true

            // Update command center to show stalled state immediately
            if useForNotification {
                setNowPlayingInfoKey(
                    for: MPNowPlayingInfoPropertyPlaybackRate,
                    value: 0.0
                )
            }

            // Trigger the stall callback
            makePluginCall(
                callbackId: onStalledCallbackId,
                data: [
                    "reason": "playback_stalled",
                    "currentTime": currentTime,
                    "duration": duration,
                    "networkAvailable": isNetworkAvailable
                ]
            )

            // Check if it's a network issue and we should prepare for auto-resume
            if isPlayerActuallyPlaying() && !isNetworkAvailable {
                wasPlayingBeforeNetworkLoss = true
                shouldAutoResume = true
                print("Marking for potential auto-resume due to network stall")
            }
        } else {
            // Near the end, treat as normal end
            print("Stalled near end - treating as track end")
            handleTrackEnd(source: "playback_stalled_near_end")
        }

        print("====================================")
    }

    // Method to monitor for stalls using periodic checking
    private func startStallMonitoring() {
        guard !loopAudio else { return } // Skip for looped audio

        stallCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.checkForStall()
        }
    }

    // Enhanced stall monitoring to handle network issues better
    private func checkForStall() {
        guard let currentPlayer = player, let currentItem = currentPlayer.currentItem else {
            return
        }

        // Use the actual player state, not the logical state
        let isPlayerPlaying = isPlayerActuallyPlaying()
        let playbackLikelyToKeepUp = currentItem.isPlaybackLikelyToKeepUp
        let playbackBufferEmpty = currentItem.isPlaybackBufferEmpty

        // Detect stall condition - but only if network is available
        // If network is unavailable, the network monitor will handle it
        let shouldBeStalled = isPlayerPlaying && !playbackLikelyToKeepUp && playbackBufferEmpty && isNetworkAvailable

        if shouldBeStalled && !isCurrentlyStalled {
            // New stall detected
            isCurrentlyStalled = true

            print("=== STALL DETECTED VIA MONITORING ===")
            print("Audio ID: \(id)")
            print("Is player playing: \(isPlayerPlaying)")
            print("Likely to keep up: \(playbackLikelyToKeepUp)")
            print("Buffer empty: \(playbackBufferEmpty)")
            print("Network available: \(isNetworkAvailable)")

            // Update command center to show stalled state immediately
            if useForNotification {
                setNowPlayingInfoKey(
                    for: MPNowPlayingInfoPropertyPlaybackRate,
                    value: 0.0
                )
            }

            makePluginCall(
                callbackId: onStalledCallbackId,
                data: [
                    "reason": "buffer_empty",
                    "currentTime": getCurrentTime(),
                    "duration": getDuration(),
                    "networkAvailable": isNetworkAvailable,
                    "bufferEmpty": playbackBufferEmpty,
                    "likelyToKeepUp": playbackLikelyToKeepUp
                ]
            )

        } else if !shouldBeStalled && isCurrentlyStalled && isNetworkAvailable {
            // Stall resolved (only if network is available)
            isCurrentlyStalled = false

            print("=== STALL RESOLVED ===")
            print("Audio ID: \(id)")

            // Update command center to show resumed state
            if useForNotification {
                let playbackRate: Float = loopAudio ? playerQueue.rate : player.rate
                setNowPlayingInfoKey(
                    for: MPNowPlayingInfoPropertyPlaybackRate,
                    value: playbackRate
                )
            }

            makePluginCall(
                callbackId: onStalledCallbackId,
                data: [
                    "reason": "stall_resolved",
                    "currentTime": getCurrentTime(),
                    "duration": getDuration(),
                    "networkAvailable": isNetworkAvailable
                ]
            )
        }
    }

    // Method to handle when playback is likely to keep up again
    @objc private func playerItemLikelyToKeepUp(_ notification: Notification) {
        if isCurrentlyStalled {
            print("=== PLAYBACK LIKELY TO KEEP UP ===")
            print("Audio ID: \(id)")

            isCurrentlyStalled = false

            makePluginCall(
                callbackId: onStalledCallbackId,
                data: [
                    "reason": "likely_to_keep_up",
                    "currentTime": getCurrentTime(),
                    "duration": getDuration(),
                    "networkAvailable": networkMonitor?.currentPath.status == .satisfied
                ]
            )

            print("=================================")
        }
    }

    // Centralized track end handling
    private func handleTrackEnd(source: String) {
        print("=== HANDLING TRACK END ===")
        print("Source: \(source)")
        print("Audio ID: \(id)")
        print("Track: \(audioMetadata.songTitle)")
        print("Current time: \(getCurrentTime())")
        print("Duration: \(getDuration())")
        print("Is playing: \(isPlaying())")
        print("Use for notification: \(useForNotification)")
        print("onEndCallbackId: \(onEndCallbackId)")
        print("App state: \(UIApplication.shared.applicationState.rawValue)")
        print("Thread: \(Thread.isMainThread ? "main" : "background")")

        // Ensure we're on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            print("Executing track end on main thread")

            // Stop the player first
            self.stop()

            // Make the callback
            if !self.onEndCallbackId.isEmpty {
                print("Triggering onEnd callback: \(self.onEndCallbackId)")
                self.makePluginCall(callbackId: self.onEndCallbackId)
                print("onEnd callback triggered successfully")
            } else {
                print("WARNING: No onEnd callback ID available")
            }

            print("Track end handling completed")
        }
        print("=========================")
    }

    // Enhanced removeOnEndObservation to clean up all observers
    private func removeOnEndObservation() {
        print("Removing end observations for audio ID: \(id)")

        // Remove boundary time observer with safety check
        if let observer = audioOnEndObservation, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            audioOnEndObservation = nil
            print("Boundary time observer removed")
        }

        // Remove periodic end check observer
        if let observer = periodicEndCheckObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            periodicEndCheckObserver = nil
            print("Periodic end check observer removed")
        }

        // Remove notification observers with safety check
        if let currentPlayer = player, let currentItem = currentPlayer.currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: currentItem
            )

            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemPlaybackStalled,
                object: currentItem
            )
        }

        print("All end observations removed")
    }

    private func setupRemoteTransportControls() {
        if !useForNotification {
            return
        }

        print("Setting up remote transport controls for audio ID: \(id)")

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            print("Remote play command received for audio ID: \(self.id)")

            if !self.isPlaying() {
                self.play()

                self.makePluginCall(
                    callbackId: self.onPlaybackStatusChangeCallbackId,
                    data: [
                        "status": "playing"
                    ]
                )

                return .success
            }

            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget {
            [unowned self] _ -> MPRemoteCommandHandlerStatus in
            print("Remote pause command received for audio ID: \(self.id)")
            print("Pause rate: " + String(self.player.rate))

            if self.isPlaying() {
                self.pause()

                self.makePluginCall(
                    callbackId: self.onPlaybackStatusChangeCallbackId,
                    data: [
                        "status": "paused"
                    ]
                )

                return .success
            }

            return .commandFailed
        }

        if showSeekBackward {
            commandCenter.skipBackwardCommand.addTarget {
                [unowned self] _ -> MPRemoteCommandHandlerStatus in
                print("Remote skip backward command for audio ID: \(self.id)")

                var seekTime = floor(
                    self.getCurrentTime()
                        - Double(self.STANDARD_SEEK_IN_SECONDS)
                )

                if seekTime < 0 {
                    seekTime = 0
                }

                self.seek(timeInSeconds: Int64(seekTime))

                return .success
            }

            commandCenter.skipBackwardCommand.preferredIntervals = [
                NSNumber.init(value: self.STANDARD_SEEK_IN_SECONDS)
            ]
        }

        if showSeekForward {
            commandCenter.skipForwardCommand.addTarget {
                [unowned self] _ -> MPRemoteCommandHandlerStatus in
                print("Remote skip forward command for audio ID: \(self.id)")

                var seekTime = ceil(
                    self.getCurrentTime()
                        + Double(self.STANDARD_SEEK_IN_SECONDS)
                )
                var duration = floor(self.getDuration())

                duration = duration < 0 ? 0 : duration

                if seekTime > duration {
                    seekTime = duration
                }

                self.seek(timeInSeconds: Int64(seekTime))

                return .success
            }

            commandCenter.skipForwardCommand.preferredIntervals = [
                NSNumber.init(value: self.STANDARD_SEEK_IN_SECONDS)
            ]
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = showSeekBackward
        commandCenter.skipForwardCommand.isEnabled = showSeekForward
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
    }

    private func removeRemoteTransportControls() {
        if !useForNotification {
            return
        }

        print("Removing remote transport controls for audio ID: \(id)")

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
    }

    private func setupNowPlaying() {
        if !useForNotification {
            return
        }

        print("Setting up now playing info for audio ID: \(id)")

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()

        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = audioMetadata.albumTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = audioMetadata.artistName
        nowPlayingInfo[MPMediaItemPropertyTitle] = audioMetadata.songTitle

        // Always set duration and current time for tracks with known duration
        let duration = getDuration()
        let currentTime = getCurrentTime()

        print("Setting up now playing - Duration: \(duration), Current Time: \(currentTime)")

        if duration > 0 {
            // For tracks with known duration
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            // For live streams, set to 0
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
        }

        // Always set elapsed time, even if it's 0
        if currentTime >= 0 {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        } else {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        }

        let playbackRate: Float

        if loopAudio {
            playbackRate = playerQueue.rate
        } else {
            playbackRate = player.rate
        }

        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        print("Setting playback rate to: \(playbackRate)")

        let artwork = getNowPlayingArtwork()
        if artwork != nil {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo

        // Force update the playback state as well
        nowPlayingInfoCenter.playbackState = isPlaying() ? .playing : .paused
    }

    private func setNowPlayingInfoKey(for key: String, value: Any?) {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo

        if nowPlayingInfo == nil {
            return
        }

        nowPlayingInfo![key] = value

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func getNowPlayingArtwork() -> MPMediaItemArtwork? {
        if nowPlayingArtwork != nil {
            return nowPlayingArtwork
        }

        if !audioMetadata.artworkSource.isEmpty {
            downloadNowPlayingIcon()
        } else {
            if let image = UIImage(named: "NowPlayingIcon") {
                nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) {
                    _ in
                    return image
                }
            }
        }

        return nowPlayingArtwork
    }

    private func downloadNowPlayingIcon() {
        guard
            var artworkSourceUrl = URL.init(string: audioMetadata.artworkSource)
        else {
            print(
                "Error: artworkSource '" + audioMetadata.artworkSource
                    + "' is invalid (1)"
            )
            return
        }

        if artworkSourceUrl.scheme != "https" {
            guard
                let baseAppPath = pluginOwner.bridge?.config.appLocation
                    .absoluteString,
                let baseAppPathUrl = URL.init(string: baseAppPath)
            else {
                print("Error: Cannot find base path of application")
                return
            }

            artworkSourceUrl = baseAppPathUrl.appendingPathComponent(
                artworkSourceUrl.absoluteString
            )
        }

        let task = URLSession.shared.dataTask(
            with: artworkSourceUrl
        ) { data, _, _ in
            guard let imageData = data, let image = UIImage(data: imageData)
            else {
                print(
                    "Error: artworkSource data is invalid - "
                        + artworkSourceUrl.absoluteString
                )
                return
            }

            DispatchQueue.main.async {
                self.nowPlayingArtwork = MPMediaItemArtwork(
                    boundsSize: image.size
                ) { _ in image }
                self.setNowPlayingInfoKey(
                    for: MPMediaItemPropertyArtwork,
                    value: self.nowPlayingArtwork
                )
            }
        }

        task.resume()
    }

    // Update the setNowPlayingCurrentTime to respect stall state
    private func setNowPlayingCurrentTime() {
        if !useForNotification {
            return
        }

        // Don't update time if currently stalled
        if isCurrentlyStalled {
            return
        }

        let currentTime = getCurrentTime()

        setNowPlayingInfoKey(
            for: MPNowPlayingInfoPropertyElapsedPlaybackTime,
            value: currentTime >= 0 ? currentTime : 0
        )

        let playbackRate: Float
        if loopAudio {
            playbackRate = playerQueue.rate
        } else {
            playbackRate = player.rate
        }

        // Set rate to 0 if stalled
        setNowPlayingInfoKey(
            for: MPNowPlayingInfoPropertyPlaybackRate,
            value: isCurrentlyStalled ? 0.0 : playbackRate
        )
    }

    private func removeNowPlaying() {
        if !useForNotification {
            return
        }

        print("Removing now playing info for audio ID: \(id)")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setNowPlayingPlaybackState(state: MPNowPlayingPlaybackState) {
        if !useForNotification {
            return
        }

        print("Setting now playing state to: \(state.rawValue) for audio ID: \(id)")
        //MPNowPlayingInfoCenter.default().playbackState = state
    }

    private func getCmTime(seconds: Int64) -> CMTime {
        return CMTimeMake(value: seconds, timescale: 1)
    }

    private func makePluginCall(callbackId: String) {
        makePluginCall(callbackId: callbackId, data: [:])
    }

    private func makePluginCall(callbackId: String, data: PluginCallResultData) {
        if callbackId == "" {
            return
        }

        print("Making plugin call with callback ID: \(callbackId)")

        let call = pluginOwner.bridge?.savedCall(withID: callbackId)

        if data.isEmpty {
            call?.resolve()
        } else {
            call?.resolve(data)
        }
    }

   // Update the periodic time observer in observeDurationChanges
   private func observeDurationChanges() {
       print("Setting up duration change observation for audio ID: \(id)")

       guard let currentPlayerItem = playerItem else {
           print("WARNING: PlayerItem not available for duration observation")
           return
       }

       // Observe duration changes
       durationObservation = currentPlayerItem.observe(\.duration, options: [.new, .old]) { [weak self] item, change in
           guard let self = self else { return }

           let newDuration = item.duration

           print("Duration changed - new duration: \(newDuration.seconds)")

           if newDuration != CMTime.indefinite && newDuration.seconds > 0 {
               print("Valid duration found: \(newDuration.seconds) seconds")
               DispatchQueue.main.async {
                   self.updateMediaSessionWithValidDuration()
               }
           }
       }

       guard let currentPlayer = player else {
           print("WARNING: Player not available for periodic time observation")
           return
       }

       let timeInterval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
       periodicTimeObserver = currentPlayer.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
           guard let self = self else { return }

           // Only update command center if we should be showing progress
           // Use player state check to avoid circular dependency
           if self.useForNotification && self.isPlayerActuallyPlaying() && !self.isCurrentlyStalled {
               self.setNowPlayingCurrentTime()
           }
       }
   }

    // Method to update media session once valid duration is available
    private func updateMediaSessionWithValidDuration() {
        guard useForNotification else { return }

        print("Updating media session with valid duration for audio ID: \(id)")

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()

        let duration = getDuration()
        let currentTime = getCurrentTime()

        print("Updating media session with valid duration: \(duration), current time: \(currentTime)")

        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if currentTime >= 0 {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }

        // Ensure playback rate is set
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        nowPlayingInfoCenter.playbackState = isPlaying() ? .playing : .paused
    }
}
