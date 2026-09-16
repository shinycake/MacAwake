import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var controller: CaffeinateController

    var body: some View {
        Form {
            Section("Prevent Sleep") {
                Toggle("Keep displays awake", isOn: $controller.options.preventDisplaySleep)
                Toggle("Keep Mac awake while idle", isOn: $controller.options.preventIdleSystemSleep)
                Toggle("Keep disks awake", isOn: $controller.options.preventDiskIdle)
                Toggle("Keep Mac awake when connected to power", isOn: $controller.options.preventSystemSleepOnACPower)
                Toggle("Simulate user activity", isOn: $controller.options.declareUserActive)
            }
            .disabled(configurationIsLocked)

            Section("Session") {
                Picker("Duration", selection: $controller.awakeDuration) {
                    ForEach(AwakeDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }

                if controller.awakeDuration == .custom {
                    Stepper(
                        controller.customDurationDescription,
                        value: $controller.customDurationMinutes,
                        in: 1...10_080,
                        step: 5
                    )
                }

                Toggle("Stop when an application quits", isOn: $controller.stopWhenApplicationQuits)
                if controller.stopWhenApplicationQuits {
                    LabeledContent("Application") {
                        Picker("Application", selection: $controller.options.processID) {
                            Text("Choose an application…").tag(0)
                            ForEach(controller.runningApplications) { application in
                                RunningApplicationLabel(application: application)
                                    .tag(application.id)
                            }
                        }
                        .labelsHidden()

                        Button {
                            controller.refreshRunningApplications()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh applications") // [VERIFY] confirm label matches intent
                    }
                }
            }
            .disabled(configurationIsLocked)

            Section("Executable") {
                Toggle("Keep awake while an executable runs", isOn: $controller.options.runUtility)
                if controller.options.runUtility {
                    LabeledContent("Executable") {
                        TextField("Application or executable", text: $controller.options.utilityPath)
                        Button("Choose…") {
                            controller.chooseUtility()
                        }
                    }

                    LabeledContent("Arguments (one per line)") {
                        TextEditor(text: $controller.options.utilityArguments)
                            .font(.body.monospaced())
                            .frame(minHeight: 64)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .separatorColor))
                                    .allowsHitTesting(false)
                            }
                            .accessibilityLabel("Executable arguments, one per line") // [VERIFY] confirm label matches intent
                    }
                }
            }
            .disabled(controller.isRunning)

            Section("General") {
                Toggle("Open MacAwake at Login", isOn: $controller.startsAtLogin)
                if controller.loginItemRequiresApproval {
                    LabeledContent("Login item needs approval") {
                        Button("Open Login Items…") {
                            controller.openLoginItemsSettings()
                        }
                    }
                }
            }

            FeedbackView(
                validationMessage: controller.options.validationError,
                errorMessage: controller.errorMessage
            )
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .onAppear {
            controller.refreshLoginItemStatus()
            controller.refreshRunningApplications()
        }
    }

    private var configurationIsLocked: Bool {
        controller.isRunning && controller.options.runUtility
    }
}

private struct RunningApplicationLabel: View {
    let application: RunningApplicationChoice

    var body: some View {
        HStack {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(application.name)
            if !application.isRunning {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pid: pid_t {
        pid_t(application.id)
    }
}

#Preview {
    SettingsView(controller: CaffeinateController(defaults: UserDefaults(suiteName: "SettingsPreview")!))
}
