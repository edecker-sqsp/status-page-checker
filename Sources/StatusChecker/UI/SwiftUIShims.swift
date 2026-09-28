import SwiftUI

// The macOS 26+ SDK redeclares SwiftUI's `@State` as a compiler macro
// (SwiftUIMacros.StateMacro) whose plugin ships only with full Xcode, so on a
// Command-Line-Tools-only machine every `@State` fails to compile ("plugin for
// module 'SwiftUIMacros' not found"). The underlying property-wrapper struct —
// which the macro merely expands to — is still in the SDK, but a shadowing
// `typealias State` can't reclaim the name (attribute lookup prefers the
// macro), so views use this alias instead of `@State`.
typealias UIState<Value> = SwiftUI.State<Value>
