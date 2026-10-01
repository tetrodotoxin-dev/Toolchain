# Static archives keep their separately versioned static dependencies.
sdks.release(
    name = "tetro_toolchain",
    project = "Toolchain",
    version = "{version}",
    linkage = "static",
    archives = {dependency_archives},
)
use_repo(sdks, fixture_dependency = "tetro_toolchain")
