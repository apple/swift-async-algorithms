// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "swift-async-algorithms",
  platforms: [
    .macOS("10.15"),
    .iOS("13.0"),
    .tvOS("13.0"),
    .watchOS("6.0"),
  ],
  products: [
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"]),
    .library(name: "AsyncSequenceValidation", targets: ["AsyncSequenceValidation"]),
    .library(name: "_CAsyncSequenceValidationSupport", type: .static, targets: ["AsyncSequenceValidation"]),
    .library(name: "AsyncAlgorithms_XCTest", targets: ["AsyncAlgorithms_XCTest"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: [.product(name: "Collections", package: "swift-collections")]
    ),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"]
    ),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"]
    ),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation", "AsyncAlgorithms_XCTest"]
    ),
  ]
)
