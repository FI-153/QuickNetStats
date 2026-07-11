//
//  LocationPermissionManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import CoreLocation
@testable import QuickNetStats

@Suite("LocationPermissionManager")
struct LocationPermissionManagerTests {

    @Test(
        "CLAuthorizationStatus maps to the app's three states",
        arguments: [
            (CLAuthorizationStatus.notDetermined, LocationAuthorizationState.notDetermined),
            (CLAuthorizationStatus.authorizedAlways, LocationAuthorizationState.authorized),
            (CLAuthorizationStatus.denied, LocationAuthorizationState.denied),
            (CLAuthorizationStatus.restricted, LocationAuthorizationState.denied),
        ]
    )
    func statusMapping(status: CLAuthorizationStatus, expected: LocationAuthorizationState) {
        #expect(LocationPermissionManager.state(from: status) == expected)
    }
}
