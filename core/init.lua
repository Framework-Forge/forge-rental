ForgeRental = ForgeRental or {}
ForgeRental.resource = GetCurrentResourceName()
ForgeRental.configPath = 'data/config'
ForgeRental.debtsPath = 'data/debts'

local lang = pr_lib.locale()

function ForgeRental.t(key, values)
    if type(lang) == 'table' and type(lang.t) == 'function' then
        return lang:t(key, values)
    end

    if type(lang) == 'function' then
        return lang(key, values)
    end

    return key
end

function locale(key, ...)
    local text = ForgeRental.t(key)
    local args = table.pack(...)

    if args.n > 0 and type(text) == 'string' then
        local ok, formatted = pcall(string.format, text, table.unpack(args, 1, args.n))
        if ok then return formatted end
    end

    return text
end
