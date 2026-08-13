// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusChecker",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "StatusChecker",
            path: "Sources/StatusChecker"
        ),
        .testTarget(
            name: "StatusCheckerTests",
            dependencies: ["StatusChecker"],
            path: "Tests/StatusCheckerTests",
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                // Without Xcode, this CLT toolchain doesn't put swift-testing's
                // Testing.framework on the default search path the way `swift
                // test` expects; point at it explicitly so `import Testing`
                // resolves.
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                // The compile-time search path above doesn't carry over to
                // linking or to locating the dylibs at runtime — both need
                // their own flags. lib_TestingInterop.dylib (a dependency of
                // Testing.framework) lives in a second, separate directory.
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
