// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacMonitorControl",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "MacMonitorControl",
      targets: ["MacMonitorControl"]
    )
  ],
  targets: [
    .executableTarget(
      name: "MacMonitorControl"
    )
  ],
  swiftLanguageModes: [.v5]
)
