"""Module extension for loading dependencies not yet compatible with bzlmod."""

def non_bzlmod_dependencies():
    pass

non_module_deps = module_extension(implementation = lambda _: non_bzlmod_dependencies())
