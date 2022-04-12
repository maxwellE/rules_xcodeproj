import PathKit

struct FilePathResolver: Equatable {
    enum VariableMode {
        case buildSetting
        case script
        case none
    }

    let externalDirectory: Path
    let generatedDirectory: Path
    let internalDirectoryName: String
    private let workspaceOutputPath: Path

    init(
        externalDirectory: Path,
        generatedDirectory: Path,
        internalDirectoryName: String,
        workspaceOutputPath: Path
    ) {
        self.externalDirectory = externalDirectory
        self.generatedDirectory = generatedDirectory
        self.internalDirectoryName = internalDirectoryName
        self.workspaceOutputPath = workspaceOutputPath
    }

    var internalDirectory: Path {
        return workspaceOutputPath + internalDirectoryName
    }

    func resolve(
        _ filePath: FilePath,
        useBuildDir: Bool = true,
        useOriginalGeneratedFiles: Bool = false,
        variableMode: VariableMode = .buildSetting
    ) -> Path {
        let projectDir: Path
        switch variableMode {
        case .buildSetting:
            projectDir = "$(PROJECT_DIR)"
        case .script:
            projectDir = "$PROJECT_DIR"
        case .none:
            projectDir = ""
        }

        switch filePath.type {
        case .project:
            return projectDir + filePath.path
        case .external:
            let path = externalDirectory + filePath.path
            if path.isRelative {
                return projectDir + path
            } else {
                return path
            }
        case .generated:
            if useOriginalGeneratedFiles {
                let path = generatedDirectory + filePath.path
                if path.isRelative {
                    return projectDir + path
                } else {
                    return path
                }
            } else if useBuildDir {
                let buildDir: Path
                switch variableMode {
                case .buildSetting:
                    buildDir = "$(BUILD_DIR)"
                case .script:
                    buildDir = "$BUILD_DIR"
                case .none:
                    buildDir = ""
                }
                return buildDir + "bazel-out" + filePath.path
            } else {
                let projectFilePath: Path
                switch variableMode {
                case .buildSetting:
                    projectFilePath = "$(PROJECT_FILE_PATH)"
                case .script:
                    projectFilePath = "$PROJECT_FILE_PATH"
                case .none:
                    projectFilePath = ""
                }
                return projectFilePath + internalDirectoryName + "gen_dir" +
                    filePath.path
            }
        case .internal:
            return projectDir + internalDirectory + filePath.path
        }
    }
}
