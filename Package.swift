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
    .library(name: "AsyncSequenceValidation", targets: ["AsyncSequenceValidation"]),
    .library(name: "_CAsyncSequenceValidationSupport", type: .static, targets: ["AsyncSequenceValidation"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "AsyncAlgorithms"),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport"],
      swiftSettings: [
        .unsafeFlags([
          "-Xfrontend", "-enable-experimental-pairwise-build-block"
        ])
      ]),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"],
      swiftSettings: [
        .unsafeFlags([
          "-Xfrontend", "-disable-availability-checking",
          "-Xfrontend", "-enable-experimental-pairwise-build-block"
        ])
      ]),
  ]
)
