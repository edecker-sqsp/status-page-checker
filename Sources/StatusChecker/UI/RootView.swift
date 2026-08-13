import SwiftUI

/// Root of the popover: the two-tab panel (Status, Settings) described in the
/// spec.
struct RootView: View {
    @Bindable var settings: Settings
    @Bindable var monitor: StatusMonitor

    var body: some View {
        TabView {
            StatusTabView(monitor: monitor)
                .tabItem { Label("Status", systemImage: "circle.fill") }

            SettingsTabView(settings: settings, monitor: monitor)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding(12)
    }
}
