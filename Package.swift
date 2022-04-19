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
    .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"]),
    .library(name: "AsyncSequenceValidation", targets: ["AsyncSequenceValidation"]),
    .library(name: "_CAsyncSequenceValidationSupport", type: .static, targets: ["AsyncSequenceValidation"]),
    .library(name: "AsyncAlgorithms_XCTest", targets: ["AsyncAlgorithms_XCTest"]),
  ],
  dependencies: [],
  targets: [
    .target(name: "AsyncAlgorithms"),
    .target(
      name: "AsyncSequenceValidation",
      dependencies: ["_CAsyncSequenceValidationSupport", "AsyncAlgorithms"]),
    .systemLibrary(name: "_CAsyncSequenceValidationSupport"),
    .target(
      name: "AsyncAlgorithms_XCTest",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation"],
      swiftSettings: [
        .unsafeFlags([
          "-Xfrontend", "-disable-availability-checking"
        ])
      ]),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "AsyncSequenceValidation", "AsyncAlgorithms_XCTest"],
      swiftSettings: [
        .unsafeFlags([
          "-Xfrontend", "-disable-availability-checking"
        ])
      ]),
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
