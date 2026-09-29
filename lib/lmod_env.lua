-- Shared logic for the MiseEnv and MisePath hooks.
--
-- Rather than parsing Lmod's shell output directly, run the modulefiles in a
-- throw-away shell and diff the environment before and after `module load`.
-- The modules are unloaded first so the result is the same whether or not
-- they are already loaded in the calling shell (mise re-runs env plugins with
-- the environment it previously exported, so this keeps the hook idempotent).

local M = {}

local log = require("log")

local SPLIT = "__MISE_LMOD_SPLIT__"

-- Variables that must never be copied back into the user's shell.
local SKIP = {
    ["_"] = true,
    PWD = true,
    OLDPWD = true,
    SHLVL = true,
    PATH = true,
}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function normalize_modules(opts)
    local modules = opts and opts.modules
    if modules == nil then
        return {}
    end
    if type(modules) == "string" then
        return { modules }
    end
    return modules
end

-- Parse `env -0` output into a table.
local function parse_env0(blob)
    local t = {}
    for entry in blob:gmatch("([^%z]+)") do
        local k, v = entry:match("^([^=]+)=(.*)$")
        if k and not k:match("^BASH_FUNC_") then
            t[k] = v
        end
    end
    return t
end

local function split_path(p)
    local list = {}
    for d in (p or ""):gmatch("[^:]+") do
        table.insert(list, d)
    end
    return list
end

-- Cache results for the life of the Lua state so repeated calls within one
-- mise invocation do not re-run Lmod.
local cache = {}

function M.compute(opts)
    local modules = normalize_modules(opts)
    if #modules == 0 then
        return nil
    end

    local key = table.concat(modules, "\n")
    if cache[key] ~= nil then
        return cache[key] or nil
    end

    local lmod_cmd = os.getenv("LMOD_CMD")
    if not lmod_cmd or lmod_cmd == "" then
        log.warn("LMOD_CMD is not set; is Lmod initialized in this shell?")
        return nil
    end

    local quoted = {}
    for _, m in ipairs(modules) do
        table.insert(quoted, shell_quote(m))
    end
    local mods = table.concat(quoted, " ")
    local lmod = shell_quote(lmod_cmd)

    -- Lmod messages go to stderr; capture them so failures can be reported.
    -- mise's cmd.exec runs the script with `set -e`; handle errors ourselves.
    local script = table.concat({
        "set +e",
        'eval "$(' .. lmod .. " bash unload " .. mods .. ' 2>/dev/null)" >/dev/null 2>&1',
        "env -0",
        "printf '\\0" .. SPLIT .. "\\0'",
        "__lmod_out=$(mktemp) || exit 1",
        "__lmod_err=$(" .. lmod .. " bash load " .. mods .. ' 2>&1 >"$__lmod_out")',
        'eval "$(cat "$__lmod_out")" >/dev/null 2>&1; __lmod_rc=$?',
        'rm -f "$__lmod_out"',
        "env -0",
        "printf '\\0" .. SPLIT .. '\\0%s\\0%s\' "$__lmod_rc" "$__lmod_err"',
        "exit 0",
    }, "\n")

    local ok, out = pcall(function()
        local cmd = require("cmd")
        return cmd.exec(script)
    end)
    if not ok or type(out) ~= "string" then
        cache[key] = false
        log.warn("failed to run Lmod: " .. tostring(out))
        return nil
    end

    local s1 = out:find("%z" .. SPLIT .. "%z")
    local rest = s1 and out:sub(s1 + #SPLIT + 2) or ""
    local s2 = rest:find("%z" .. SPLIT .. "%z")
    if not s1 or not s2 then
        cache[key] = false
        log.warn("unexpected output while running Lmod")
        return nil
    end
    local before_blob = out:sub(1, s1 - 1)
    local after_blob = rest:sub(1, s2 - 1)
    local rc, err = rest:sub(s2 + #SPLIT + 2):match("^([^%z]*)%z(.*)$")

    -- Lmod emits `false` on an error (e.g. unknown module), so eval fails.
    if rc ~= "0" or (err and err:match("Lmod has detected the following error")) then
        cache[key] = false
        log.warn("module load " .. table.concat(modules, " ") .. " failed:\n" .. (err or ""))
        return nil
    end

    local before, after = parse_env0(before_blob), parse_env0(after_blob)

    local env = {}
    for k, v in pairs(after) do
        if not SKIP[k] and before[k] ~= v then
            table.insert(env, { key = k, value = v })
        end
    end
    table.sort(env, function(a, b)
        return a.key < b.key
    end)

    -- mise manages PATH itself, so hand back only the new directories.
    local seen, paths = {}, {}
    for _, d in ipairs(split_path(before.PATH)) do
        seen[d] = true
    end
    for _, d in ipairs(split_path(after.PATH)) do
        if not seen[d] then
            seen[d] = true
            table.insert(paths, d)
        end
    end

    local result = { env = env, paths = paths }
    cache[key] = result
    return result
end

return M
