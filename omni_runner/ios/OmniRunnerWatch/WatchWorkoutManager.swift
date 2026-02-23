import Foundation
import HealthKit
import CoreLocation

/// Manages the full lifecycle of a watch workout:
/// - HKWorkoutSession + HKLiveWorkoutBuilder (HR, calories, HealthKit save)
/// - CLLocationManager (GPS tracking)
/// - Distance via Haversine (consistent with Flutter core)
/// - Pace calculation
///
/// Conforms to ObservableObject for SwiftUI data binding.
///
/// Architecture reference: docs/WatchArchitecture.md §3.1
final class WatchWorkoutManager: NSObject, ObservableObject {

    // MARK: - Public State

    enum WorkoutState: String {
        case idle
        case running
        case paused
        case ended
    }

    @Published var state: WorkoutState = .idle
    @Published var currentHeartRate: Int = 0
    @Published var averageHeartRate: Int = 0
    @Published var maxHeartRate: Int = 0
    @Published var totalDistanceMeters: Double = 0
    @Published var elapsedSeconds: Int = 0
    @Published var currentPaceSecondsPerKm: Double = 0

    /// Accumulated GPS points (for sync and route).
    @Published private(set) var gpsPoints: [LocationPoint] = []

    /// Accumulated HR samples (for sync).
    @Published private(set) var hrSamples: [HeartRateSample] = []

    /// Unique session identifier (generated on watch, sent to phone).
    let sessionId = UUID()

    // MARK: - Connectivity

    /// Optional reference to the watch connectivity manager for sync.
    var connectivity: WatchConnectivityManager?

    // MARK: - HealthKit

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?

    // MARK: - Location

    private var locationManager: CLLocationManager?
    private var lastLocation: CLLocation?

    // MARK: - Timing

    private var startDate: Date?
    private var pauseDate: Date?
    private var accumulatedPauseSeconds: TimeInterval = 0
    private var timer: Timer?

    // MARK: - Accuracy Filter

    /// Max horizontal accuracy in meters to accept a GPS point.
    private let maxAccuracyMeters: Double = 20.0

    /// Min distance delta (m) to accumulate — filters GPS jitter.
    private let minDeltaMeters: Double = 1.0

    /// Max distance delta (m) per single update — filters teleports.
    private let maxDeltaMeters: Double = 100.0

    // MARK: - Permissions

    /// Request HealthKit authorization for workout recording.
    ///
    /// Must be called before `startWorkout()`.
    func requestPermissions() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[WorkoutManager] HealthKit not available on this device")
            return false
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        ]

        do {
            try await healthStore.requestAuthorization(
                toShare: typesToShare, read: typesToRead
            )
            return true
        } catch {
            print("[WorkoutManager] Permission error: \(error)")
            return false
        }
    }

    // MARK: - Workout Lifecycle

    /// Start a new outdoor running workout session.
    ///
    /// Flow:
    /// 1. Create HKWorkoutSession + HKLiveWorkoutBuilder
    /// 2. Start HealthKit data collection (HR auto-streams)
    /// 3. Start CLLocationManager for GPS
    /// 4. Start elapsed-time timer
    func startWorkout() async {
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore, configuration: config
            )
            let builder = session.associatedWorkoutBuilder()

            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder
            self.routeBuilder = HKWorkoutRouteBuilder(
                healthStore: healthStore, device: nil
            )

            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)

            startDate = now
            state = .running

            startLocationUpdates()
            startTimer()

            connectivity?.resetTransferState()
            connectivity?.sendStateUpdate(
                sessionId: sessionId.uuidString, state: "running"
            )

            playHaptic(.start)
        } catch {
            print("[WorkoutManager] Start error: \(error)")
        }
    }

    /// Pause the active workout.
    func pauseWorkout() {
        guard state == .running else { return }
        workoutSession?.pause()
        pauseDate = Date()
        stopTimer()
        connectivity?.sendStateUpdate(
            sessionId: sessionId.uuidString, state: "paused"
        )
        playHaptic(.stop)
    }

    /// Resume a paused workout.
    func resumeWorkout() {
        guard state == .paused else { return }
        workoutSession?.resume()
        if let pauseStart = pauseDate {
            accumulatedPauseSeconds += Date().timeIntervalSince(pauseStart)
        }
        pauseDate = nil
        startTimer()
        connectivity?.sendStateUpdate(
            sessionId: sessionId.uuidString, state: "running"
        )
        playHaptic(.start)
    }

    /// End the workout, save to HealthKit, finalize route.
    func endWorkout() async {
        guard state == .running || state == .paused else { return }

        workoutSession?.end()
        stopLocationUpdates()
        stopTimer()

        guard let builder = workoutBuilder else {
            state = .ended
            return
        }

        let endDate = Date()

        do {
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()

            if let routeBuilder = routeBuilder, !gpsPoints.isEmpty {
                try await routeBuilder.finishRoute(
                    with: workout, metadata: nil
                )
            }
        } catch {
            print("[WorkoutManager] End error: \(error)")
        }

        state = .ended

        // Transfer completed session to phone
        let sessionData = toSessionJSON()
        connectivity?.transferSession(sessionData)
        connectivity?.sendStateUpdate(
            sessionId: sessionId.uuidString, state: "ended"
        )

        playHaptic(.success)
    }

    /// Reset all state for a new workout.
    func reset() {
        workoutSession = nil
        workoutBuilder = nil
        routeBuilder = nil
        lastLocation = nil
        startDate = nil
        pauseDate = nil
        accumulatedPauseSeconds = 0

        gpsPoints.removeAll()
        hrSamples.removeAll()

        currentHeartRate = 0
        averageHeartRate = 0
        maxHeartRate = 0
        totalDistanceMeters = 0
        elapsedSeconds = 0
        currentPaceSecondsPerKm = 0

        state = .idle
    }

    // MARK: - Formatted Accessors

    /// Pace as "M:SS /km" string. Returns "--:--" if insufficient data.
    var formattedPace: String {
        guard currentPaceSecondsPerKm > 0,
              currentPaceSecondsPerKm < 3600 else { return "--:--" }
        let mins = Int(currentPaceSecondsPerKm) / 60
        let secs = Int(currentPaceSecondsPerKm) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Elapsed time as "H:MM:SS" or "MM:SS" string.
    var formattedElapsedTime: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Distance as "X.XX km" string.
    var formattedDistance: String {
        let km = totalDistanceMeters / 1000.0
        return String(format: "%.2f km", km)
    }

    // MARK: - Session Data Export

    /// Serialize the current session into the shared wire format (JSON).
    ///
    /// Matches the schema in `docs/WatchArchitecture.md` §5.
    func toSessionJSON() -> [String: Any] {
        let endMs = Int64(Date().timeIntervalSince1970 * 1000)
        let startMs = Int64(
            (startDate ?? Date()).timeIntervalSince1970 * 1000
        )
        let movingMs = Int64(
            (Double(elapsedSeconds) - accumulatedPauseSeconds) * 1000
        )

        return [
            "version": 1,
            "source": "apple_watch",
            "sessionId": sessionId.uuidString,
            "startMs": startMs,
            "endMs": endMs,
            "totalDistanceM": totalDistanceMeters,
            "movingMs": max(0, movingMs),
            "avgBpm": averageHeartRate,
            "maxBpm": maxHeartRate,
            "isVerified": true,
            "integrityFlags": [String](),
            "points": gpsPoints.map { pt in
                [
                    "lat": pt.latitude,
                    "lng": pt.longitude,
                    "alt": pt.altitude,
                    "accuracy": pt.accuracy,
                    "speed": pt.speed,
                    "timestampMs": pt.timestampMs,
                ] as [String: Any]
            },
            "hrSamples": hrSamples.map { s in
                [
                    "bpm": s.bpm,
                    "timestampMs": s.timestampMs,
                ] as [String: Any]
            },
        ]
    }

    // MARK: - Private: Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.updateElapsedTime()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsedTime() {
        guard let start = startDate, state == .running else { return }
        let total = Date().timeIntervalSince(start)
        elapsedSeconds = max(0, Int(total - accumulatedPauseSeconds))
        updatePace()
        sendLiveSampleIfNeeded()
    }

    /// Send a periodic live sample to the phone (throttled by connectivity manager).
    private func sendLiveSampleIfNeeded() {
        connectivity?.sendLiveSampleIfNeeded(
            sessionId: sessionId.uuidString,
            bpm: currentHeartRate,
            paceSecondsPerKm: currentPaceSecondsPerKm,
            distanceM: totalDistanceMeters,
            elapsedS: elapsedSeconds
        )
    }

    // MARK: - Private: Location

    private func startLocationUpdates() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        locationManager = manager
    }

    private func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
        locationManager?.delegate = nil
        locationManager = nil
    }

    // MARK: - Private: GPS Processing

    private func processLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxAccuracyMeters
        else { return }

        let point = LocationPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            accuracy: location.horizontalAccuracy,
            speed: max(0, location.speed),
            timestampMs: Int64(
                location.timestamp.timeIntervalSince1970 * 1000
            )
        )

        if let prev = lastLocation {
            let delta = Haversine.distanceMeters(
                lat1: prev.coordinate.latitude,
                lng1: prev.coordinate.longitude,
                lat2: location.coordinate.latitude,
                lng2: location.coordinate.longitude
            )

            if delta >= minDeltaMeters && delta <= maxDeltaMeters {
                totalDistanceMeters += delta
            }
        }

        gpsPoints.append(point)
        lastLocation = location

        routeBuilder?.insertRouteData([location]) { error in
            if let error {
                print("[WorkoutManager] Route insert error: \(error)")
            }
        }
    }

    // MARK: - Private: Pace

    private func updatePace() {
        guard totalDistanceMeters > 50, elapsedSeconds > 0 else {
            currentPaceSecondsPerKm = 0
            return
        }
        let kmCovered = totalDistanceMeters / 1000.0
        currentPaceSecondsPerKm = Double(elapsedSeconds) / kmCovered
    }

    // MARK: - Private: Heart Rate

    private func processHeartRate(from statistics: HKStatistics) {
        let unit = HKUnit.count().unitDivided(by: .minute())

        if let mostRecent = statistics.mostRecentQuantity() {
            let bpm = Int(mostRecent.doubleValue(for: unit))
            currentHeartRate = bpm

            let sample = HeartRateSample(
                bpm: bpm,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
            )
            hrSamples.append(sample)
        }

        if let avg = statistics.averageQuantity() {
            averageHeartRate = Int(avg.doubleValue(for: unit))
        }

        if let max = statistics.maximumQuantity() {
            maxHeartRate = Int(max.doubleValue(for: unit))
        }
    }

    // MARK: - Private: Haptics

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch toState {
            case .running:
                self.state = .running
            case .paused:
                self.state = .paused
            case .ended:
                self.state = .ended
            default:
                break
            }
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[WorkoutManager] Session error: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {
        // Workout events (lap markers, segment transitions) — not used yet.
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else {
                continue
            }

            if quantityType == HKQuantityType(.heartRate),
               let stats = workoutBuilder.statistics(for: quantityType)
            {
                DispatchQueue.main.async { [weak self] in
                    self?.processHeartRate(from: stats)
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchWorkoutManager: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard state == .running else { return }
        for location in locations {
            processLocation(location)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("[WorkoutManager] Location error: \(error)")
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if state == .running {
                manager.startUpdatingLocation()
            }
        default:
            print(
                "[WorkoutManager] Location not authorized: "
                    + "\(manager.authorizationStatus.rawValue)"
            )
        }
    }
}
