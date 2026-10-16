import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var controller: CaffeinateController
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeader(controller: controller)
                .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Duration") {
                    Picker("Duration", selection: $controller.awakeDuration) {
                        ForEach(AwakeDuration.allCases.filter { $0 != .custom }) { duration in
                            Text(duration.title).tag(duration)
                        }
                        if controller.awakeDuration == .custom {
                            Text(controller.customDurationDescription).tag(AwakeDuration.custom)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                Toggle("Keep displays awake", isOn: $controller.options.preventDisplaySleep)
                Toggle("Keep Mac awake while idle", isOn: $controller.options.preventIdleSystemSleep)

                FeedbackView(
                    validationMessage: controller.options.validationError,
                    errorMessage: controller.errorMessage
                )
            }
            .disabled(controller.isRunning && controller.options.runUtility)
            .padding(16)

            Divider()

            HStack {
                Button {
                    openSettings()
                    NSApp.activate()
                } label: {
                    Label("Settings…", systemImage: "gear")
                }
                Spacer()
                Button("Quit", action: quit)
                    .keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: 340)
        .onAppear {
            controller.refreshLoginItemStatus()
            controller.refreshRunningApplications()
        }
    }
}

private struct MenuBarHeader: View {
    @Bindable var controller: CaffeinateController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: controller.isRunning ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.title)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacAwake")
                    .font(.headline)
                Text(controller.isStopping ? "Stopping…" : controller.isRunning ? "Caffeinate is on" : "Caffeinate is off")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(controller.isRunning ? "Stop" : "Start") {
                controller.toggle()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(controller.isStopping)
        }
    }
}

struct FeedbackView: View {
    let validationMessage: String?
    let errorMessage: String?

    var body: some View {
        if let message = errorMessage ?? validationMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    MenuBarView(
        controller: CaffeinateController(defaults: UserDefaults(suiteName: "MenuBarPreview")!),
        quit: {}
    )
}
