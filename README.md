# Toolchain

Toolchain provides an opinionated all in one development toolchain for creating
cross platform SDKs using C/C++. Its goal is to automate every repeatable quality decision
across separate projects with different technical requirements while providing
portable infrastructure. The core infrastructure is built using Bazel.

Tetrodotoxin's requirements define Toolchain's primary direction. Independent
C and C++ projects can use the same public Bazel interface, project structure
and release guarantees.

## Using Toolchain

To use Toolchain, create a `MODULE.bazel` that pins the release you want. If you are
unfamiliar with Bazel start with the `MODULE.bazel` from any Tetrodotoxin project as
a working example. Toolchain provides all of it's own Skylark rules so you don't have 
to learn the full Skylark language to manage a Toolchain project. You can view all of
the required declarations in [`defs.bzl`](defs.bzl).

Toolchain supplies Linux, Windows and Web compiler environments and builds static
or shared component SDKs from the same project model. Toolchain includes it's own
in box testing and benchmark system, but you are more than welcome to configure your
own. If you are using Google Test and Google Benchmark they already have prepackaged
bazel repositories and are fairly easy to integrate:

 * [Google Test](https://registry.bazel.build/modules/googletest/)
 * [Google Benchmark](https://registry.bazel.build/modules/google_benchmark)

## Components and SDKs

Toolchain exposes canonical Bazel rules for compiling libraries and packaging
SDKs. Components drive those rules so source builds and binary SDKs expose the
same public module graph.

Components are used to divide a library's public headers into modules with 
explicit dependencies. The core configuration is loaded from the projects `source/BUILD`
file.

Components are stored as a dependency map. This example creates a `core` module and
a secondary `render` module that only has a local dependency on `core`:

```starlark
COMPONENTS = {
    "core": [],
    "render": ["core"],
}
```

The `library()` rule compiles the implementation and creates a header interface
for each component. The `package()` rule publishes the selected static or shared
library and produces SDK archives from those interfaces. Both rules should take the
same component map in almost all cases.

All code that is part of the SDK build, including private implementation details are
stored under `source/<project>/<component>/`. 

The SDK records that component graph alongside each platform library. Consumers
use the [SDK module extension](source/bazel/sdk.bzl) to pin the header and
platform archives, choose static or shared linkage and declare SDK dependencies.
The extension exports component targets for use by other Toolchain projects directly.
This allows targets to be more selective and minimize their export size but the main
benefit is it limits the number of public headers that need to be forwarded.
To include only the `render` component we defined above you can use `@project//:render`. 
When importing you can use `sdks.component()` to declare the external dependencies each component requires.

## Testing

Toolchain provides a `validation()` rule that enables testing. Similar to source code
validation code is stored under `validation/<type>/`. Validation supports both `tests`
and `benchmarks` for validation.

To keep the enviornment simple all tests are built as stand alone binary executables and
`bazel test ...` isn't supported by toolchain projects. This avoids several dependencies
such as Bash on Windows. To execute tests from the commandline use `bazel run :tests`
instead.

## Development

Call `validation()` and `snapshot()` from the root `BUILD` file. Validation
links the project library and compiles the sources under `validation/tests` and
`validation/benchmarks` into the `:tests` and `:benchmarks` programs. Both
programs receive the artifacts under `validation/data`.

Repositories using Toolchain share these core bazel commands:

```sh
# Perform a complete host local build (default is --config=debug)
bazel build ...
bazel build ... --config=release

# Format and validate code standards for the entire repository
bazel run :format

# Runs all tests for the repository for all modules
bazel run :tests

# Runs all benchmarks for the repository (make sure to use release when not debugging)
bazel run :benchmarks --config=release

# Most hosts can also run tests for other configurations with the most common being Web.
bazel run :tests_web
bazel run :benchmarks_web
```

## Release gates

Along with standard tests, Toolchain provides a `:format` command canonicalizes the code
and does it's best to cover code styling and standardization that clang-format can't catch.
It attempts to apply as many fixes as possible automatically and should be run frequently. 
Harder to catch cases like common problematic comment patterns use a classifier.

**Code must clear all `:format` checks including warnings before merging into `main`.**

### Oneshot release packaging

The recursive build command `bazel build ...` can be used to build all artifacts for the current host's target platform.
This makes it easy to run local tests and iterate without the overhead of release packaging.
For a full release Toolchain provides `bazel build :sdk`.

Running the command in release will build and package release artifacts for every target:

```sh
bazel build :sdk --config=release
```

The SDK contains public headers, libraries, runtime dependencies, metadata and
the license. Everything is packaged in one shot to make distribution setup easy.

> [!WARNING]
> Cross platform builds are supported, but executing Windows tests still requires a dedicated
> requires a dedicated Windows host environment.

Every project additionally can create a source snapshot from a clean Git commit with:

```sh
bazel run :snapshot
```

The snapshot contains the complete committed repository and should be provided
with the SDK for any published builds. Binaries built from the Source should generate
the exact hashes provided by the SDK.

### Toolchain releases

Toolchain only ships a snapshot since Bazel consumes its Starlark and compiler declarations
as source. Toolchain provides extra integration tests for validating the toolchain itself by
preforming a mock SDK release.

It can be run with a single command as well in place of `:sdk`:

```sh
bazel run //validation/integration:integration
```

## Human workflows

Even if contributors are using agents all workflows across all Tetrodotoxin projects
must provide an accessable method for humans to develop directly. By default Tetrodotoxin
provides a VS Code workflow since it streamlines cross platform development.


For a full VS Code setup, run `bazel run :vscode` to generate a
Toolchain compatible folder environment. It's optional but greatly
reduces editor integration setup.

Toolchain's implementation lives under [`source/bazel`](source/bazel), and
[`validation`](validation) exercises its public contract.

Toolchain uses the [MIT license](LICENSE).
