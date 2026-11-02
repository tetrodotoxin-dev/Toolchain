# Copyright (c) 2023-present Matt Kaes and contributors

"""Cache the normalized, pinned Ubuntu target sysroot across workspaces."""

load("//source:sdk/normalize.bzl", "normalize_sdk")

GCC_DIRECTORY = "usr/lib/gcc/x86_64-linux-gnu/11"

def _extract_debian(ctx, archives):
    """Extract pinned packages into one Linux target sysroot.

    Args:
        ctx: Repository context receiving the target filesystem.
        archives: Package URLs mapped to their reviewed checksums.
    """
    for index, (url, checksum) in enumerate(archives.items()):
        directory = "archives/" + str(index)
        archive = directory + "/package.deb"
        ctx.download(url = url, sha256 = checksum, output = archive)
        ctx.extract(archive, output = directory)
        payload = [path for path in ctx.path(directory).readdir() if path.basename.startswith("data.tar.")]
        if len(payload) != 1:
            fail("Linux SDK package has no unique data archive: " + url)
        ctx.extract(payload[0])
        ctx.delete(directory)

# A fixed target sysroot keeps releases independent of the build machine's
# distribution. Ubuntu 22.04 supplies the existing glibc and libstdc++ model.
# The dated snapshot keeps every package available under its reviewed checksum.
def _sdk(ctx):
    """Assemble the Linux sysroot from pinned Debian packages.

    Args:
        ctx: Repository context with package pins and the sysroot normalizer.
    """
    packages = json.decode(ctx.read(ctx.attr._packages))
    _extract_debian(ctx, {
        "https://snapshot.ubuntu.com/ubuntu/20260925T000000Z/" + package["path"]: package["sha256"]
        for package in packages.values()
    })
    normalize_sdk(ctx, "linux")
    ctx.template("BUILD.bazel", ctx.attr._build)
    return ctx.repo_metadata(reproducible = True)

linux_sdk = repository_rule(implementation = _sdk, attrs = {
    "_build": attr.label(default = Label("//source/bazel:toolchains/linux/sdk.build")),
    "_packages": attr.label(default = Label("//source:sdk/linux.json")),
})

