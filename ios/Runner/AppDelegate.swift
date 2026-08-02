import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let started = registerScreenAwakeChannel()
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // The root controller isn't always up yet at this point (it isn't
    // with a scene-based launch); try once more after super has built it.
    if !started { _ = registerScreenAwakeChannel() }

    return result
  }

  private var screenAwakeChannel: FlutterMethodChannel?

  /// Keeps the display lit (no auto-dim, no auto-lock) while a
  /// Mushaf/reader screen is open. Disabling the idle timer is the
  /// system's own mechanism — brightness itself is never touched.
  /// Returns false when the Flutter controller isn't available yet.
  @discardableResult
  private func registerScreenAwakeChannel() -> Bool {
    guard screenAwakeChannel == nil else { return true }
    guard let controller = window?.rootViewController as? FlutterViewController
    else { return false }

    let channel = FlutterMethodChannel(
      name: "com.omar.quran_app_v1/screen_awake",
      binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setKeepAwake" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let enabled = args?["enabled"] as? Bool ?? false
      UIApplication.shared.isIdleTimerDisabled = enabled
      result(nil)
    }
    screenAwakeChannel = channel
    return true
  }
}
