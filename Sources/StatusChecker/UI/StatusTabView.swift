import SwiftUI

/// First tab: every monitored service, worst-first, with a description and a
/// link back to the real status page.
struct StatusTabView: View {
    @Bindable var monitor: StatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.reports.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No services enabled")
                        .foregroundStyle(.secondary)
                    Text("Turn one on in Settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(monitor.sortedReports) { report in
                            ServiceRow(report: report)
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack {
            if let lastChecked = monitor.lastChecked {
                Text("Last checked \(lastChecked.formatted(date: .omitted, time: .standard))")
            } else {
                Text("Checking…")
            }
            Spacer()
            if monitor.isChecking {
                ProgressView().controlSize(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(hasUnknown ? .orange : .secondary)
        .padding(.top, 6)
    }

    private var hasUnknown: Bool {
        monitor.reports.contains { $0.health == .unknown }
    }
}

private struct ServiceRow: View {
    let report: ServiceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(report.health.emoji)
                Text(report.name)
                    .font(.headline)
                Text(report.health.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: report.pageURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open \(report.name) status page")
            }

            if !report.description.isEmpty {
                Text(report.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if report.health.isProblem, !report.affectedComponents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.affectedComponents) { component in
                        HStack(spacing: 4) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(component.name)
                            Text(component.statusLabel)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }
}
