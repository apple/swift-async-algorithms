// swift-tools-version: 5.8

import PackageDescription
import CompilerPluginSupport

// Availability Macros

let availabilityMacros: [SwiftSetting] = [
  .enableExperimentalFeature("AvailabilityMacro=AsyncAlgorithms 1.0:macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0"),
  .enableExperimentalFeature("AvailabilityMacro=AsyncAlgorithms 1.1:macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0"),
]

let package = Package(
  name: "swift-async-algorithms",
  products: [
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"])
  ],
  targets: [
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(name: "_CPowSupport"),
    .target(
      name: "AsyncAlgorithms",
      dependencies: [
        "_CPowSupport",
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "DequeModule", package: "swift-collections"),
      ],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation", "AsyncAlgorithms_XCTest"],
      swiftSettings: availabilityMacros + [
        .enableExperimentalFeature("StrictConcurrency=complete")
      ]
    ),
  ]
)

if Context.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
  ]
} else {
  package.dependencies += [
    .package(path: "../swift-collections")
  ]
}
