// swift-tools-version: 5.8

import PackageDescription
import CompilerPluginSupport

// Availability Macros
let availabilityTags = [_Availability("AsyncAlgorithms")]
let versionNumbers = ["1.0"]

// Availability Macro Utilities
enum _OSAvailability: String {
  // This should match the package's deployment target
  case alwaysAvailable = "macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0"
  // Use 10000 for future availability to avoid compiler magic around
  // the 9999 version number but ensure it is greater than 9999
  case future = "macOS 10000, iOS 10000, tvOS 10000, watchOS 10000"
}

struct _Availability {
  let name: String
  let osAvailability: _OSAvailability

  init(_ name: String, availability: _OSAvailability = .alwaysAvailable) {
    self.name = name
    self.osAvailability = availability
  }
}

let availabilityMacros: [SwiftSetting] = versionNumbers.flatMap { version in
  availabilityTags.map {
    .enableExperimentalFeature("AvailabilityMacro=\($0.name) \(version):\($0.osAvailability.rawValue)")
  }
}

let package = Package(
  name: "swift-async-algorithms",
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
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
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
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ]
} else {
  package.dependencies += [
    .package(path: "../swift-collections")
  ]
}
