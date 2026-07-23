import SwiftUI
import BackgroundTasks
import UserNotifications
import WidgetKit
import UIKit
import TipKit

@main
struct PegelWatchApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        registerBackgroundTasks()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationManager.shared.registerCategories()
        #if DEBUG
        try? Tips.configure([.displayFrequency(.immediate)])
        #else
        try? Tips.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    UIApplication.shared.registerForRemoteNotifications()
                    scheduleBackgroundRefresh()
                }
        }
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "de.felixschick.pegelwatch.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleBackgroundRefresh(task: refreshTask)
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let operation = Task { @MainActor in
            await StationStore.shared.refreshAll()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "de.felixschick.pegelwatch.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await APNSManager.shared.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[APNS] Failed to register for remote notifications: \(error)")
        #endif
    }
}
