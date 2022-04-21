# High Level Design

rules_xcodeproj has a few high level design goals:

- Only the `xcodeproj` rule is necessary to create a working project
- The project can be further customized by using additional rules_xcodeproj
  rules, or by returning certain rules_xcodeproj providers from custom rules
- All definition of a project exists in `BUILD` files
- The project can be configured to use either Xcode or Bazel as the build system

## Only the `xcodeproj` rule is necessary

If all one does is define an `xcodeproj` target, then the resulting project
should build and run. There should be no need to adjust the way your workspace
is built in any way, or define any additional intermediary targets.

Bazel allows for some pretty complicated stuff, and not all of it will
automatically translate neatly into Xcode's world. In those cases the project
should still build and run (see how in the [build mode](#multiple-build-modes)
section), but the project might not be in an ideal state (e.g. schemes might not
be the way you want them, or custom rule targets might not be represented
ideally). This can be addressed through project customization.

## Projects can be customized

As mentioned above, the default state of using just the `xcodeproj` rule might
result in a project that isn't "ideal". While the project should be able to
build and run without doing anything else, rules_xcodeproj will support project
customization through the use of additional rules and providers.

### Additional rules

At the bare minimum, the `xcodeproj` rule depends on the targets that you want
represented in the project. This will generate a project that allows you to
build, and if applicable run, those targets. If possible, all of the transitive
dependencies will also individually be buildable and runnable. Default schemes
will be created for each of these Xcode targets.

What if you don't like the way the schemes are created (e.g. too many, with
incorrect options, or not enough targets per scheme)? Or what if you don't want
all of the transitive dependencies represented in Xcode? Or what if you want to
customize how a target is represented, maybe by adding additional Xcode build
settings (e.g. to support
[XCRemoteCache](https://github.com/spotify/XCRemoteCache))?

These scenarios will be handled by additional rules that `xcodeproj` can depend
on to customize your project. The key characteristic of these rules is it gives
the project generator control over how their project is setup. This is in
contrast to the other customization point, providers.

### Providers

The core of the `xcodeproj` rule is the `xcodeproj_aspect` aspect, which
traverses the dependency graph of the targets passed to an `xcodeproj` instance.
The aspect collects information from providers of other rules (i.e.
[`CcInfo`](https://bazel.build/rules/lib/CcInfo),
[`SwiftInfo`](https://github.com/bazelbuild/rules_swift/blob/master/doc/providers.md#swiftinfo),
and various rules_apple providers), as well as information from its own
providers that it creates. The rule then uses that information to shape the
project that it generates.

The `xcodeproj` rule has to make some assumptions about the data it gets, as the
providers from other rules don't have the fidelity needed to perfectly recreate
a similar Xcode target. rules_xcodeproj will expose providers and associated
helper functions, to allow rules, including your own custom ones, to control how
the `xcodeproj` generates targets. The goal being that a default,
non-customized, project is as natural as possible. Rules that return
rules_xcodeproj providers can choose to expose customization points, similar to
the additional rules mentioned above, but that's not their primary purpose.

## All in `BUILD` files

The building blocks of a rules_xcodeproj project generation is the `xcodeproj`
rule and associated [customization rules](#additional-rules). Targets using
these rules are defined in `BUILD` files, and generating a project happens by
executing  `bazel run`. There is no need to create additional configuration
files, or to run additional commands.

Some setups might require something more dynamic, in particular when using the
focused project customization. For these cases the recommended approach, which
we might supply some optional tools for, is to dynamically generate `.bzl` files
with macros that create the required targets and use those in your `BUILD`
files.

## Multiple build modes

The `xcodeproj` rule will allow specifying a build mode that should be used by
the generated project. This will allow the project to build with Xcode instead
of Bazel, if that is desired.

Here are a few reasons one may want to build with
Xcode instead of Bazel:

- If a new, possibly beta, version of Xcode is released with a feature that
  Build with Bazel doesn't support yet, because one of Bazel, rules_apple,
  rules_swift, or rules_xcodeproj doesn't support it
- To work around a bug in Bazel, rules_apple, rules_swift, or rules_xcodeproj
- To compare Bazel and Xcode build system or build commands
- As a step when migrating to Bazel

### Build with Xcode

In the "Build with Xcode" mode, the generated project will let Xcode orchestrate
the build. Xcode Build Settings, target dependencies, etc. are all set up to
create a normal Xcode experience.

To ensure that the resulting build is as similar to a Bazel build as
possible, some things are done differently than a vanilla Xcode project. In
particular, `BUILT_PRODUCTS_DIR` is set to a nested folder, mirroring the layout
of `bazel-out/`, and various search paths are adjusted to account for this.

There are also aspects of a Bazel build that can't be neatly translated into an
Xcode concept (though updating rules to supply [rules_xcodeproj
providers](#providers) can help). One that will come up in nearly every project
is code generation. In these situations the project takes on a hybrid approach,
invoking `bazel build` for a portion of the build. The degree to which `bazel
build` needs to handle the build depends on the the rules involved.

Of note, the project can be customized to force more of it to be hybrid, through
the use of [focused project rules](#additional-rules).

### Build with Bazel

...

### Build with Bazel via Proxy

...

TODO: Why is it needed as an option? Why not the default?
