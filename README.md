# Toolchain

Toolchain gives Tetrodotoxin projects one opinionated definition of a project
and its SDK. Its goal is to automate every repeatable quality decision across
separate projects with different technical requirements. Each project retains
its own architecture and supported targets while sharing the same code quality
infrastructure across local development and published SDKs.

Tetrodotoxin's requirements define Toolchain's primary direction. Independent
C and C++ projects can use the same public Bazel interface, project structure
and release guarantees.

## Using Toolchain

To use Toolchain, create a `MODULE.bazel` that pins the release you want. Start
with the `MODULE.bazel` from any Tetrodotoxin project as a working example.
Register the targets your project supports, then load the required declarations
from [`defs.bzl`](defs.bzl). Toolchain supplies Linux, Windows and Web compiler
environments and builds static or shared component SDKs from the same project
model.

## Components and SDKs

Toolchain exposes canonical Bazel rules for compiling libraries and packaging
SDKs. Components drive those rules so source builds and binary SDKs expose the
same public module graph.

Components divide a library's public headers into modules with explicit
dependencies. Define one component map and load it from the source and root
BUILD files:

```starlark
COMPONENTS = {
    "core": [],
    "render": ["core"],
}
```

The `library()` rule compiles the implementation and creates a header interface
for each component. The `package()` rule publishes the selected static or shared
library and produces SDK archives from those interfaces. Pass the same map to
both rules. Each key names a directory under `source/<project>`, and each value
names the sibling components required by those headers.

The SDK records that component graph alongside each platform library. Consumers
use the [SDK module extension](source/bazel/sdk.bzl) to pin the header and
platform archives, choose static or shared linkage and declare SDK dependencies.
The extension recreates targets such as `@project//:render`; `sdks.component()`
attaches external dependencies required by an individual component.

A project can build against those imported targets and package its own SDK.
Toolchain carries their compatible link interface and runtime libraries into
the downstream release for every supported target.

## Development

Call `validation()` and `snapshot()` from the root `BUILD` file. Validation
links the project library and compiles the sources under `validation/tests` and
`validation/benchmarks` into the `:tests` and `:benchmarks` programs. Both
programs receive the artifacts under `validation/data`.

Repositories using Toolchain share this development workflow:

```sh
bazel run :format
bazel build ...
bazel run :tests
bazel run :benchmarks --config=release
bazel run :tests --config=web
```

The format target applies canonical source formatting, structural policy and
comment quality checks. The validation rule collects standalone test and
benchmark programs from their standard directories. The public programs select
the pinned Emscripten runtime and Node host when `--config=web` is requested,
while their explicit `_binary` targets retain the hosted SDK platform.

The recursive build covers the project while leaving release artifacts
explicit. Library projects build binary SDKs for every configured target with:

```sh
bazel build :sdk --config=release
```

Every project creates its source snapshot from a clean Git commit with:

```sh
bazel run :snapshot
```

The SDK contains public headers, libraries, runtime dependencies, metadata and
the license. The snapshot contains the complete committed repository so it can
rebuild the project and run its validation. Toolchain publishes only the
snapshot because Bazel consumes its Starlark and compiler declarations as
source.

For a full VS Code setup, run `bazel run :vscode` to generate a
Toolchain-compatible folder environment. It's optional but greatly
reduces editor integration setup.

Toolchain's implementation lives under [`source/bazel`](source/bazel), and
[`validation`](validation) exercises its public contract.

Toolchain uses the [MIT license](LICENSE).
