# One producer can supply both variants under independent repository names.
sdks.release(
    name = "dependency_static",
    archives = {dependency_archives},
    library = "tetro_toolchain",
    linkage = "static",
    project = "Toolchain",
    version = "{version}",
)

sdks.release(
    name = "dependency_shared",
    archives = {dependency_archives},
    library = "tetro_toolchain",
    linkage = "shared",
    project = "Toolchain",
    version = "{version}",
)

use_repo(
    sdks,
    alternate = "dependency_{alternate_linkage}",
    dependency = "dependency_{dependency_linkage}",
)
