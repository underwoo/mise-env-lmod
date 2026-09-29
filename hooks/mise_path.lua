--- Returns the PATH entries added by loading the configured Lmod modules
--- Documentation: https://mise.jdx.dev/env-plugin-development.html#misepath-hook
--- @param ctx {options: table} Context (options = plugin configuration from mise.toml)
--- @return string[] List of paths to prepend to PATH
function PLUGIN:MisePath(ctx)
    local lmod_env = require("lmod_env")
    local r = lmod_env.compute(ctx.options)
    if not r then
        return {}
    end
    return r.paths
end
