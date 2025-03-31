"""Exposes targets used by `xcodeproj` to allow use in fixture tests."""

XCODEPROJ_TARGETS = [
    "@swiftpkg_swift_build//:swbuild",
]

SCHEME_AUTOGENERATION_MODE = "all"

XCSCHEMES = [
]

def get_xcode_schemes():
    return [
    ]

def get_extra_files():
    return [
    ]
