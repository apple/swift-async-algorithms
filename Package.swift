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
    .library(name: "MarbleDiagram", targets: ["MarbleDiagram"]),
    .library(name: "CMarbleDiagram", type: .static, targets: ["CMarbleDiagram"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "AsyncAlgorithms",
      dependencies: ["ClockStub"]),
    .target(name: "ClockStub"),
    .target(name: "MarbleDiagram", dependencies: ["CMarbleDiagram"]),
    .target(name: "CMarbleDiagram",
                publicHeadersPath: "Headers",
                cxxSettings: [
                  .unsafeFlags(["-std=c++11"])
                ]),
    .testTarget(
      name: "AsyncAlgorithmsTests",
      dependencies: ["AsyncAlgorithms", "MarbleDiagram"]),
  ]
)
