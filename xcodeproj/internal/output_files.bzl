"""Module containing functions dealing with target output files."""

load(":output_group_map.bzl", "output_group_map")

# Utility

def _get_outputs(*, bundle_info, swift_info):
    build_outputs = []
    index_outputs = []

    if bundle_info:
        build_outputs.append(bundle_info.archive)

    if swift_info:
        for module in swift_info.direct_modules:
            swift = module.swift
            if not swift:
                continue
            index_outputs.append(swift.swiftdoc)
            index_outputs.append(swift.swiftmodule)
            build_outputs.append(swift.swiftmodule)
            if swift.swiftsourceinfo:
                index_outputs.append(swift.swiftsourceinfo)
            if swift.swiftinterface:
                index_outputs.append(swift.swiftinterface)

    return build_outputs, index_outputs

def _target_id_to_output_group_name(id):
    return id.replace("/", "_")

# API

def _collect(
        *,
        bundle_info,
        swift_info,
        id,
        transitive_infos):
    """Collects the outputs of a target.

    Args:
        bundle_info: The `AppleBundleInfo` provider for `target`, or `None`.
        swift_info: The `SwiftInfo` provider for the target, or `None`.
        id: A unique identifier for the target.
        transitive_infos: A list of `XcodeProjInfo`s for the transitive
            dependencies of the target.

    Returns:
        An opaque `struct` that should be used with
        `output_files.to_output_groups_fields` or `output_files.merge()`.
    """
    direct_build_outputs, direct_index_outputs = _get_outputs(
        bundle_info = bundle_info,
        swift_info = swift_info,
    )

    build_outputs = depset(
        direct_build_outputs,
        # TODO: Does this need to use `attrs_info.xcode_target`?
        transitive = [
            info.outputs._build_outputs
            for _, info in transitive_infos
        ],
    )
    index_outputs = depset(
        direct_index_outputs,
        # TODO: Does this need to use `attrs_info.xcode_target`?
        transitive = [
            info.outputs._index_outputs
            for _, info in transitive_infos
        ],
    )

    output_group_name = _target_id_to_output_group_name(id)

    return struct(
        _output_group_list = depset(
            [
                ("b {}".format(output_group_name), build_outputs),
                ("i {}".format(output_group_name), index_outputs),
            ],
            # TODO: Does this need to use `attrs_info.xcode_target`?
            transitive = [
                info.outputs._output_group_list
                for _, info in transitive_infos
            ],
        ),
        _build_outputs = build_outputs,
        _index_outputs = index_outputs,
    )

def _merge(*, transitive_infos):
    """Creates merged outputs.

    Args:
        transitive_infos: A list of `XcodeProjInfo`s for the transitive
            dependencies of the current target.

    Returns:
        A value similar to the one returned from `output_files.collect()`. The
        values include the outputs of the transitive dependencies, via
        `transitive_infos` (e.g. `generated` and `extra_files`).
    """
    return struct(
        _output_group_list = depset(
            # TODO: Does this need to use `attrs_info.xcode_target`?
            transitive = [
                info.outputs._output_group_list
                for _, info in transitive_infos
            ],
        ),
        _build_outputs = depset(
            # TODO: Does this need to use `attrs_info.xcode_target`?
            transitive = [
                info.outputs._build_outputs
                for _, info in transitive_infos
            ],
        ),
        _index_outputs = depset(
            # TODO: Does this need to use `attrs_info.xcode_target`?
            transitive = [
                info.outputs._index_outputs
                for _, info in transitive_infos
            ],
        ),
    )

def _to_output_groups_fields(*, ctx, outputs, toplevel_cache_buster):
    """Generates a dictionary to be splatted into `OutputGroupInfo`.

    Args:
        ctx: The rule context.
        outputs: A value returned from `output_files.collect()`.
        toplevel_cache_buster: A `list` of `File`s that change with each build,
            and are used as inputs to the output map generation, to ensure that
            the files references by the output map are always downloaded from
            the remote cache, even when using `--remote_download_toplevel`.

    Returns:
        A `dict` where the keys are output group names and the values are
        `depset` of `File`s.
    """
    return {
        name: depset([output_group_map.write_map(
            ctx = ctx,
            name = name,
            files = files,
            toplevel_cache_buster = toplevel_cache_buster,
        )])
        for name, files in outputs._output_group_list.to_list()
    }

output_files = struct(
    collect = _collect,
    merge = _merge,
    to_output_groups_fields = _to_output_groups_fields,
)
