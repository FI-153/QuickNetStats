//
//  LocationPermissionManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-07.
//

import Foundation
import Combine
import CoreLocation

/// The app-level view of Location Services authorization, collapsed to the three
/// states the opt-in toggle cares about.
enum LocationAuthorizationState {
    case notDetermined
    case authorized
    case denied
}

/// Owns the `CLLocationManager` used solely to unlock CoreWLAN's location-gated
/// SSID/BSSID reads. Never requests a location fix. This is the ONLY file that
/// imports CoreLocation.
class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// The current authorization state; updates whenever the system reports a change.
    @Published private(set) var state: LocationAuthorizationState

    private let manager: CLLocationManager

    /// Pending grant continuation from `requestAuthorization(onGrant:)`; fired once
    /// the user answers the system prompt with a grant, discarded on refusal.
    private var onGrant: (() -> Void)?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.state = Self.state(from: manager.authorizationStatus)
        super.init()
        manager.delegate = self
    }

    /// Shows the system location prompt (only possible while `.notDetermined`) and
    /// runs `onGrant` if the user authorizes.
    func requestAuthorization(onGrant: @escaping () -> Void) {
        self.onGrant = onGrant
        manager.requestWhenInUseAuthorization()
    }

    /// Delegate callbacks are not actor-isolated; hop to the main actor before
    /// touching published state.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.apply(status)
        }
    }

    /// Publishes the new state and settles the pending grant continuation.
    private func apply(_ status: CLAuthorizationStatus) {
        state = Self.state(from: status)
        switch state {
        case .authorized:
            onGrant?()
            onGrant = nil
        case .denied:
            onGrant = nil
        case .notDetermined:
            break
        }
    }

    /// Collapses `CLAuthorizationStatus` to the app's three-state view. Unknown
    /// future cases degrade to `.denied` (no prompt, nothing displayed).
    nonisolated static func state(from status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}
