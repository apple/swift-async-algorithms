// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "AsyncAlgorithms",
  platforms: [
    .macOS("10.15"),
    .iOS("13.0"),
    .tvOS("13.0"),
    .watchOS("6.0")
  ],
  products: [
    .library(
      name: "AsyncAlgorithms",
      targets: ["AsyncAlgorithms"]),
  ],
  dependencies: [],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: []),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms"]),
  ]
)