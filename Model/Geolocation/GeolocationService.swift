// This file is part of Kiwix for iOS & macOS.
//
// Kiwix is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// any later version.
//
// Kiwix is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Kiwix; If not, see https://www.gnu.org/licenses/.

import CoreLocation
import Foundation

/// Groups the Geolocation response types we send to JS
protocol JSRespondable {
    var jsResponse: [String: Any] { get }
}

private enum GeolocationError: Int, Error, JSRespondable {
    // Matching the DOM equivalent from:
    // https://www.w3.org/TR/geolocation/#dom-geolocationpositionerror
    case permissionDenied = 1
    case positionUnavailable = 2
    case timeout = 3

    var localizedDescription: String {
        switch self {
        case .permissionDenied: return LocalString.geolocation_error_permission_denied
        case .positionUnavailable: return LocalString.geolocation_error_position_unavailable
        case .timeout: return LocalString.geolocation_error_timeout
        }
    }

    var jsResponse: [String: Any] {
        ["error": ["code": rawValue, "message": localizedDescription]]
    }
}

private struct GeolocationResponse: JSRespondable {
    struct Vertical {
        let altitude: Double
        let accuracy: Double
    }
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let vertical: Vertical?
    let course: Double?
    let speed: Double?
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        if location.verticalAccuracy >= 0 {
            vertical = Vertical(altitude: location.altitude, accuracy: location.verticalAccuracy)
        } else {
            vertical = nil
        }
        course = location.course >= 0 ? location.course : nil
        speed = location.speed >= 0 ? location.speed : nil
        timestamp = location.timestamp
    }

    var jsResponse: [String: Any] {
        var coords: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "accuracy": horizontalAccuracy
        ]
        if let vertical {
            coords["altitude"] = vertical.altitude
            coords["altitudeAccuracy"] = vertical.accuracy
        }
        if let course { coords["heading"] = course }
        if let speed { coords["speed"] = speed }
        return [
            "coords": coords,
            "timestamp": timestamp.timeIntervalSince1970 * 1000
        ]
    }
}

/// The incoming Geolocation request from JS
struct GeolocationRequest: Hashable {
    let id: UInt
    let type: RequestMethod
    let highAccuracy: Bool
    
    enum RequestMethod: String {
        case getCurrentPosition
        case watchPosition
        case clearWatch
    }
    
    init?(jsRequest payload: [String: Any]) {
        guard let payloadType = payload["type"] as? String,
              let requestMethod = RequestMethod(rawValue: payloadType),
              let requestId = payload["id"] as? UInt else { return nil }
        id = requestId
        type = requestMethod
        highAccuracy = (payload["highAccuracy"] as? NSNumber)?.boolValue ?? false
    }
}

@MainActor
final class GeolocationService: NSObject, @MainActor CLLocationManagerDelegate {
    private let onResult: @MainActor (JSRespondable) -> Void
    private var watchRequests = Set<UInt>()
    private var oneTimeRequests = Set<UInt>()
    private var task: Task<Void, Error>?
    private let manager = CLLocationManager()
    private var cachedLocation: CLLocation?
    
    init(onResult: @escaping @MainActor (JSRespondable) -> Void) {
        self.onResult = onResult
        super.init()
        manager.delegate = self
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            break
        case .restricted, .denied:
            onResult(GeolocationError.permissionDenied)
            stopAll()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func handle(request: GeolocationRequest) {
        switch request.type {
        case .clearWatch:
            // remove watch by id
            watchRequests = watchRequests.filter { $0 != request.id }
        case .getCurrentPosition:
            oneTimeRequests.insert(request.id)
            sendCachedLocation()
        case .watchPosition:
            watchRequests.insert(request.id)
            sendCachedLocation()
        }
        didUpdateRequests()
    }
    
    func stopAll() {
        stop()
        watchRequests.removeAll()
        oneTimeRequests.removeAll()
    }
    
    private func didUpdateRequests() {
        if watchRequests.isEmpty, oneTimeRequests.isEmpty {
            stop()
        } else {
            start()
        }
    }
    
    private func sendCachedLocation() {
        guard let cachedLocation else { return }
        let timeDiff = Date().timeIntervalSince(cachedLocation.timestamp)
        if timeDiff < 300 {
            onResult(GeolocationResponse(cachedLocation))
        } else {
            self.cachedLocation = nil
        }
    }
    
    private func start() {
        guard task == nil else { return }
        task = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard !Task.isCancelled else { break }
                    if let location = update.location {
                        // store it in cache
                        cachedLocation = location
                        onResult(GeolocationResponse(location))
                        // fired once, now remove them
                        oneTimeRequests.removeAll()
                        didUpdateRequests()
                    } else {
                        if watchRequests.isEmpty {
                            onResult(GeolocationError.positionUnavailable)
                        }
                    }
                }
            } catch {
                Log.Geolocation.warning("GeolocationService error: \(error.localizedDescription)")
                onResult(GeolocationError.timeout)
            }
        }
    }
    
    private func stop() {
        task?.cancel()
        task = nil
    }
}
