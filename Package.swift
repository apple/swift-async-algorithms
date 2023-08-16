// swift-tools-version: 5.8

import PackageDescription

let package = Package(
  name: "swift-async-algorithms",
  platforms: [
    .macOS("10.15"),
    .iOS("13.0"),
    .tvOS("13.0"),
    .watchOS("6.0")
  ],
  products: [
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"]),
  ],
  dependencies: [.package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.4"))],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: [.product(name: "Collections", package: "swift-collections")],
      swiftSettings: [
          .enableExperimentalFeature("StrictConcurrency=complete"),
      ]
    ),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"],
      swiftSettings: [
          .enableExperimentalFeature("StrictConcurrency=complete"),
      ]
    ),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"],
      swiftSettings: [
          .enableExperimentalFeature("StrictConcurrency=complete"),
      ]
    ),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation", "AsyncAlgorithms_XCTest"],
      swiftSettings: [
          .enableExperimentalFeature("StrictConcurrency=complete"),
      ]
    ),
  ]
)

#if canImport(Darwin)
import Darwin
let buildingDocs = getenv("BUILDING_FOR_DOCUMENTATION_GENERATION") != nil
#elseif canImport(Glibc)
import Glibc
let buildingDocs = getenv("BUILDING_FOR_DOCUMENTATION_GENERATION") != nil
#else
let buildingDocs = false
#endif

// Only require the docc plugin when building documentation
package.dependencies += buildingDocs ? [
  .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
] : []
