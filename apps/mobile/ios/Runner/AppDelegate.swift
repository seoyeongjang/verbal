import Flutter
import CoreLocation
import EventKit
import EventKitUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate, EKEventEditViewDelegate {
  private var locationManager: CLLocationManager?
  private var locationResult: FlutterResult?
  private let eventStore = EKEventStore()
  private var externalCalendarResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "verbal/location",
      binaryMessenger: engineBridge.binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "currentLocation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestCurrentLocation(result: result)
    }
    FlutterMethodChannel(
      name: "verbal/external_calendar",
      binaryMessenger: engineBridge.binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "addEvent" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.addExternalCalendarEvent(arguments: call.arguments, result: result)
    }
  }

  private func requestCurrentLocation(result: @escaping FlutterResult) {
    if locationResult != nil {
      result(FlutterError(
        code: "location_busy",
        message: "A location request is already running.",
        details: nil
      ))
      return
    }
    let manager = CLLocationManager()
    locationManager = manager
    locationResult = result
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.requestWhenInUseAuthorization()
    manager.requestLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finishLocation(errorCode: "location_unavailable", message: "Current location is unavailable.")
      return
    }
    locationResult?([
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy
    ])
    locationResult = nil
    locationManager = nil
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finishLocation(errorCode: "location_unavailable", message: error.localizedDescription)
  }

  private func finishLocation(errorCode: String, message: String) {
    locationResult?(FlutterError(code: errorCode, message: message, details: nil))
    locationResult = nil
    locationManager = nil
  }

  private func addExternalCalendarEvent(arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = calendarPayload(arguments: arguments) else {
      result(FlutterError(
        code: "invalid_argument",
        message: "Calendar event payload is invalid.",
        details: nil
      ))
      return
    }
    if payload.target == "google" {
      openGoogleCalendar(payload: payload, result: result)
    } else {
      presentAppleCalendar(payload: payload, result: result)
    }
  }

  private func openGoogleCalendar(payload: ExternalCalendarPayload, result: @escaping FlutterResult) {
    var components = URLComponents(string: "https://calendar.google.com/calendar/render")
    components?.queryItems = [
      URLQueryItem(name: "action", value: "TEMPLATE"),
      URLQueryItem(name: "text", value: payload.title),
      URLQueryItem(name: "dates", value: "\(googleCalendarDate(payload.startDate))/\(googleCalendarDate(payload.endDate))"),
      URLQueryItem(name: "details", value: payload.description)
    ]
    guard let url = components?.url else {
      result(FlutterError(code: "calendar_unavailable", message: "Google Calendar URL is invalid.", details: nil))
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  private func presentAppleCalendar(payload: ExternalCalendarPayload, result: @escaping FlutterResult) {
    if externalCalendarResult != nil {
      result(FlutterError(code: "calendar_busy", message: "A calendar editor is already open.", details: nil))
      return
    }
    requestCalendarAccess { [weak self] granted, error in
      guard let self = self else { return }
      guard granted else {
        result(FlutterError(
          code: "calendar_permission_denied",
          message: error?.localizedDescription ?? "Calendar access was denied.",
          details: nil
        ))
        return
      }
      guard let presenter = self.topViewController() else {
        result(FlutterError(code: "calendar_unavailable", message: "Unable to present calendar editor.", details: nil))
        return
      }
      guard let defaultCalendar = self.eventStore.defaultCalendarForNewEvents else {
        result(FlutterError(code: "calendar_unavailable", message: "Default calendar is unavailable.", details: nil))
        return
      }
      let event = EKEvent(eventStore: self.eventStore)
      event.title = payload.title
      event.startDate = payload.startDate
      event.endDate = payload.endDate
      event.notes = payload.description
      event.calendar = defaultCalendar

      let editor = EKEventEditViewController()
      editor.eventStore = self.eventStore
      editor.event = event
      editor.editViewDelegate = self
      self.externalCalendarResult = result
      presenter.present(editor, animated: true)
    }
  }

  private func requestCalendarAccess(completion: @escaping (Bool, Error?) -> Void) {
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents { granted, error in
        DispatchQueue.main.async {
          completion(granted, error)
        }
      }
    } else {
      eventStore.requestAccess(to: .event) { granted, error in
        DispatchQueue.main.async {
          completion(granted, error)
        }
      }
    }
  }

  func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
    let didSave = action == .saved
    controller.dismiss(animated: true) { [weak self] in
      self?.externalCalendarResult?(didSave)
      self?.externalCalendarResult = nil
    }
  }

  private func topViewController() -> UIViewController? {
    let windowScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first
    var controller = windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private func calendarPayload(arguments: Any?) -> ExternalCalendarPayload? {
    guard let data = arguments as? [String: Any],
          let title = data["title"] as? String,
          !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let startMillis = millisValue(data["startAtMillis"]),
          let endMillis = millisValue(data["endAtMillis"]) else {
      return nil
    }
    let description = data["description"] as? String ?? ""
    let target = data["target"] as? String ?? "apple"
    return ExternalCalendarPayload(
      target: target,
      title: title,
      startDate: Date(timeIntervalSince1970: startMillis / 1000),
      endDate: Date(timeIntervalSince1970: endMillis / 1000),
      description: description
    )
  }

  private func millisValue(_ value: Any?) -> TimeInterval? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let value = value as? Double {
      return value
    }
    if let value = value as? Int {
      return TimeInterval(value)
    }
    return nil
  }

  private func googleCalendarDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: date)
  }
}

private struct ExternalCalendarPayload {
  let target: String
  let title: String
  let startDate: Date
  let endDate: Date
  let description: String
}
