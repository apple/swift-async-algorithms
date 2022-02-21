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
    .library(name: "ClockStub", type: .static, targets: ["ClockStub"]),
    .library(name: "AsyncSequenceValidation", targets: ["AsyncSequenceValidation"]),
    .library(name: "_CAsyncSequenceValidationSupport", type: .static, targets: ["AsyncSequenceValidation"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: ["ClockStub"]),
    .target(name: "ClockStub"),
    .target(name: "AsyncSequenceValidation", dependencies: ["_CAsyncSequenceValidationSupport", "ClockStub"]),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"]),
  ]
)
