# Copyright (c) 2023-present Matt Kaes and contributors

"""Canonical release identities and root labels for supported targets.

SDK import, release packaging and consumer selection use this same mapping, so
an archive name always identifies one configuration condition and one platform.
"""

PLATFORMS = {
    "linux-x86_64-v3": struct(
        condition = Label("//:linux"),
        platform = Label("//:linux_x86_64"),
    ),
    "wasm32-emscripten": struct(
        condition = Label("//:web"),
        platform = Label("//:wasm32"),
    ),
    "windows-x86_64-msvc": struct(
        condition = Label("//:windows"),
        platform = Label("//:windows_x64"),
    ),
}
