// swift-tools-version: 5.8

import Foundation
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
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"])
  ],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: [
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "DequeModule", package: "swift-collections"),
      ],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation", "AsyncAlgorithms_XCTest"],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
  ]
)

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ]
} else {
  package.dependencies += [
    .package(path: "../swift-collections")
  ]
}
