import UIKit
import Capacitor
import SwiftData

// Capacitor/UIKit exposes a non-generic KeyPath symbol in this target. SwiftData's
// @Model macro expects the generic Swift standard-library KeyPath type, so make
// that resolution explicit at module scope.
typealias KeyPath<Root, Value> = Swift.KeyPath<Root, Value>

// MARK: - SwiftData personal models (iOS 17+)

@available(iOS 17.0, *)
@Model
final class RunPacerStoredRun {
    var id: UUID = UUID()
    var name: String = "Course"
    var distanceKm: Double = 0
    var durationSecs: Int?
    var date: Date = Date()
    var type: String = "Run"
    var source: String = "runpacer"
    var notes: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "Course",
        distanceKm: Double,
        durationSecs: Int? = nil,
        date: Date = Date(),
        type: String = "Run",
        source: String = "runpacer",
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.distanceKm = distanceKm
        self.durationSecs = durationSecs
        self.date = date
        self.type = type
        self.source = source
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Flexible snapshot used for the existing Supabase `user_backups` payloads.
/// Keeping the complex user/training-plan structures as JSON avoids freezing a
/// large CloudKit schema before those structures are fully stabilized.
@available(iOS 17.0, *)
@Model
final class RunPacerUserSnapshot {
    var snapshotKey: String = "current-user"
    var userDataJSON: String?
    var trainingPlanJSON: String?
    var deviceId: String?
    var updatedAt: Date = Date()

    init(
        snapshotKey: String = "current-user",
        userDataJSON: String? = nil,
        trainingPlanJSON: String? = nil,
        deviceId: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.snapshotKey = snapshotKey
        self.userDataJSON = userDataJSON
        self.trainingPlanJSON = trainingPlanJSON
        self.deviceId = deviceId
        self.updatedAt = updatedAt
    }
}

// MARK: - SwiftData store

@available(iOS 17.0, *)
@MainActor
final class RunPacerDataStore {
    static let shared = RunPacerDataStore()

    let container: ModelContainer
    let cloudKitEnabled: Bool
    private(set) var persistenceFallbackReason: String?

    private init() {
        cloudKitEnabled = Bundle.main.object(forInfoDictionaryKey: "RunPacerCloudKitEnabled") as? Bool ?? false

        let schema = Schema([
            RunPacerStoredRun.self,
            RunPacerUserSnapshot.self
        ])

        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = cloudKitEnabled ? .automatic : .none
        let configuration = ModelConfiguration(
            "RunPacerPersonal",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: cloudKitDatabase
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Do not crash the whole running app if the persistent store cannot
            // initialize. The bridge reports this fallback so it can be surfaced
            // during testing instead of silently losing data.
            persistenceFallbackReason = error.localizedDescription
            let fallback = ModelConfiguration(
                "RunPacerPersonalFallback",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            container = try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    func saveRun(
        id: UUID,
        name: String,
        distanceKm: Double,
        durationSecs: Int?,
        date: Date,
        type: String,
        source: String,
        notes: String?,
        createdAt: Date
    ) throws {
        let context = container.mainContext
        let runId = id
        let descriptor = FetchDescriptor<RunPacerStoredRun>(
            predicate: #Predicate { $0.id == runId }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.name = name
            existing.distanceKm = distanceKm
            existing.durationSecs = durationSecs
            existing.date = date
            existing.type = type
            existing.source = source
            existing.notes = notes
            existing.createdAt = createdAt
        } else {
            context.insert(
                RunPacerStoredRun(
                    id: id,
                    name: name,
                    distanceKm: distanceKm,
                    durationSecs: durationSecs,
                    date: date,
                    type: type,
                    source: source,
                    notes: notes,
                    createdAt: createdAt
                )
            )
        }

        try context.save()
    }

    func listRuns() throws -> [RunPacerStoredRun] {
        var descriptor = FetchDescriptor<RunPacerStoredRun>()
        descriptor.sortBy = [SortDescriptor(\RunPacerStoredRun.date, order: .reverse)]
        return try container.mainContext.fetch(descriptor)
    }

    func deleteRun(id: UUID) throws -> Bool {
        let context = container.mainContext
        let runId = id
        let descriptor = FetchDescriptor<RunPacerStoredRun>(
            predicate: #Predicate { $0.id == runId }
        )
        guard let run = try context.fetch(descriptor).first else { return false }
        context.delete(run)
        try context.save()
        return true
    }

    func saveSnapshot(
        userDataJSON: String?,
        trainingPlanJSON: String?,
        deviceId: String?
    ) throws {
        let context = container.mainContext
        let key = "current-user"
        let descriptor = FetchDescriptor<RunPacerUserSnapshot>(
            predicate: #Predicate { $0.snapshotKey == key }
        )

        let snapshot: RunPacerUserSnapshot
        if let existing = try context.fetch(descriptor).first {
            snapshot = existing
        } else {
            snapshot = RunPacerUserSnapshot(snapshotKey: key)
            context.insert(snapshot)
        }

        snapshot.userDataJSON = userDataJSON
        snapshot.trainingPlanJSON = trainingPlanJSON
        snapshot.deviceId = deviceId
        snapshot.updatedAt = Date()
        try context.save()
    }

    func loadSnapshot() throws -> RunPacerUserSnapshot? {
        let key = "current-user"
        let descriptor = FetchDescriptor<RunPacerUserSnapshot>(
            predicate: #Predicate { $0.snapshotKey == key }
        )
        return try container.mainContext.fetch(descriptor).first
    }
}

// MARK: - Capacitor bridge

@available(iOS 17.0, *)
@objc(RunPacerStoragePlugin)
public class RunPacerStoragePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RunPacerStoragePlugin"
    public let jsName = "RunPacerStorage"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveRun", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listRuns", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteRun", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveSnapshot", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadSnapshot", returnType: CAPPluginReturnPromise)
    ]

    private let isoFormatter = ISO8601DateFormatter()
    private let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func parseISODate(_ value: String) -> Date? {
        // RunPacer's historical `startTime` values include milliseconds, e.g.
        // 2026-06-06T12:01:09.093Z. ISO8601DateFormatter's default options do
        // not reliably parse fractional seconds, so try that format first.
        if let parsed = isoFormatterWithFractionalSeconds.date(from: value) {
            return parsed
        }
        return isoFormatter.date(from: value)
    }

    private func date(from call: CAPPluginCall, key: String, fallback: Date = Date()) -> Date {
        if let timestamp = call.getDouble(key) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let value = call.getString(key), let parsed = parseISODate(value) {
            return parsed
        }
        return fallback
    }

    @objc public func status(_ call: CAPPluginCall) {
        Task { @MainActor in
            let store = RunPacerDataStore.shared
            call.resolve([
                "available": true,
                "minimumIOS": 17,
                "cloudKitEnabled": store.cloudKitEnabled,
                "storageMode": store.cloudKitEnabled ? "swiftdata+cloudkit" : "swiftdata-local",
                "persistent": store.persistenceFallbackReason == nil,
                "fallbackReason": store.persistenceFallbackReason ?? ""
            ])
        }
    }

    @objc public func saveRun(_ call: CAPPluginCall) {
        guard let distanceKm = call.getDouble("distanceKm") else {
            call.reject("distanceKm is required")
            return
        }

        let id = call.getString("id").flatMap(UUID.init(uuidString:)) ?? UUID()
        let name = call.getString("name") ?? "Course"
        let durationSecs = call.getInt("durationSecs")
        let type = call.getString("type") ?? "Run"
        let source = call.getString("source") ?? "runpacer"
        let notes = call.getString("notes")
        let runDate = date(from: call, key: "date")
        let createdAt = date(from: call, key: "createdAt", fallback: runDate)

        Task { @MainActor in
            do {
                try RunPacerDataStore.shared.saveRun(
                    id: id,
                    name: name,
                    distanceKm: distanceKm,
                    durationSecs: durationSecs,
                    date: runDate,
                    type: type,
                    source: source,
                    notes: notes,
                    createdAt: createdAt
                )
                call.resolve(["id": id.uuidString])
            } catch {
                call.reject("Unable to save run", nil, error)
            }
        }
    }

    @objc public func listRuns(_ call: CAPPluginCall) {
        Task { @MainActor in
            do {
                let runs: [JSObject] = try RunPacerDataStore.shared.listRuns().map { run in
                    [
                        "id": run.id.uuidString,
                        "name": run.name,
                        "distanceKm": run.distanceKm,
                        "durationSecs": run.durationSecs ?? 0,
                        "date": isoFormatter.string(from: run.date),
                        "type": run.type,
                        "source": run.source,
                        "notes": run.notes ?? "",
                        "createdAt": isoFormatter.string(from: run.createdAt)
                    ]
                }
                call.resolve(["runs": runs])
            } catch {
                call.reject("Unable to load runs", nil, error)
            }
        }
    }

    @objc public func deleteRun(_ call: CAPPluginCall) {
        guard let idString = call.getString("id"), let id = UUID(uuidString: idString) else {
            call.reject("A valid run id is required")
            return
        }

        Task { @MainActor in
            do {
                let deleted = try RunPacerDataStore.shared.deleteRun(id: id)
                call.resolve(["deleted": deleted])
            } catch {
                call.reject("Unable to delete run", nil, error)
            }
        }
    }

    @objc public func saveSnapshot(_ call: CAPPluginCall) {
        let userDataJSON = call.getString("userDataJson")
        let trainingPlanJSON = call.getString("trainingPlanJson")
        let deviceId = call.getString("deviceId")

        Task { @MainActor in
            do {
                try RunPacerDataStore.shared.saveSnapshot(
                    userDataJSON: userDataJSON,
                    trainingPlanJSON: trainingPlanJSON,
                    deviceId: deviceId
                )
                call.resolve(["saved": true])
            } catch {
                call.reject("Unable to save user snapshot", nil, error)
            }
        }
    }

    @objc public func loadSnapshot(_ call: CAPPluginCall) {
        Task { @MainActor in
            do {
                guard let snapshot = try RunPacerDataStore.shared.loadSnapshot() else {
                    call.resolve(["exists": false])
                    return
                }
                call.resolve([
                    "exists": true,
                    "userDataJson": snapshot.userDataJSON ?? "",
                    "trainingPlanJson": snapshot.trainingPlanJSON ?? "",
                    "deviceId": snapshot.deviceId ?? "",
                    "updatedAt": isoFormatter.string(from: snapshot.updatedAt)
                ])
            } catch {
                call.reject("Unable to load user snapshot", nil, error)
            }
        }
    }
}

/// Capacitor 7 requires local plugins to be registered on the bridge view
/// controller. Keeping this class in AppDelegate.swift means no Xcode project
/// file references need to be added for the first migration step.
@objc(RunPacerBridgeViewController)
class RunPacerBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        if #available(iOS 17.0, *) {
            bridge?.registerPluginInstance(RunPacerStoragePlugin())
        }
    }
}

// MARK: - App lifecycle

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // ── Push Notifications ─────────────────────────────────────────────

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(
            name: .capacitorDidRegisterForRemoteNotifications,
            object: deviceToken
        )
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(
            name: .capacitorDidFailToRegisterForRemoteNotifications,
            object: error
        )
    }

    // ── Deep Links (Strava OAuth) ──────────────────────────────────────

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // ── Lifecycle ──────────────────────────────────────────────────────

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}
}
