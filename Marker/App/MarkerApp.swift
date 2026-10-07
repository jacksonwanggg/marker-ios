import SwiftUI
import UserNotifications

@main
struct MarkerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.acc)
                .preferredColorScheme(model.prefs.theme.scheme)
                .task { await model.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.foreground() }
            case .background: if !model.isDemo, model.phase == .signedIn { Notifier.scheduleAppRefresh() }
            default: break
            }
        }
        .backgroundTask(.appRefresh(Notifier.refreshTaskID)) {
            await Notifier.refreshInBackground()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifier.registerCategories()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // "Mark as read later" just dismisses it, nothing goes to Formatif
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let p = info["projectID"] as? Int, let td = info["taskDefID"] as? Int else { return }
        let comments = info["comments"] as? Bool ?? false
        await MainActor.run {
            DeepLinks.shared.pending = DeepLink(key: TaskKey(projectID: p, taskDefID: td), comments: comments)
        }
    }
}
