import SwiftUI
import AppKit

/// Second tab: poll interval, per-service enable/notify toggles, adding a
/// custom service, launch-at-login, and quit.
struct SettingsTabView: View {
    @Bindable var settings: Settings
    @Bindable var monitor: StatusMonitor

    @UIState private var intervalText: String = ""
    @FocusState private var intervalFieldFocused: Bool

    @UIState private var newServiceName = ""
    @UIState private var newServiceURL = ""
    @UIState private var isVerifying = false
    @UIState private var addServiceError: String?

    @UIState private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intervalSection
                Divider()
                servicesSection
                Divider()
                addServiceSection
                Divider()
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                Divider()
                quitButton
            }
            .padding(.vertical, 4)
        }
        .onAppear { intervalText = String(settings.intervalSeconds) }
        .onChange(of: intervalFieldFocused) { _, isFocused in
            if !isFocused { commitInterval() }
        }
    }

    // MARK: Interval

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Check interval").font(.headline)
            HStack {
                TextField("Seconds", text: $intervalText)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .focused($intervalFieldFocused)
                    .onSubmit(commitInterval)
                Text("seconds")
                Spacer()
            }
            Text("Minimum \(Settings.minimumIntervalSeconds) seconds.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func commitInterval() {
        guard let value = Int(intervalText.trimmingCharacters(in: .whitespaces)), value > 0 else {
            intervalText = String(settings.intervalSeconds)
            return
        }
        settings.setInterval(value)
        intervalText = String(settings.intervalSeconds)
        monitor.restart()
    }

    // MARK: Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Services").font(.headline)
            ForEach(settings.services) { config in
                ServiceConfigRow(
                    config: config,
                    onToggleEnabled: { newValue in
                        settings.updateService(id: config.id) { $0.enabled = newValue }
                        monitor.restart()
                    },
                    onToggleNotify: { newValue in
                        settings.updateService(id: config.id) { $0.notify = newValue }
                    },
                    onDelete: {
                        settings.removeService(id: config.id)
                        monitor.restart()
                    }
                )
            }
        }
    }

    // MARK: Add service

    private var addServiceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a service").font(.headline)
            TextField("Name (optional)", text: $newServiceName)
                .textFieldStyle(.roundedBorder)
            TextField("Status page URL", text: $newServiceURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit(verifyAndAdd)
            HStack {
                Button(action: verifyAndAdd) {
                    if isVerifying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Verify & Add")
                    }
                }
                .disabled(newServiceURL.trimmingCharacters(in: .whitespaces).isEmpty || isVerifying)
                Spacer()
            }
            if let addServiceError {
                Text(addServiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verifyAndAdd() {
        let urlString = newServiceURL
        let requestedName = newServiceName
        guard !urlString.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isVerifying = true
        addServiceError = nil
        Task { @MainActor in
            let outcome = await ProviderDetector.detect(urlString: urlString)
            isVerifying = false
            switch outcome {
            case .detected(let kind, let origin, let suggestedName):
                let trimmedName = requestedName.trimmingCharacters(in: .whitespaces)
                let finalName = trimmedName.isEmpty ? suggestedName : trimmedName
                settings.addService(ServiceConfig(name: finalName, pageURL: origin, kind: kind))
                monitor.restart()
                newServiceName = ""
                newServiceURL = ""
            case .rejected(let reason):
                addServiceError = reason
            }
        }
    }

    // MARK: Launch at login

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                let success = LoginItem.setEnabled(newValue)
                launchAtLogin = success ? newValue : LoginItem.isEnabled
            }
        )
    }

    private var quitButton: some View {
        HStack {
            Spacer()
            Button("Quit WDD") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct ServiceConfigRow: View {
    let config: ServiceConfig
    let onToggleEnabled: (Bool) -> Void
    let onToggleNotify: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                Text(config.pageURL.host ?? config.pageURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(spacing: 1) {
                Text("On").font(.caption2).foregroundStyle(.secondary)
                Toggle("Enabled", isOn: Binding(get: { config.enabled }, set: onToggleEnabled))
                    .labelsHidden()
            }
            VStack(spacing: 1) {
                Text("Notify").font(.caption2).foregroundStyle(.secondary)
                Toggle("Notify", isOn: Binding(get: { config.notify }, set: onToggleNotify))
                    .labelsHidden()
                    .disabled(!config.enabled)
                    .opacity(config.enabled ? 1 : 0.4)
            }
            if !config.isBuiltIn {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove \(config.name)")
            }
        }
    }
}
