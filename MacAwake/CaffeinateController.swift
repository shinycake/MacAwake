import AppKit
import Foundation
import Observation
import ServiceManagement

enum AwakeDuration: CaseIterable, Equatable, Identifiable {
    case indefinitely
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case custom

    var id: Self { self }

    var seconds: Int? {
        switch self {
        case .indefinitely: nil
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1_800
        case .oneHour: 3_600
        case .twoHours: 7_200
        case .fourHours: 14_400
        case .eightHours: 28_800
        case .custom: nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .indefinitely: "Indefinitely"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        case .eightHours: "8 hours"
        case .custom: "Custom"
        }
    }
}

struct RunningApplicationChoice: Equatable, Identifiable {
    let id: Int
    let name: String
    let isRunning: Bool
}

struct CaffeinateOptions: Codable, Equatable {
    var preventDisplaySleep = false
    var preventIdleSystemSleep = true
    var preventDiskIdle = false
    var preventSystemSleepOnACPower = false
    var declareUserActive = false

    var useTimeout = false
    var timeoutSeconds = 3_600
    var waitForProcess = false
    var processID = 0

    var runUtility = false
    var utilityPath = ""
    var utilityArguments = ""

    var validationError: String? {
        guard preventDisplaySleep || preventIdleSystemSleep || preventDiskIdle
                || preventSystemSleepOnACPower || declareUserActive else {
            return String(localized: "Select at least one assertion.")
        }
        if useTimeout && timeoutSeconds <= 0 {
            return String(localized: "Duration must be greater than zero.")
        }
        if waitForProcess && processID <= 0 {
            return String(localized: "Enter a valid process ID.")
        }
        if runUtility && utilityPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Enter the utility to run.")
        }
        return nil
    }

    var arguments: [String] {
        var result: [String] = []
        if preventDisplaySleep { result.append("-d") }
        if preventIdleSystemSleep { result.append("-i") }
        if preventDiskIdle { result.append("-m") }
        if preventSystemSleepOnACPower { result.append("-s") }
        if declareUserActive { result.append("-u") }
        if useTimeout { result += ["-t", String(timeoutSeconds)] }
        // caffeinate honours only the last -w, so it is reserved for our own PID:
        // that way the assertion dies with MacAwake even on a force quit or crash.
        // "Stop when an application quits" is handled in CaffeinateController instead.
        result += ["-w", String(ProcessInfo.processInfo.processIdentifier)]
        if runUtility {
            result.append(utilityPath.trimmingCharacters(in: .whitespacesAndNewlines))
            result += utilityArguments
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
        }
        return result
    }
}

@MainActor
@Observable
final class CaffeinateController {
    var options: CaffeinateOptions {
        didSet {
            guard options != oldValue else { return }
            saveOptions()
            errorMessage = nil
            if isRunning && !oldValue.runUtility && !options.runUtility {
                restartAfterOptionsChange()
            }
        }
    }

    var awakeDuration: AwakeDuration {
        didSet {
            guard awakeDuration != oldValue else { return }
            applyAwakeDuration()
        }
    }
    var customDurationMinutes: Int {
        get { max(1, options.timeoutSeconds / 60) }
        set {
            options.useTimeout = true
            options.timeoutSeconds = max(1, newValue) * 60
        }
    }
    var stopWhenApplicationQuits: Bool {
        get { options.waitForProcess }
        set {
            refreshRunningApplications()
            options.waitForProcess = newValue
            if newValue && !runningApplications.contains(where: { $0.id == options.processID && $0.isRunning }) {
                options.processID = 0
            }
        }
    }

    private(set) var isRunning = false
    private(set) var isStopping = false
    private(set) var loginItemRequiresApproval = false
    private(set) var errorMessage: String?
    private(set) var runningApplications: [RunningApplicationChoice] = []
    var startsAtLogin: Bool {
        didSet {
            guard !isRefreshingLoginItem, startsAtLogin != oldValue else { return }
            updateLoginItem()
        }
    }
    var startsSessionOnLaunch: Bool {
        didSet {
            guard startsSessionOnLaunch != oldValue else { return }
            defaults.set(startsSessionOnLaunch, forKey: "startsSessionOnLaunch")
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var caffeinateProcess: Process?
    @ObservationIgnored private var activeRunID: UUID?
    @ObservationIgnored private var isRefreshingLoginItem = false
    @ObservationIgnored private var stoppedByUser = false
    @ObservationIgnored private var restartAfterTermination = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedOptions: CaffeinateOptions
        if let data = defaults.data(forKey: "caffeinateOptions"),
           let savedOptions = try? JSONDecoder().decode(CaffeinateOptions.self, from: data) {
            loadedOptions = savedOptions
        } else {
            loadedOptions = CaffeinateOptions()
        }
        options = loadedOptions
        if !loadedOptions.useTimeout {
            awakeDuration = .indefinitely
        } else {
            awakeDuration = AwakeDuration.allCases.first { $0.seconds == loadedOptions.timeoutSeconds } ?? .custom
        }

        startsSessionOnLaunch = defaults.bool(forKey: "startsSessionOnLaunch")

        let status = SMAppService.mainApp.status
        startsAtLogin = status == .enabled || status == .requiresApproval
        loginItemRequiresApproval = status == .requiresApproval

        // Lives for the whole app lifetime, like this controller, so it is never removed.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let terminatedProcessID = application?.processIdentifier
            Task { @MainActor in
                guard let terminatedProcessID else { return }
                self?.applicationDidTerminate(processID: Int(terminatedProcessID))
            }
        }
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        if let validationError = options.validationError {
            errorMessage = validationError
            return
        }
        if options.waitForProcess {
            refreshRunningApplications()
            guard runningApplications.contains(where: { $0.id == options.processID && $0.isRunning }) else {
                errorMessage = String(localized: "The selected application is no longer running.")
                return
            }
        }
        launchCaffeinate()
    }

    func stop() {
        guard let caffeinateProcess, caffeinateProcess.isRunning else { return }
        restartAfterTermination = false
        stoppedByUser = true
        isStopping = true
        caffeinateProcess.terminate()
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        isRefreshingLoginItem = true
        startsAtLogin = status == .enabled || status == .requiresApproval
        loginItemRequiresApproval = status == .requiresApproval
        isRefreshingLoginItem = false
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshRunningApplications() {
        let currentProcessID = Int(ProcessInfo.processInfo.processIdentifier)
        var applications = NSWorkspace.shared.runningApplications.compactMap { application -> RunningApplicationChoice? in
            guard !application.isTerminated,
                  Int(application.processIdentifier) != currentProcessID,
                  let name = application.localizedName else { return nil }
            return RunningApplicationChoice(
                id: Int(application.processIdentifier),
                name: name,
                isRunning: true
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if options.processID > 0 && !applications.contains(where: { $0.id == options.processID }) {
            applications.insert(
                RunningApplicationChoice(
                    id: options.processID,
                    name: String(localized: "Application no longer running"),
                    isRunning: false
                ),
                at: 0
            )
        }
        runningApplications = applications
    }

    func chooseUtility() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose an application or executable to run.")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.options.utilityPath = Bundle(url: url)?.executableURL?.path ?? url.path
        }
    }

    var customDurationDescription: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(options.timeoutSeconds)) ?? String(localized: "Custom")
    }

    private func applicationDidTerminate(processID: Int) {
        guard isRunning, options.waitForProcess, options.processID == processID else { return }
        stop()
    }

    private func launchCaffeinate() {
        let process = Process()
        let runID = UUID()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = options.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor [weak self] in
                self?.processEnded(runID: runID, status: status)
            }
        }

        do {
            try process.run()
            caffeinateProcess = process
            activeRunID = runID
            stoppedByUser = false
            isStopping = false
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn’t start caffeinate: \(error.localizedDescription)")
        }
    }

    private func processEnded(runID: UUID, status: Int32) {
        guard activeRunID == runID else { return }
        let shouldRestart = restartAfterTermination
        restartAfterTermination = false
        caffeinateProcess = nil
        activeRunID = nil
        isRunning = false
        isStopping = false
        if !stoppedByUser && status != 0 {
            errorMessage = String(localized: "Caffeinate exited with status \(status).")
        }
        stoppedByUser = false
        if shouldRestart {
            start()
        }
    }

    private func updateLoginItem() {
        do {
            if startsAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemStatus()
        } catch {
            errorMessage = String(localized: "Couldn’t update Start at Login: \(error.localizedDescription)")
            refreshLoginItemStatus()
        }
    }

    private func applyAwakeDuration() {
        switch awakeDuration {
        case .indefinitely:
            options.useTimeout = false
        case .custom:
            options.useTimeout = true
            if options.timeoutSeconds <= 0 {
                options.timeoutSeconds = 3_600
            }
        default:
            options.useTimeout = true
            options.timeoutSeconds = awakeDuration.seconds ?? 3_600
        }
    }

    private func restartAfterOptionsChange() {
        restartAfterTermination = true
        guard !isStopping, let caffeinateProcess, caffeinateProcess.isRunning else { return }
        stoppedByUser = true
        isStopping = true
        caffeinateProcess.terminate()
    }

    private func saveOptions() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: "caffeinateOptions")
    }
}
