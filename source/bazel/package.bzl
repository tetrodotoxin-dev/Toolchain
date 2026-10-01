# Copyright (c) 2023-present Matt Kaes and contributors

"""Package one project's source, headers and every target's linker outputs."""

load("@host_tools//:settings.bzl", "PYTHON")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_TARGETS = {
    "linux-x86_64-v3": str(Label("//:linux_x86_64")),
    "windows-x86_64-msvc": str(Label("//:windows_x64")),
    "wasm32-emscripten": str(Label("//:wasm32")),
}

# Bazel supplies the incoming settings even though every release selects opt.
# buildifier: disable=unused-variable
def _targets(settings, attr):
    """Select an optimized build for each SDK platform.

    Args:
        settings: Incoming build settings, unused by these release selections.
        attr: Packaging rule attributes selecting the published platforms.

    Returns:
        A dictionary mapping SDK platform names to their build settings.
    """
    return {name: {
        "//command_line_option:platforms": [platform],
        "//command_line_option:compilation_mode": "opt",
    } for name, platform in _TARGETS.items() if name in attr.platforms}

_transition = transition(
    implementation = _targets,
    inputs = [],
    outputs = ["//command_line_option:platforms", "//command_line_option:compilation_mode"],
)

def _binaries(target, project, linkage):
    """Select the target's link outputs and their release archive names.

    Args:
        target: Configured library target for one SDK platform.
        project: Published library name used for static archive filenames.
        linkage: Either static or shared, as declared by the packaging call.

    Returns:
        A binary, its optional import library and their archive basenames.
    """
    libraries = [library for entry in target[CcInfo].linking_context.linker_inputs.to_list() if entry.owner == target.label for library in entry.libraries]
    if len(libraries) != 1:
        fail("Release target must own exactly one library: " + str(target.label))
    library = libraries[0]
    if linkage == "static":
        # PIC archives can also be linked into a consumer's plugin. A distinct
        # Windows basename keeps the archive separate from the DLL's .lib.
        binary = library.pic_static_library or library.static_library
        if not binary:
            fail("Static release target supplies no archive: " + str(target.label))
        name = project + "_static.lib" if binary.extension == "lib" else "lib" + project + ".a"
        return struct(binary = binary, name = name, interface = None, interface_name = None)
    binary = library.resolved_symlink_dynamic_library or library.dynamic_library
    if not binary:
        fail("Shared release target supplies no shared library: " + str(target.label))
    interface = library.resolved_symlink_interface_library or library.interface_library
    if binary.extension == "dll" and not interface:
        fail("Windows shared release target supplies no import library: " + str(target.label))
    return struct(binary = binary, name = binary.basename, interface = interface, interface_name = binary.basename.removesuffix(".dll") + ".lib" if interface else None)

_PublicHeadersInfo = provider("Declared public header paths across ordinary dependencies.", fields = {"entries": "Declared header files and their public include paths."})

def _public_headers_impl(target, ctx):
    """Follow public header declarations without duplicating include aliases.

    Args:
        target: Configured dependency whose public interface is being visited.
        ctx: Aspect context exposing the rule's header and prefix declarations.

    Returns:
        Public header mappings, including mappings from ordinary dependencies.
    """
    if CcInfo not in target:
        return []
    context = target[CcInfo].compilation_context
    roots = context.includes.to_list() + context.system_includes.to_list() + context.quote_includes.to_list()
    roots = [root + "/" if root and root != "." else "" for root in roots]
    strip = getattr(ctx.rule.attr, "strip_include_prefix", "")
    prefix = getattr(ctx.rule.attr, "include_prefix", "")
    repository = target.label.workspace_root + "/" if target.label.workspace_root else ""
    package = target.label.package + "/" if target.label.package else ""
    strip_root = repository + (strip[1:] if strip.startswith("/") else package + strip)
    strip_root = strip_root.rstrip("/") + "/" if strip_root else ""
    headers = []
    for file in getattr(ctx.rule.files, "hdrs", []) + getattr(ctx.rule.files, "textual_hdrs", []) + context.direct_private_headers:
        if strip or prefix:
            if not file.path.startswith(strip_root):
                fail("Header is outside its declared strip_include_prefix: " + file.path)
            path = file.path[len(strip_root):]
            path = prefix.rstrip("/") + "/" + path if prefix else path
        else:
            prefixes = [root for root in roots if file.path.startswith(root)]
            if not prefixes:
                continue
            path = file.path[len(sorted(prefixes, key = len)[-1]):]
        headers.append((file, path))
    dependencies = getattr(ctx.rule.attr, "deps", [])
    actual = getattr(ctx.rule.attr, "actual", None)
    if actual:
        dependencies = dependencies + [actual]
    return [_PublicHeadersInfo(entries = depset(headers, transitive = [dep[_PublicHeadersInfo].entries for dep in dependencies if _PublicHeadersInfo in dep]))]

_public_headers = aspect(
    implementation = _public_headers_impl,
    attr_aspects = ["deps", "actual"],
)

def _headers(target):
    """Select the public headers owned by the released target's repository.

    Args:
        target: Configured library with declared public header mappings.

    Returns:
        File and include path pairs, with external SDK headers left to deps.
    """
    return [(file, path) for file, path in target[_PublicHeadersInfo].entries.to_list() if file.owner.workspace_root == target.label.workspace_root]

def _runtime(target, primary):
    """Collect declared shared dependencies beside the published library.

    Args:
        target: Configured library with transitive C++ linker inputs.
        primary: Published binary, already included by the release rule.

    Returns:
        Runtime library records and their [File, archive_path] pairs.
    """
    libraries = {}
    files = []
    for entry in target[CcInfo].linking_context.linker_inputs.to_list():
        for library in entry.libraries:
            binary = library.resolved_symlink_dynamic_library or library.dynamic_library
            if not binary or binary == primary:
                continue
            interface = library.resolved_symlink_interface_library or library.interface_library
            name = "lib/" + binary.basename
            import_name = "lib/" + binary.basename.removesuffix(".dll") + ".lib" if interface else None
            if binary.extension == "dll" and not interface:
                fail("Bundled Windows dependency supplies no import library: " + str(entry.owner))
            libraries[name] = {"library": name, "interface": import_name}
            files.append([binary, name])
            if interface:
                files.append([interface, import_name])
    return libraries.values(), files

def _package(ctx):
    """Write source, header and platform archives with a checksum manifest.

    Args:
        ctx: Rule context with source files and libraries split by platform.

    Returns:
        A list containing DefaultInfo for the archives and checksum file.
    """
    stem = ctx.attr.project + "-" + ctx.attr.version
    variants = {linkage: getattr(ctx.split_attr, linkage) for linkage in ["static", "shared"] if getattr(ctx.attr, linkage)}
    headers = {}
    for targets in variants.values():
        for target in targets.values():
            for file, path in _headers(target):
                if path in headers and headers[path] != file:
                    fail("Release variants supply different headers for " + path)
                headers[path] = file
    headers.setdefault("toolchain/export.h", ctx.file._export)
    license = [[file.path, "LICENSE"] for file in ctx.files.sources if file.short_path == "LICENSE"]
    archives = {
        stem + "-headers.zip": [[file.path, "include/" + path] for path, file in headers.items()] + license,
        stem + "-source.zip": [[file.path, file.short_path] for file in ctx.files.sources],
    }
    inputs = headers.values() + ctx.files.sources
    for linkage, targets in variants.items():
        for platform, target in targets.items():
            files = _binaries(target, ctx.attr.project, linkage)
            runtime, runtime_files = _runtime(target, files.binary)
            project = ctx.attr.project.upper().replace("-", "_").replace(".", "_")
            defines = target[CcInfo].compilation_context.defines.to_list()
            if linkage == "static" and project + "_STATIC=1" not in defines:
                fail("Static release project must match its static_library project: " + project)

            # Dependencies carry their own link requirements through SDK deps.
            # Export this target's flags once and preserve their ordering.
            linkopts = []
            for entry in target[CcInfo].linking_context.linker_inputs.to_list():
                if entry.owner == target.label:
                    # Toolchains can attach private link inputs, such as an
                    # empty Windows DEF file. Only consumer flags make those
                    # files a requirement of the imported SDK.
                    if any([file.path in flag for file in entry.additional_inputs for flag in entry.user_link_flags]):
                        fail("SDK link requirements need relocatable inputs; additional linker inputs are not packaged: " + str(target.label))
                    linkopts.extend(entry.user_link_flags)
            archive = stem + "-" + platform + "-" + linkage

            # Components select header interfaces over this library's binary.
            # Their compilation contexts include their public header dependencies
            # so SDK consumers receive the same complete include surface.
            components = {}
            for component, name in zip(ctx.split_attr.components.get(platform, []), ctx.attr.component_names):
                paths = {path: True for _, path in _headers(component)}
                paths["toolchain/export.h"] = True
                for path in paths:
                    if path not in headers:
                        fail("Component header is outside the released interface: " + path)
                components[name] = {
                    "headers": sorted(paths),
                    "defines": depset(component[CcInfo].compilation_context.defines.to_list() + ([project + "_STATIC=1"] if linkage == "static" else [])).to_list(),
                }
            metadata = ctx.actions.declare_file(archive + ".json")
            ctx.actions.write(metadata, json.encode({
                "project": project,
                "linkage": linkage,
                "library": "lib/" + files.name,
                "interface": "lib/" + files.interface_name if files.interface else None,
                "defines": defines,
                "linkopts": linkopts,
                "runtime": runtime,
                "components": components,
            }))
            members = [[file.path, path] for file, path in runtime_files] + [[files.binary.path, "lib/" + files.name], [metadata.path, "sdk.json"]]
            inputs.extend([file for file, _ in runtime_files])
            inputs.extend([files.binary, metadata])
            if files.interface:
                members.append([files.interface.path, "lib/" + files.interface_name])
                inputs.append(files.interface)
            archives[archive + ".zip"] = members + license
    outputs = [ctx.actions.declare_file(name) for name in archives]
    checksum = ctx.actions.declare_file(stem + "-sha256.txt")
    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(manifest, json.encode({output.path: archives[output.basename] for output in outputs}))
    ctx.actions.run(
        executable = PYTHON,
        arguments = [ctx.file._writer.path, manifest.path, checksum.path],
        inputs = depset(inputs + [manifest, ctx.file._writer]),
        outputs = outputs + [checksum],
        mnemonic = "PackageRelease",
    )
    return [DefaultInfo(files = depset(outputs + [checksum]))]

_package_release = rule(implementation = _package, attrs = {
    "static": attr.label(cfg = _transition, providers = [CcInfo], aspects = [_public_headers]),
    "shared": attr.label(cfg = _transition, providers = [CcInfo], aspects = [_public_headers]),
    "components": attr.label_list(cfg = _transition, providers = [CcInfo], aspects = [_public_headers]),
    "component_names": attr.string_list(),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "sources": attr.label_list(allow_files = True),
    "platforms": attr.string_list(mandatory = True),
    "_export": attr.label(default = Label("//source:toolchain/export.h"), allow_single_file = True),
    "_writer": attr.label(default = Label("//source/bazel:package.py"), allow_single_file = True),
    "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
})

def package(name = "sdk", module = None, components = [], static = None, shared = None, linkage = None, visibility = ["//visibility:public"], tags = ["manual"], **kwargs):
    """Publish a module's library, component interfaces and SDK target.

    The source package supplies //source:<module> and //source:<component>.
    Root component targets expose those header interfaces and link the common
    runtime. The SDK records the same interfaces for archive consumers.
    These declarations set their own visibility, so a root BUILD can load
    package directly without a separate native package declaration.

    Args:
        name: SDK target name, defaulting to sdk.
        module: Published library identity, defaulting to the Bazel module name.
        components: Component names whose header interfaces live in //source.
        static: Static runtime target. With neither variant supplied, the
            selected linkage uses //source:<module>.
        shared: Optional shared runtime target. Supply both variants to package
            both while selecting one for source consumers through linkage.
        linkage: Linkage used by root library and component consumers. Defaults
            to static when available, otherwise shared.
        visibility: Visibility of the published targets, defaulting to public.
        tags: SDK target tags. The default manual tag keeps cross compilation
            out of wildcard builds while permitting an explicit :sdk build.
        **kwargs: Additional release attributes such as platforms and sources.
    """
    module = module or native.module_name()
    linkage = linkage or ("shared" if shared and not static else "static")
    if linkage not in ["static", "shared"]:
        fail("package linkage must be static or shared")
    if not static and not shared:
        if linkage == "static":
            static = "//source:" + module
        else:
            shared = "//source:" + module
    runtime = static if linkage == "static" else shared
    if not runtime:
        fail("package requires a target for its selected " + linkage + " linkage")
    common = {key: kwargs[key] for key in ["testonly", "target_compatible_with", "compatible_with"] if key in kwargs}
    native.alias(name = module, actual = runtime, visibility = visibility, **common)
    definitions = [module.upper().replace("-", "_").replace(".", "_") + "_STATIC=1"] if linkage == "static" else []
    for component in components:
        cc_library(
            name = component,
            deps = ["//source:" + component],
            implementation_deps = [runtime],
            defines = definitions,
            visibility = visibility,
            **common
        )
    package_release(
        name = name,
        project = module,
        components = {"//source:" + component: component for component in components},
        static = static,
        shared = shared,
        visibility = visibility,
        tags = tags,
        **kwargs
    )

def package_release(name, static = None, shared = None, project = None, platforms = None, sources = None, components = {}, **kwargs):
    """Package static and shared libraries with common source and headers.

    Called from the repository root to collect its source packages and build
    each supplied target for the selected SDK platforms. Binary archives end
    in -static.zip or -shared.zip. Static Windows archives use _static.lib so
    they can share an installation directory with the DLL's import library.
    Each archive preserves public definitions and the target's linkopts.
    Declared transitive shared libraries and their import libraries accompany
    either linkage in lib/. System libraries supplied by the platform remain
    platform requirements. Static dependency archives retain separate SDK pins.
    The archive writer checks repeated filenames for identical contents, so
    conflicting libraries fail packaging instead of replacing one another.
    Linkopts must remain valid outside the build tree; linker scripts and other
    additional linker inputs require their own distribution support. Dependency
    SDKs provide their own link requirements through the importer's deps.

    Args:
        name: Release packaging target name.
        static: Optional static_library target. Supply at least one variant.
        shared: Optional shared_library target. Supply at least one variant.
        project: Published name and EXPORTED identifier before uppercasing,
            defaulting to the module name. Match the library macros' project.
        platforms: Platform names to publish, defaulting to all SDK platforms.
        sources: Source archive inputs. Omit at the repository root to collect
            its standard source packages and build configuration.
        components: Header interface targets mapped to public SDK target names.
            Each component links the release binary and exposes the selected
            target's public headers and definitions. These targets describe
            headers independently of the release's static or shared linkage.
        **kwargs: Common rule attributes such as visibility, tags and testonly.
    """
    if not static and not shared:
        fail("package_release requires a static or shared library")
    selected = _TARGETS.keys() if platforms == None else platforms
    if not selected or any([platform not in _TARGETS for platform in selected]):
        fail("platforms must select supported SDK platforms: " + str(_TARGETS.keys()))
    _package_release(
        name = name,
        static = static,
        shared = shared,
        components = components.keys(),
        component_names = components.values(),
        project = project or native.module_name(),
        platforms = selected,
        version = native.module_version(),
        sources = sources if sources != None else native.glob(["source/**", "validation/**"], allow_empty = True) + ["//" + package + ":sources" for package in native.subpackages(include = ["source", "validation", "tests", "benchmarks"], allow_empty = True)] + ["BUILD", "MODULE.bazel", "LICENSE", ".bazelrc", ".bazelversion", ".clang-format"],
        **kwargs
    )

def source_files(name = "sources"):
    """Collect package sources and the sources targets of descendant packages.

    Args:
        name: Filegroup target name, defaulting to the release's sources label.
    """
    native.filegroup(
        name = name,
        srcs = native.glob(["**"], allow_empty = True) + ["//" + native.package_name() + "/" + package + ":sources" for package in native.subpackages(include = ["**"], allow_empty = True)],
        visibility = ["//visibility:public"],
    )
