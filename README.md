# mise-env-lmod

A [mise](https://mise.jdx.dev) environment plugin that loads
[Lmod](https://lmod.readthedocs.io) modules when you enter a project
directory, and unloads them when you leave.

This is useful on HPC systems where building a project needs a set of
modules loaded (compilers, MPI, HDF5, NetCDF, ...). Declare them once in the
project's `mise.toml` and they're loaded automatically on `cd`.

## Requirements

- mise with shell activation (`mise activate`) in a supported shell: bash,
  zsh, fish, nu, xonsh, elvish or PowerShell
- Lmod initialized in your shell, so that `LMOD_CMD` is set

Tested with mise 2026.9.17 and Lmod on HPE Cray EX (Cray PE).

## Installation

```sh
mise plugin install lmod https://github.com/underwoo/mise-env-lmod
```

To pin a release, append the tag:

```sh
mise plugin install lmod https://github.com/underwoo/mise-env-lmod#v0.1.1
```

> [!IMPORTANT]
> Install the plugin *before* entering a directory whose config uses it.
> mise does not auto-install environment plugins, and while a config
> references a missing env plugin every mise command in that directory
> fails, including `mise plugin install`. If you're already in such a
> directory, run the install relative to another directory:
>
> ```sh
> mise --cd ~ plugin install lmod https://github.com/underwoo/mise-env-lmod
> ```

## Usage

In the project's `mise.toml` (or `.mise.toml`):

```toml
[env]
_.lmod = { modules = ["cray-hdf5", "cray-netcdf"] }
```

Adding the plugin's source under `[plugins]` is recommended. It tells
people (and mise) where the plugin comes from: without it, a missing plugin
fails with the unhelpful error `relative URL without a base`; with it, mise
reports `[lmod] plugin not installed` along with the repository URL.

```toml
[plugins]
lmod = "https://github.com/underwoo/mise-env-lmod"

[env]
_.lmod = { modules = ["cray-hdf5", "cray-netcdf"] }
```

`modules` may be a single string or a list. Modules are loaded in the order
given, exactly as `module load` would.

Then, from a shell with `mise activate`:

```console
$ cd my-project
$ echo $HDF5_ROOT
/opt/cray/pe/hdf5/1.14.3.7/intel/2025.0
$ module list        # shows cray-hdf5 as loaded
$ cd ..
$ echo $HDF5_ROOT    # unset again
```

Without shell activation (scripts, CI, or unsupported shells such as
csh/tcsh), run commands through mise instead:

```sh
mise exec -- make
```

## How it works

The plugin runs Lmod in a throw-away `/bin/sh` subprocess:

1. unloads the requested modules (so the result does not depend on whether
   they're already loaded),
2. records the environment,
3. runs `module load <modules>`,
4. records the environment again.

Every variable that changed is returned to mise, including `MODULEPATH`,
`LOADEDMODULES` and Lmod's `_ModuleTable*` state, so `module list` stays
accurate. New `PATH` entries are returned through the `MisePath` hook. mise
then applies the changes in your shell's own syntax and reverts them when
you leave the directory.

If a module fails to load (for example, a misspelled name), Lmod's error
message is shown as a mise warning and no changes are applied.

## Limitations

- **Swapping modules:** mise can only prepend to `PATH`. If loading a module
  swaps out another (e.g. `PrgEnv-gnu` replacing `PrgEnv-intel`), the old
  module's directories remain later in `PATH`. All other variables are set
  correctly.
- **Performance:** each evaluation runs Lmod, typically well under a second.
  mise only re-evaluates when the directory or config changes, not on every
  prompt.
- **`unset` variables:** variables that a module unsets are left unchanged.

## Updating

```sh
mise plugin update lmod
```

## Development

This plugin is based on
[jdx/mise-env-plugin-template](https://github.com/jdx/mise-env-plugin-template).

```sh
# Use a local checkout as the installed plugin
mise plugin link --force lmod /path/to/mise-env-lmod

# Install development tools
mise install

# Run linters (lua-language-server, stylua, actionlint)
mise run lint

# Fix linting issues
mise run lint-fix
```

### Plugin structure

```
├── metadata.lua           # Plugin metadata (name, version, etc.)
├── hooks/
│   ├── mise_env.lua       # Environment variables hook
│   └── mise_path.lua      # PATH entries hook
├── lib/
│   └── lmod_env.lua       # Runs Lmod and diffs the environment
├── types/                 # Lua type definitions for lua-language-server
├── .luarc.json            # Lua language server configuration
├── hk.pkl                 # hk linter configuration
├── mise.toml              # mise configuration for development
└── .github/workflows/
    └── ci.yml             # GitHub Actions CI
```

## License

[MIT](LICENSE)
