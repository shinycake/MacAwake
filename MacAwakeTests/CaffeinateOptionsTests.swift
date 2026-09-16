import Foundation
import Testing
@testable import MacAwake

struct CaffeinateOptionsTests {
    @Test
    func buildsEverySupportedCaffeinateArgument() {
        var options = CaffeinateOptions()
        options.preventDisplaySleep = true
        options.preventDiskIdle = true
        options.preventSystemSleepOnACPower = true
        options.declareUserActive = true
        options.useTimeout = true
        options.timeoutSeconds = 90
        options.waitForProcess = true
        options.processID = 42
        options.runUtility = true
        options.utilityPath = "/usr/bin/say"
        options.utilityArguments = "hello world\n--voice\nSamantha"

        #expect(options.validationError == nil)
        #expect(options.arguments == [
            "-d", "-i", "-m", "-s", "-u",
            "-t", "90", "-w", "42",
            "/usr/bin/say", "hello world", "--voice", "Samantha"
        ])
    }

    @Test
    func requiresAnAssertion() {
        var options = CaffeinateOptions()
        options.preventIdleSystemSleep = false

        #expect(options.validationError != nil)
    }

    @Test @MainActor
    func durationPresetUpdatesCaffeinateArguments() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let controller = CaffeinateController(defaults: defaults)

        controller.awakeDuration = .twoHours
        #expect(controller.options.arguments == ["-i", "-t", "7200"])

        controller.awakeDuration = .indefinitely
        #expect(!controller.options.arguments.contains("-t"))
    }
}
