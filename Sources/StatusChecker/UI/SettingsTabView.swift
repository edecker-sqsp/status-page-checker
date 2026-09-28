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

    // Drag-to-reorder state for the services list. Reordering is a manual
    // DragGesture rather than native drag-and-drop so we control the cursor
    // (open hand over the handle, closed hand while dragging) — a native drag
    // session owns the cursor and won't show either.
    @UIState private var draggedServiceID: UUID?
    @UIState private var dragTranslation: CGFloat = 0
    @UIState private var proposedIndex: Int?
    @UIState private var hoveredHandleID: UUID?
    @UIState private var rowFrames: [UUID: CGRect] = [:]

    private static let servicesSpace = "servicesList"
    private static let rowSpacing: CGFloat = 8

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
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            Text("Services").font(.headline)
            ForEach(settings.services) { config in
                serviceRow(for: config)
            }
        }
        .coordinateSpace(name: Self.servicesSpace)
        .onPreferenceChange(ServiceRowFramesKey.self) { frames in
            // Frames reported mid-drag include the reorder offsets (the
            // GeometryReader sits inside .offset), so they'd shift the hit
            // zones as rows animate out of the way. Only trust frames while
            // the list is at rest; all drag math runs against that snapshot.
            guard draggedServiceID == nil else { return }
            rowFrames = frames
        }
    }

    private func serviceRow(for config: ServiceConfig) -> some View {
        HStack(spacing: 10) {
            dragHandle(for: config)
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
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ServiceRowFramesKey.self,
                    value: [config.id: geo.frame(in: .named(Self.servicesSpace))]
                )
            }
        )
        .offset(y: rowOffset(for: config.id))
        .zIndex(draggedServiceID == config.id ? 1 : 0)
    }

    private func dragHandle(for config: ServiceConfig) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .onHover { inside in
                if inside {
                    hoveredHandleID = config.id
                } else if hoveredHandleID == config.id {
                    hoveredHandleID = nil
                }
                updateCursor()
            }
            .gesture(reorderGesture(for: config))
    }

    // MARK: Reordering

    private func reorderGesture(for config: ServiceConfig) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if draggedServiceID != config.id {
                    draggedServiceID = config.id
                    proposedIndex = index(of: config.id)
                    updateCursor()
                }
                dragTranslation = clampedTranslation(value.translation.height, for: config.id)
                if let target = targetIndex(), target != proposedIndex {
                    withAnimation(.easeInOut(duration: 0.15)) { proposedIndex = target }
                }
            }
            .onEnded { _ in
                let dragged = draggedServiceID
                let target = proposedIndex
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let dragged, let target {
                        settings.moveService(id: dragged, toIndex: target)
                    }
                    draggedServiceID = nil
                    proposedIndex = nil
                    dragTranslation = 0
                }
                updateCursor()
            }
    }

    private func index(of id: UUID) -> Int? {
        settings.services.firstIndex { $0.id == id }
    }

    /// While a drag is in flight the array itself doesn't change (the move
    /// commits on release) and `rowFrames` is frozen at the resting layout:
    /// the dragged row follows the pointer, and rows between its old and
    /// proposed slot shift one slot over to open a gap.
    private func rowOffset(for id: UUID) -> CGFloat {
        guard let draggedID = draggedServiceID,
              let from = index(of: draggedID),
              let target = proposedIndex else { return 0 }
        if id == draggedID { return dragTranslation }
        guard let myIndex = index(of: id),
              let draggedFrame = rowFrames[draggedID] else { return 0 }
        let step = draggedFrame.height + Self.rowSpacing
        if from < target, myIndex > from, myIndex <= target { return -step }
        if from > target, myIndex >= target, myIndex < from { return step }
        return 0
    }

    /// The slot whose band contains the dragged row's current center,
    /// top-to-bottom, clamped to the list's ends. Keying off the row's center
    /// (rather than the pointer) keeps the swap thresholds the same no matter
    /// where on the handle the drag was grabbed.
    private func targetIndex() -> Int? {
        guard let draggedID = draggedServiceID,
              let draggedFrame = rowFrames[draggedID] else { return nil }
        let frames = settings.services.compactMap { rowFrames[$0.id] }
        guard frames.count == settings.services.count, !frames.isEmpty else { return nil }
        let center = draggedFrame.midY + dragTranslation
        for (index, frame) in frames.enumerated() where center < frame.maxY + Self.rowSpacing / 2 {
            return index
        }
        return frames.count - 1
    }

    /// Keeps the dragged row from being pulled visually outside the list.
    private func clampedTranslation(_ raw: CGFloat, for id: UUID) -> CGFloat {
        let frames = settings.services.compactMap { rowFrames[$0.id] }
        guard let myFrame = rowFrames[id],
              let first = frames.first, let last = frames.last else { return raw }
        return min(max(raw, first.minY - myFrame.minY), last.maxY - myFrame.maxY)
    }

    /// Single source of truth for the pointer: closed hand while dragging,
    /// open hand over a handle, arrow otherwise. Called from every hover and
    /// drag transition so the states can't fight each other.
    private func updateCursor() {
        if draggedServiceID != nil {
            NSCursor.closedHand.set()
        } else if hoveredHandleID != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
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

/// Collects each service row's frame in the services-list coordinate space,
/// so the drag gesture can map pointer position to a slot index.
private struct ServiceRowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
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
