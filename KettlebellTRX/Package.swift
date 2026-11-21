// swift-tools-version:5.9
// FitnessCore: plattformunabhängige Trainings-, Vitaldaten- und Integrationslogik.
// Wird von der iOS- und der watchOS-App eingebunden und ist unter macOS UND Linux testbar.
import PackageDescription

let package = Package(
    name: "KettlebellTRX",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "FitnessCore", targets: ["FitnessCore"]),
    ],
    targets: [
        .target(
            name: "FitnessCore",
            resources: [.process("Library/Resources")]
        ),
        .testTarget(
            name: "FitnessCoreTests",
            dependencies: ["FitnessCore"]
        ),
    ]
)
