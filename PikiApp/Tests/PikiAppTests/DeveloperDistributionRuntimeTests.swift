import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Developer distribution runtime")
struct DeveloperDistributionRuntimeTests {
    @Test
    func developmentProjectRootUsesEnvironmentOverrideWhenPyprojectExists() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "piki-project-root-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "".write(to: tempRoot.appending(path: "pyproject.toml"), atomically: true, encoding: .utf8)

        let projectRoot = LocalServiceManager.developmentProjectRoot(
            environment: ["PIKI_REPO_ROOT": tempRoot.path(percentEncoded: false)],
            currentDirectoryURL: nil,
            fileManager: .default,
            sourceFileURL: URL(fileURLWithPath: "/tmp/missing-source.swift")
        )

        #expect(projectRoot == tempRoot)
    }

    @Test
    func prepareManagedRuntimeEnvironmentCreatesExpectedDirectories() throws {
        let pikiHome = FileManager.default.temporaryDirectory
            .appending(path: "piki-home-\(UUID().uuidString)", directoryHint: .isDirectory)

        LocalServiceManager.prepareManagedRuntimeEnvironment(at: pikiHome, fileManager: .default)

        #expect(FileManager.default.fileExists(atPath: pikiHome.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: pikiHome.appending(path: "claude-runtime").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: pikiHome.appending(path: "task-staging").path(percentEncoded: false)))
    }

    @Test
    func terminateProcessStopsSpawnedChild() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 30"]

        try process.run()
        #expect(process.isRunning)

        LocalServiceManager.terminateProcess(process, gracePeriod: 0.2)

        #expect(process.isRunning == false)
    }

    @Test
    func managedServiceEnvironmentEnablesRuntimeAndPrefersBundledSitePackages() {
        let pikiHome = URL(fileURLWithPath: "/tmp/piki-home", isDirectory: true)
        let pythonURL = URL(fileURLWithPath: "/tmp/PikiRuntime/Python/bin/python3")
        let bundleRuntime = RuntimeBundleConfiguration(
            pythonURL: pythonURL,
            sitePackagesURL: URL(fileURLWithPath: "/tmp/PikiRuntime/site-packages", isDirectory: true)
        )

        let environment = LocalServiceManager.managedServiceEnvironment(
            baseEnvironment: ["PYTHONPATH": "/existing/site-packages"],
            pikiHome: pikiHome,
            pythonURL: pythonURL,
            bundleRuntime: bundleRuntime
        )

        #expect(environment["PIKI_APP_MANAGED_SERVICE"] == "1")
        #expect(environment["PIKI_ENABLE_AGENT_RUNTIME"] == "1")
        #expect(environment["PIKI_APP_RUNTIME_SOURCE"] == "bundle")
        #expect(environment["CLAUDE_CONFIG_DIR"] == "/tmp/piki-home/claude-runtime")
        #expect(environment["PIKI_TASK_STAGING_ROOT"] == "/tmp/piki-home/task-staging")
        #expect(environment["PYTHONPATH"] == "/tmp/PikiRuntime/site-packages:/existing/site-packages")
    }
}
