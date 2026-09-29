--- Returns the environment variables set by loading the configured Lmod modules
--- Documentation: https://mise.jdx.dev/env-plugin-development.html#miseenv-hook
--- @param ctx {options: table} Context (options = plugin configuration from mise.toml)
--- @return table[] List of environment variable definitions with key/value pairs
function PLUGIN:MiseEnv(ctx)
    local lmod_env = require("lmod_env")
    local r = lmod_env.compute(ctx.options)
    if not r then
        return {}
    end
    return r.env
end
