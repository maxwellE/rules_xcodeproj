import PathKit
import XcodeProj
import XCTest

@testable import generator

class CreateAutogeneratedXCSchemesTests: XCTestCase {
    enum BuildPreActionType {
        case set
        case remove
        case none
    }

    enum LaunchRunnableType {
        case target
        case remote(
            bundleIdentifier: String,
            runnableDebuggingMode: String,
            remotePath: String?
        )
        case none
    }

    enum LaunchMacroExpansionType {
        case target
        case host
        case none
    }

    let consolidatedTargetKeys = Fixtures.consolidatedTargets.keys

    let extensionPointIdentifiers = Fixtures.extensionPointIdentifiers

    let filePathResolver = FilePathResolver(
        internalDirectoryName: "rules_xcodeproj",
        workspaceOutputPath: "examples/foo/Foo.xcodeproj"
    )

    let pbxTargetsDict: [ConsolidatedTarget.Key: PBXTarget] =
        Fixtures.pbxTargets(
            in: Fixtures.pbxProj(),
            consolidatedTargets: Fixtures.consolidatedTargets
        )
        .0

    let targetHosts = Fixtures.project.targetHosts

    func assertScheme(
        schemesDict: [String: XCScheme],
        targetKey: ConsolidatedTarget.Key,
        hostTargetKey: ConsolidatedTarget.Key? = nil,
        hostIndex: Int? = nil,
        buildPreActions: BuildPreActionType,
        launchRunnable: LaunchRunnableType,
        launchMacroExpansion: LaunchMacroExpansionType,
        shouldExpectBuildActionEntries: Bool,
        shouldExpectTestables: Bool,
        shouldExpectLaunchEnvVariables: Bool,
        expectedWasCreatedForAppExtension: Bool? = nil,
        expectedSelectedDebuggerIdentifier: String = XCScheme.defaultDebugger,
        expectedSelectedLauncherIdentifier: String = XCScheme.defaultLauncher,
        expectedLaunchAutomaticallySubstyle: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard let target = pbxTargetsDict[targetKey] else {
            XCTFail(
                "Did not find the target '\(targetKey)'",
                file: file,
                line: line
            )
            return
        }
        let schemeName = target.schemeName
        guard let scheme = schemesDict[schemeName] else {
            XCTFail(
                "Did not find a scheme named \(schemeName)",
                file: file,
                line: line
            )
            return
        }

        let hostTarget: PBXTarget?
        if let hostTargetKey = hostTargetKey {
            guard let aTarget = pbxTargetsDict[hostTargetKey] else {
                XCTFail(
                    "Did not find the host target '\(hostTargetKey)'",
                    file: file,
                    line: line
                )
                return
            }
            hostTarget = aTarget
        } else {
            hostTarget = nil
        }

        // Expected values

        let expectedBuildConfigurationName = target.defaultBuildConfigurationName
        let expectedBuildableReference = try target.createBuildableReference(
            referencedContainer: filePathResolver.containerReference
        )
        let expectedHostBuildableReference = try hostTarget?
            .createBuildableReference(
                referencedContainer: filePathResolver.containerReference
            )

        let expectedLaunchRunnable: XCScheme.Runnable?
        switch launchRunnable {
        case .target:
            expectedLaunchRunnable = XCScheme.BuildableProductRunnable(
                buildableReference: expectedBuildableReference
            )
        case let .remote(bundleIdentifier, runnableDebuggingMode, remotePath):
            expectedLaunchRunnable = XCScheme.RemoteRunnable(
                buildableReference: expectedBuildableReference,
                bundleIdentifier: bundleIdentifier,
                runnableDebuggingMode: runnableDebuggingMode,
                remotePath: remotePath
            )
        case .none:
            expectedLaunchRunnable = nil
        }

        let expectedLaunchMacroExpansion: XCScheme.BuildableReference?
        switch launchMacroExpansion {
        case .target:
            expectedLaunchMacroExpansion = expectedBuildableReference
        case .host:
            expectedLaunchMacroExpansion = expectedHostBuildableReference
        case .none:
            expectedLaunchMacroExpansion = nil
        }

        let expectedBuildActionEntries: [XCScheme.BuildAction.Entry] =
            shouldExpectBuildActionEntries ?
            [
                .init(
                    buildableReference: expectedBuildableReference,
                    buildFor: [
                        .running,
                        .testing,
                        .profiling,
                        .archiving,
                        .analyzing,
                    ]
                ),
                expectedHostBuildableReference.map { buildableReference in
                    .init(
                        buildableReference: buildableReference,
                        buildFor: [
                            .running,
                            .testing,
                            .profiling,
                            .archiving,
                            .analyzing,
                        ]
                    )
                },
            ].compactMap { $0 } : []

        let expectedTestables: [XCScheme.TestableReference] =
            shouldExpectTestables ?
            [.init(
                skipped: false,
                buildableReference: expectedBuildableReference
            )] : []

        let expectedCustomLLDBInitFile = "$(BAZEL_LLDB_INIT)"

        let expectedBuildPreActions: [XCScheme.ExecutionAction]
        switch buildPreActions {
        case .set:
            let hostTargetOutputGroup: String
            if let hostIndex = hostIndex {
                hostTargetOutputGroup = #"""
echo "b $BAZEL_HOST_TARGET_ID_\#(hostIndex)" >> "$BAZEL_BUILD_OUTPUT_GROUPS_FILE"
"""#
            } else {
                hostTargetOutputGroup = ""
            }

            expectedBuildPreActions = [.init(
                scriptText: #"""
mkdir -p "${BAZEL_BUILD_OUTPUT_GROUPS_FILE%/*}"
echo "b $BAZEL_TARGET_ID" > "$BAZEL_BUILD_OUTPUT_GROUPS_FILE"
\#(hostTargetOutputGroup)
"""#,
                title: "Set Bazel Build Output Groups",
                environmentBuildable: expectedBuildableReference
            )]
        case .remove:
            expectedBuildPreActions = [.init(
                scriptText: #"""
if [[ -s "$BAZEL_BUILD_OUTPUT_GROUPS_FILE" ]]; then
    rm "$BAZEL_BUILD_OUTPUT_GROUPS_FILE"
fi

"""#,
                title: "Set Bazel Build Output Groups",
                environmentBuildable: expectedBuildableReference
            )]
        case .none:
            expectedBuildPreActions = []
        }

        let expectedLaunchEnvVariables: [XCScheme.EnvironmentVariable]? =
            shouldExpectLaunchEnvVariables ? .bazelLaunchVariables : nil

        // Assertions

        XCTAssertNotNil(
            scheme.lastUpgradeVersion,
            file: file,
            line: line
        )
        XCTAssertNotNil(
            scheme.version,
            file: file,
            line: line
        )
        XCTAssertEqual(
            scheme.wasCreatedForAppExtension,
            expectedWasCreatedForAppExtension,
            "wasCreatedForAppExtension did not match for \(scheme.name)",
            file: file,
            line: line
        )

        guard let buildAction = scheme.buildAction else {
            XCTFail(
                "Expected a build action for \(scheme.name)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(
            buildAction.preActions,
            expectedBuildPreActions,
            "preActions did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            buildAction.buildActionEntries,
            expectedBuildActionEntries,
            "buildActionEntries did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            buildAction.parallelizeBuild,
            "parallelizeBuild was not true for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            buildAction.buildImplicitDependencies,
            "buildImplicitDependencies was not true for \(scheme.name)",
            file: file,
            line: line
        )

        guard let testAction = scheme.testAction else {
            XCTFail(
                "Expected a test action for \(scheme.name)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertNil(
            testAction.macroExpansion,
            "testAction.macroExpansion was not nil for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            testAction.buildConfiguration,
            expectedBuildConfigurationName,
            "testAction.buildConfiguration did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            testAction.testables,
            expectedTestables,
            "testables did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            testAction.customLLDBInitFile,
            expectedCustomLLDBInitFile,
            "testAction.customLLDBInitFile did not match for \(scheme.name)",
            file: file,
            line: line
        )

        guard let launchAction = scheme.launchAction else {
            XCTFail(
                "Expected a launch action for \(scheme.name)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(
            launchAction.buildConfiguration,
            expectedBuildConfigurationName,
            """
the launch action buildConfiguration did not match for \(scheme.name)
""",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.runnable,
            expectedLaunchRunnable,
            "launchAction.runnable did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.macroExpansion,
            expectedLaunchMacroExpansion,
            "launchAction.macroExpansion did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.customLLDBInitFile,
            expectedCustomLLDBInitFile,
            "launchAction.customLLDBInitFile did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.environmentVariables,
            expectedLaunchEnvVariables,
            "launch environment variables did not match for \(scheme.name)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.selectedDebuggerIdentifier,
            expectedSelectedDebuggerIdentifier,
            """
selectedDebuggerIdentifier did not match for \(scheme.name)
""",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.selectedLauncherIdentifier,
            expectedSelectedLauncherIdentifier,
            """
selectedLauncherIdentifier did not match for \(scheme.name)
""",
            file: file,
            line: line
        )
        XCTAssertEqual(
            launchAction.launchAutomaticallySubstyle,
            expectedLaunchAutomaticallySubstyle,
            """
launchAction.launchAutomaticallySubstyle did not match for \(scheme.name)
""",
            file: file,
            line: line
        )

        guard let analyzeAction = scheme.analyzeAction else {
            XCTFail(
                "Expected an analyze action for \(scheme.name)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(
            analyzeAction.buildConfiguration,
            expectedBuildConfigurationName,
            """
the analyze action buildConfiguration did not match for \(scheme.name)
""",
            file: file,
            line: line
        )

        guard let archiveAction = scheme.archiveAction else {
            XCTFail(
                "Expected an archive action for \(scheme.name)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(
            archiveAction.buildConfiguration,
            expectedBuildConfigurationName,
            """
the archive action buildConfiguration did not match for \(scheme.name)
""",
            file: file,
            line: line
        )
        XCTAssertTrue(
            archiveAction.revealArchiveInOrganizer,
            "revealArchiveInOrganizer did not match for \(scheme.name)",
            file: file,
            line: line
        )
    }

    func test_createAutogeneratedXCSchemes_withNoTargets() throws {
        let schemes = try Generator.createAutogeneratedXCSchemes(
            schemeAutogenerationMode: .auto,
            buildMode: .xcode,
            targetHosts: [:],
            extensionPointIdentifiers: [:],
            filePathResolver: filePathResolver,
            consolidatedTargetKeys: [:],
            pbxTargets: [:]
        )
        let expected = [XCScheme]()
        XCTAssertEqual(schemes, expected)
    }

    func test_createAutogeneratedXCSchemes_withTargets_xcode() throws {
        let schemes = try Generator.createAutogeneratedXCSchemes(
            schemeAutogenerationMode: .auto,
            buildMode: .xcode,
            targetHosts: targetHosts,
            extensionPointIdentifiers: extensionPointIdentifiers,
            filePathResolver: filePathResolver,
            consolidatedTargetKeys: consolidatedTargetKeys,
            pbxTargets: pbxTargetsDict
        )
        // -1 since we don't create a scheme for WatchKit Extensions
        XCTAssertEqual(schemes.count, pbxTargetsDict.count - 1)

        let schemesDict = Dictionary(
            uniqueKeysWithValues: schemes.map { ($0.name, $0) }
        )

        // Non-native target
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: .bazelDependencies,
            buildPreActions: .none,
            launchRunnable: .none,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false
        )

        // Library
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "A 1",
            buildPreActions: .none,
            launchRunnable: .none,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false
        )

        // Launchable, testable
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "B 2",
            buildPreActions: .none,
            launchRunnable: .none,
            launchMacroExpansion: .target,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: true,
            shouldExpectLaunchEnvVariables: false
        )

        // Launchable, not testable
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "A 2",
            buildPreActions: .none,
            launchRunnable: .target,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false
        )

        // WatchOS App
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "W",
            hostTargetKey: "I",
            hostIndex: 0,
            buildPreActions: .none,
            launchRunnable: .target,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false
        )

        // WidgetKit Extension
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "WDKE",
            hostTargetKey: "I",
            hostIndex: 0,
            buildPreActions: .none,
            launchRunnable: .remote(
                bundleIdentifier: "com.apple.springboard",
                runnableDebuggingMode: "2",
                remotePath: nil
            ),
            launchMacroExpansion: .host,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false,
            expectedWasCreatedForAppExtension: true,
            expectedSelectedDebuggerIdentifier: "",
            expectedSelectedLauncherIdentifier: """
Xcode.IDEFoundation.Launcher.PosixSpawn
""",
            expectedLaunchAutomaticallySubstyle: "2"
        )
    }

    func assertBazelSchemes(
        schemes: [XCScheme],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // -1 since we don't create a scheme for WatchKit Extensions
        XCTAssertEqual(schemes.count, pbxTargetsDict.count - 1)

        let schemesDict = Dictionary(uniqueKeysWithValues: schemes.map { ($0.name, $0) })

        // Non-native target
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: .bazelDependencies,
            buildPreActions: .remove,
            launchRunnable: .none,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false,
            file: file,
            line: line
        )

        // Library
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "A 1",
            buildPreActions: .set,
            launchRunnable: .none,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: false,
            file: file,
            line: line
        )

        // Launchable, testable
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "B 2",
            buildPreActions: .set,
            launchRunnable: .none,
            launchMacroExpansion: .target,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: true,
            shouldExpectLaunchEnvVariables: true,
            file: file,
            line: line
        )

        // Launchable, not testable
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "A 2",
            buildPreActions: .set,
            launchRunnable: .target,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: true,
            file: file,
            line: line
        )

        // WatchOS App
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "W",
            hostTargetKey: "I",
            hostIndex: 0,
            buildPreActions: .set,
            launchRunnable: .target,
            launchMacroExpansion: .none,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: true,
            file: file,
            line: line
        )

        // WidgetKit Extension
        try assertScheme(
            schemesDict: schemesDict,
            targetKey: "WDKE",
            hostTargetKey: "I",
            hostIndex: 0,
            buildPreActions: .set,
            launchRunnable: .remote(
                bundleIdentifier: "com.apple.springboard",
                runnableDebuggingMode: "2",
                remotePath: nil
            ),
            launchMacroExpansion: .host,
            shouldExpectBuildActionEntries: true,
            shouldExpectTestables: false,
            shouldExpectLaunchEnvVariables: true,
            expectedWasCreatedForAppExtension: true,
            expectedSelectedDebuggerIdentifier: "",
            expectedSelectedLauncherIdentifier: """
Xcode.IDEFoundation.Launcher.PosixSpawn
""",
            expectedLaunchAutomaticallySubstyle: "2",
            file: file,
            line: line
        )
    }

    func test_createAutogeneratedXCSchemes_withTargets_bazel_withSchemeModeAuto() throws {
        let schemes = try Generator.createAutogeneratedXCSchemes(
            schemeAutogenerationMode: .auto,
            buildMode: .bazel,
            targetHosts: targetHosts,
            extensionPointIdentifiers: extensionPointIdentifiers,
            filePathResolver: filePathResolver,
            consolidatedTargetKeys: consolidatedTargetKeys,
            pbxTargets: pbxTargetsDict
        )
        try assertBazelSchemes(schemes: schemes)
    }

    func test_createAutogeneratedXCSchemes_withTargets_bazel_withSchemeModeAll() throws {
        let schemes = try Generator.createAutogeneratedXCSchemes(
            schemeAutogenerationMode: .all,
            buildMode: .bazel,
            targetHosts: targetHosts,
            extensionPointIdentifiers: extensionPointIdentifiers,
            filePathResolver: filePathResolver,
            consolidatedTargetKeys: consolidatedTargetKeys,
            pbxTargets: pbxTargetsDict
        )
        try assertBazelSchemes(schemes: schemes)
    }

    func test_createAutogeneratedXCSchemes_withTargets_bazel_withSchemeModeNone() throws {
        let schemes = try Generator.createAutogeneratedXCSchemes(
            schemeAutogenerationMode: .none,
            buildMode: .bazel,
            targetHosts: targetHosts,
            extensionPointIdentifiers: extensionPointIdentifiers,
            filePathResolver: filePathResolver,
            consolidatedTargetKeys: consolidatedTargetKeys,
            pbxTargets: pbxTargetsDict
        )
        XCTAssertEqual(schemes, [])
    }
}
