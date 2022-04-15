"""Module containing functions dealing with target output files."""

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
            if swift.swiftsourceinfo:
                index_outputs.append(swift.swiftsourceinfo)
            if swift.swiftinterface:
                index_outputs.append(swift.swiftinterface)

    return build_outputs, index_outputs

def _target_id_to_output_group_name(id):
    return id.replace("/", "_")

# Each "file" might actually represent many files (if the "file" is an output
# directory). This value was optimized around indexstores. The larger this value
# is, the higher the memory use of the `XcodeProjOutputsMap` action, and it
# forces more of the collection to happen at the end of the build, all at once.
# If this value is too small though, the overhead of too many actions slows
# things down. With a small enough value some actions will have to run
# sequentially, which lowers the concurrent burden.
_SHARD_SIZE = 75

def _write_sharded_output_maps(*, ctx, name, files, toplevel_cache_buster):
    files_list = files.to_list()
    length = len(files_list)
    shard_count = length // _SHARD_SIZE
    if length % _SHARD_SIZE != 0:
        shard_count += 1

    if shard_count < 2:
        return [
            _write_sharded_output_map(
                ctx = ctx,
                name = name,
                shard = None,
                shard_count = 1,
                files = files,
                toplevel_cache_buster = toplevel_cache_buster,
            ),
        ]

    shards = []
    for shard in range(shard_count):
        sharded_inputs = depset(
            files_list[shard * _SHARD_SIZE:(shard + 1) * _SHARD_SIZE],
        )
        shards.append(
            _write_sharded_output_map(
                ctx = ctx,
                name = name,
                shard = shard + 1,
                shard_count = shard_count,
                files = sharded_inputs,
                toplevel_cache_buster = toplevel_cache_buster,
            ),
        )

    return shards

def _write_sharded_output_map(
        *,
        ctx,
        name,
        shard,
        shard_count,
        files,
        toplevel_cache_buster):
    args = ctx.actions.args()
    args.use_param_file("%s", use_always = True)
    args.set_param_file_format("multiline")
    args.add_all(files, expand_directories = False)

    if shard:
        output_path = "shards/{}-{}.filelist".format(name, shard)
        progress_message = """\
Generating output map (shard {} of {}) for '{}'""".format(
            shard,
            shard_count,
            name,
        )
    else:
        output_path = "{}.filelist".format(name)
        progress_message = "Generating output map for '{}'".format(name)

    output = ctx.actions.declare_file(output_path)

    ctx.actions.run_shell(
        command = """
if [[ $OSTYPE == darwin* ]]; then
  cp -c \"$1\" \"$2\"
else
  cp \"$1\" \"$2\"
fi
""",
        arguments = [
            args,
            output.path,
        ],
        # Include files as inputs to cause them to be built or downloaded,
        # even if they aren't top level targets
        inputs = depset(toplevel_cache_buster, transitive = [files]),
        mnemonic = "XcodeProjOutputsMap",
        progress_message = progress_message,
        outputs = [output],
        execution_requirements = {
            # No need to cache, as it's super ephemeral
            "no-cache": "1",
            # No need for remote, as it takes no time, and we don't want the
            # remote executor to download all the inputs for nothing
            "no-remote": "1",
            # Disable sandboxing for speed
            "no-sandbox": "1",
        },
    )

    return output

def _write_output_map(*, ctx, name, files, toplevel_cache_buster):
    if files == None:
        files = depset()

    files_list = _write_sharded_output_maps(
        ctx = ctx,
        name = name,
        files = files,
        toplevel_cache_buster = toplevel_cache_buster,
    )
    if len(files_list) == 1:
        # If only one shared output map was generated, we use it as is
        return files_list[0]
    files = depset(files_list)

    args = ctx.actions.args()
    args.add_all(files)

    output = ctx.actions.declare_file(
        "{}.filelist".format(ctx.attr.name, name),
    )

    ctx.actions.run_shell(
        command = """
readonly output="$1"
shift
cat $@ > "$output"
""",
        arguments = [
            output.path,
            args,
        ],
        # Include files as inputs to cause them to be built or downloaded,
        # even if they aren't top level targets
        inputs = depset(toplevel_cache_buster, transitive = [files]),
        mnemonic = "XcodeProjOutputsMapMerge",
        progress_message = "Merging {} output map".format(name),
        outputs = [output],
        execution_requirements = {
            # No need to cache, as it's super ephemeral
            "no-cache": "1",
            # No need for remote, as it takes no time, and we don't want the
            # remote executor to download all the inputs for nothing
            "no-remote": "1",
            # Disable sandboxing for speed
            "no-sandbox": "1",
        },
    )

    return output

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

def _to_output_groups_fields(ctx, outputs, toplevel_cache_buster):
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
        name: depset([_write_output_map(
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
