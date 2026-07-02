import SwiftUI
import BackgroundTasks
import UserNotifications
import WidgetKit

@main
struct PegelWatchApp: App {
    
    init() {
        registerBackgroundTasks()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationManager.shared.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationManager.shared.requestPermission()
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
            
            
            /*
            let store = StationStore.shared
            let ids = store.watchedStations.map { $0.id }
            guard !ids.isEmpty else {
                task.setTaskCompleted(success: true)
                return
            }

            let levels = await PegelOnlineAPI.shared.fetchLevels(for: ids)

            for (id, value) in levels {
                store.updateLevel(id: id, value: value)

                guard let station = store.watchedStations.first(where: { $0.id == id }) else { continue }

                // ✅ 1. Update Live Activity
                await LiveActivityManager.shared.update(station: station)

                
                // ✅ 2. Send notification if threshold crossed
                if let threshold = station.alarmThreshold, value >= threshold {
                    NotificationManager.shared.sendAlarmNotification(for: station, currentValue: value)
                }
            }

            // ✅ 3. Tell WidgetKit to reload
            WidgetCenter.shared.reloadAllTimelines()

            */
            
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
