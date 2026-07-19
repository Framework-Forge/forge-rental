RentalService = RentalService or {
    config = nil,
    locations = {},
    activeRentals = {},
    debts = {},
}

local function debug(level, message)
    local api = pr_lib and pr_lib.debug
    local fn = api and api[level]

    if type(fn) == 'function' then
        fn(message)
        return
    end

    if level == 'warn' or level == 'error' then
        print(('[forge-rental][%s] %s'):format(level, tostring(message)))
    end
end

local function notifyPlayer(source, description, notifyType)
    if source <= 0 then return end

    pr_lib.notify.Notify(source, {
        title = 'Forge Rental',
        description = description,
        type = notifyType or 'inform',
    })
end

local function trim(value)
    if pr_lib.utils and pr_lib.utils.trim then return pr_lib.utils.trim(value) end
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function boolValue(value, fallback)
    if value == nil then return fallback == true end
    if type(value) == 'boolean' then return value end

    local lowered = tostring(value):lower()
    return lowered == 'true' or lowered == '1' or lowered == 'yes' or lowered == 'sim'
end

local function numberValue(value, fallback)
    return tonumber(value) or fallback or 0
end

local function clampNumber(value, minValue, maxValue)
    value = numberValue(value, minValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function normalizeId(value, fallback)
    value = trim(value)
    if value == '' then value = fallback or '' end

    return value:lower():gsub('%s+', '_'):gsub('[^%w_%-]', ''):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
end

local function normalizeBilling(value, accounts)
    value = type(value) == 'table' and value or {}
    accounts = type(accounts) == 'table' and accounts or {}

    return {
        account = trim(value.account) ~= '' and trim(value.account) or (trim(accounts.rent) ~= '' and trim(accounts.rent) or 'bank'),
        timeIntervalMinutes = math.max(1, math.floor(numberValue(value.timeIntervalMinutes, 10))),
        pricePerInterval = math.max(0, math.floor(numberValue(value.pricePerInterval, 10))),
        fuelPricePerLiter = math.max(0, math.floor(numberValue(value.fuelPricePerLiter, 10))),
        insuranceFee = math.max(0, math.floor(numberValue(value.insuranceFee, 80))),
        fullTankLiters = clampNumber(value.fullTankLiters, 1.0, 100.0),
    }
end

local function vectorValue(value)
    value = type(value) == 'table' and value or {}

    return {
        x = numberValue(value.x or value[1]),
        y = numberValue(value.y or value[2]),
        z = numberValue(value.z or value[3]),
        w = numberValue(value.w or value[4]),
    }
end

local function stockValue(value)
    local normalized = {}
    value = type(value) == 'table' and value or {}

    for key, item in pairs(value) do
        item = type(item) == 'table' and item or {}
        local model = normalizeId(item.model or item.name or key)

        if model ~= '' then
            normalized[#normalized + 1] = {
                model = model,
                label = trim(item.label) ~= '' and trim(item.label) or model,
                price = math.max(0, numberValue(item.price)),
                enabled = boolValue(item.enabled, true),
            }
        end
    end

    table.sort(normalized, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    return normalized
end

local function normalizeLocation(value, index)
    value = type(value) == 'table' and value or {}

    local label = trim(value.label or value.name or value.id)
    if label == '' then label = ('Rental %s'):format(index or 1) end

    local coords = vectorValue(value.coords or value.position)
    local location = {
        id = normalizeId(value.id, label),
        label = label,
        enabled = boolValue(value.enabled, true),
        coords = coords,
        entityType = trim(value.entityType) ~= '' and trim(value.entityType) or 'ped',
        model = trim(value.model) ~= '' and trim(value.model) or 's_m_m_highsec_01',
        stock = stockValue(value.stock),
        vehicleSpawn = {},
    }

    local animdata = type(value.animdata) == 'table' and value.animdata or nil
    if animdata and trim(animdata.dict) ~= '' and trim(animdata.anim) ~= '' then
        location.animdata = {
            dict = trim(animdata.dict),
            anim = trim(animdata.anim),
            flags = math.floor(numberValue(animdata.flags, 1)),
        }
    end

    local blip = type(value.blip) == 'table' and value.blip or {}
    location.blip = {
        enabled = boolValue(blip.enabled, blip.sprite ~= nil),
        sprite = math.floor(numberValue(blip.sprite, 227)),
        color = math.floor(numberValue(blip.color, 5)),
        scale = numberValue(blip.scale, 0.8),
    }

    local spawns = type(value.vehicleSpawn) == 'table' and value.vehicleSpawn or {}
    for i = 1, #spawns do
        local spawn = vectorValue(spawns[i])
        location.vehicleSpawn[#location.vehicleSpawn + 1] = spawn
    end

    return location
end

local function normalizeConfig(config)
    config = type(config) == 'table' and config or {}
    config.accounts = type(config.accounts) == 'table' and config.accounts or {}

    local normalized = {
        enabled = boolValue(config.enabled, true),
        command = normalizeId(config.command, 'rentaladmin'),
        paperworkItem = normalizeId(config.paperworkItem, 'rental_paperwork'),
        accounts = {
            rent = trim(config.accounts.rent) ~= '' and trim(config.accounts.rent) or 'bank',
            refund = trim(config.accounts.refund) ~= '' and trim(config.accounts.refund) or 'bank',
        },
        billing = normalizeBilling(config.billing, config.accounts),
        returnRadius = math.max(1.0, numberValue(config.returnRadius, 5.0)),
        returnVehicleRadius = math.max(5.0, numberValue(config.returnVehicleRadius, 100.0)),
        spawnCheckRadius = math.max(1.0, numberValue(config.spawnCheckRadius, 3.0)),
        locations = {},
    }

    local locations = type(config.locations) == 'table' and config.locations or {}
    for index = 1, #locations do
        local location = normalizeLocation(locations[index], index)
        if location.id ~= '' then
            normalized.locations[#normalized.locations + 1] = location
        end
    end

    return normalized
end

local function rebuildLocationLookup()
    RentalService.locations = {}

    for index = 1, #(RentalService.config.locations or {}) do
        local location = RentalService.config.locations[index]
        RentalService.locations[location.id] = location
    end
end

function RentalService.loadConfig()
    local loaded = pr_lib.loadJson(ForgeRental.configPath, true)

    if type(loaded) ~= 'table' then
        loaded = {
            enabled = true,
            command = 'rentaladmin',
            paperworkItem = 'rental_paperwork',
            accounts = { rent = 'bank', refund = 'bank' },
            billing = {
                account = 'bank',
                timeIntervalMinutes = 10,
                pricePerInterval = 10,
                fuelPricePerLiter = 10,
                insuranceFee = 80,
                fullTankLiters = 100.0,
            },
            locations = {},
        }
    end

    RentalService.config = normalizeConfig(loaded)
    rebuildLocationLookup()

    return RentalService.config
end

function RentalService.loadDebts()
    local loaded = pr_lib.loadJson(ForgeRental.debtsPath, true)
    RentalService.debts = type(loaded) == 'table' and loaded or {}
    return RentalService.debts
end

function RentalService.saveDebts()
    local saved, result = pr_lib.saveJson(ForgeRental.debtsPath, RentalService.debts or {})
    if not saved then
        debug('warn', ('saveDebts failed err=%s'):format(tostring(result)))
        return false, result or 'debt_save_failed'
    end

    return true
end

function RentalService.saveConfig(config)
    RentalService.config = normalizeConfig(config or RentalService.config)
    rebuildLocationLookup()

    local saved, result = pr_lib.saveJson(ForgeRental.configPath, RentalService.config)
    if not saved then
        return false, result or 'json_save_failed'
    end

    return true, result
end

local function refreshClient(source)
    if source <= 0 then return end
    pr_lib.callback.awaitClient(source, 'forge-rental:client:refreshConfig', 5000, RentalService.config)
end

local function refreshClients()
    for _, playerSource in ipairs(GetPlayers()) do
        local source = tonumber(playerSource)
        if source then
            CreateThread(function()
                refreshClient(source)
            end)
        end
    end
end

local function hasAdminAccess(source)
    if source == 0 then return true end
    if IsPlayerAceAllowed(source, 'forge-rental.admin') then return true end

    local command = RentalService.config and RentalService.config.command or 'rentaladmin'
    return IsPlayerAceAllowed(source, ('command.%s'):format(command)) or IsPlayerAceAllowed(source, 'command.rentaladmin')
end

local function getPlayerFullName(source)
    local first, last = pr_lib.framework.GetPlayerName(source)

    if type(first) == 'table' then
        return trim(('%s %s'):format(first.firstname or first.firstName or first.first or '', first.lastname or first.lastName or first.last or ''))
    end

    if last ~= nil then return trim(('%s %s'):format(tostring(first or ''), tostring(last or ''))) end
    return trim(first) ~= '' and trim(first) or ('Player %s'):format(source)
end

local function getActiveDebtSummary(identifier)
    local summary = {
        total = 0,
        count = 0,
        debts = {},
    }

    identifier = trim(identifier)
    if identifier == '' then return summary end

    for index = 1, #(RentalService.debts or {}) do
        local debt = RentalService.debts[index]
        if type(debt) == 'table' and debt.identifier == identifier and debt.paid ~= true then
            local amount = math.max(0, math.floor(numberValue(debt.amount)))
            summary.total = summary.total + amount
            summary.count = summary.count + 1
            summary.debts[#summary.debts + 1] = debt
        end
    end

    return summary
end

local function getSourceDebtSummary(source)
    local identifier = pr_lib.framework.GetPlayerIdentifier(source)
    return getActiveDebtSummary(identifier)
end

local function accountCandidates(preferredAccount)
    local candidates = {}
    local seen = {}

    local function add(account)
        account = trim(account)
        if account == '' then return end
        local key = account:lower()
        if seen[key] then return end
        seen[key] = true
        candidates[#candidates + 1] = account
    end

    add(preferredAccount)
    add('bank')
    add('cash')
    add('money')

    return candidates
end

local function tryChargePlayer(source, amount, preferredAccount, reason)
    amount = math.max(0, math.floor(numberValue(amount)))
    if amount <= 0 then return true, 'none' end

    local candidates = accountCandidates(preferredAccount)
    for index = 1, #candidates do
        local account = candidates[index]
        local balance = tonumber(pr_lib.framework.GetAccountBalance(source, account)) or 0
        if balance >= amount then
            local removed = pr_lib.framework.RemoveAccountBalance(source, account, amount, reason)
            if removed ~= false then return true, account end
        end
    end

    return false, 'no_money'
end

local function createDebt(source, rental, invoice)
    local identifier = pr_lib.framework.GetPlayerIdentifier(source)
    if trim(identifier) == '' then return false, 'debt_save_failed' end

    local debt = {
        id = ('%s_%s_%s'):format(os.time(), source, math.random(1000, 9999)),
        identifier = identifier,
        playerName = getPlayerFullName(source),
        amount = math.max(0, math.floor(numberValue(invoice.total))),
        plate = rental.plate,
        locationId = rental.locationId,
        vehicleModel = rental.vehicleModel,
        vehicleLabel = rental.vehicleLabel,
        createdAt = os.time(),
        paid = false,
        invoice = invoice,
    }

    RentalService.debts[#RentalService.debts + 1] = debt
    local saved, result = RentalService.saveDebts()
    if not saved then return false, result end

    return true, debt
end

local function payActiveDebts(source)
    local identifier = pr_lib.framework.GetPlayerIdentifier(source)
    local summary = getActiveDebtSummary(identifier)
    if summary.total <= 0 then return true, { total = 0, count = 0 } end

    local billing = normalizeBilling(RentalService.config.billing, RentalService.config.accounts)
    local paid, account = tryChargePlayer(source, summary.total, billing.account, 'forge-rental:pay-debt')
    if not paid then return false, 'no_money_debt' end

    local paidCount = 0
    for index = 1, #(RentalService.debts or {}) do
        local debt = RentalService.debts[index]
        if type(debt) == 'table' and debt.identifier == identifier and debt.paid ~= true then
            debt.paid = true
            debt.paidAt = os.time()
            debt.paidAccount = account
            paidCount = paidCount + 1
        end
    end

    local saved, result = RentalService.saveDebts()
    if not saved then return false, result end

    return true, { total = summary.total, count = paidCount, account = account }
end

local function findStock(location, model)
    model = normalizeId(model)

    for index = 1, #(location.stock or {}) do
        local item = location.stock[index]
        if normalizeId(item.model) == model then return item end
    end

    return nil
end

local function playerNearLocation(source, location, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local pedCoords = GetEntityCoords(ped)
    local coords = location.coords or {}
    return #(pedCoords - vector3(coords.x, coords.y, coords.z)) <= (distance or 100.0)
end

local function waitForNetworkEntity(netId, timeout)
    local deadline = GetGameTimer() + (timeout or 2000)
    local entity = NetworkGetEntityFromNetworkId(netId)

    while (not entity or entity == 0 or not DoesEntityExist(entity)) and GetGameTimer() < deadline do
        Wait(50)
        entity = NetworkGetEntityFromNetworkId(netId)
    end

    if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    return nil
end

local function setRentalVehicleState(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local state = Entity(vehicle).state
    state:set('rental', true, true)
    state:set('door', 1, true)
    SetVehicleDoorsLocked(vehicle, 1)
end

local function giveRentalKey(source, plate, netId)
    if not pr_lib.vehicle_key or type(pr_lib.vehicle_key.GiveTempKeys) ~= 'function' then
        return false, 'vehicle_key_unavailable'
    end

    local ok, result = pcall(pr_lib.vehicle_key.GiveTempKeys, source, plate)
    if not ok then
        debug('warn', ('GiveTempKeys failed source=%s plate=%s err=%s'):format(source, tostring(plate), tostring(result)))
        return false, 'vehicle_key_failed'
    end

    if result == false then return false, 'vehicle_key_failed' end

    if type(pr_lib.vehicle_key.GiveKeyItem) == 'function' then
        local itemOk, itemResult = pcall(pr_lib.vehicle_key.GiveKeyItem, source, plate, netId)
        if not itemOk then
            debug('warn', ('GiveKeyItem failed source=%s plate=%s err=%s'):format(source, tostring(plate), tostring(itemResult)))
            pr_lib.vehicle_key.RemoveTempKeys(source, plate)
            return false, 'vehicle_key_failed'
        end

        if itemResult == false or itemResult == nil then
            pr_lib.vehicle_key.RemoveTempKeys(source, plate)
            return false, 'vehicle_key_failed'
        end
    end

    return true
end

local function removeRentalKey(source, plate)
    if not pr_lib.vehicle_key or type(pr_lib.vehicle_key.RemoveTempKeys) ~= 'function' then return true end

    local ok, result = pcall(pr_lib.vehicle_key.RemoveTempKeys, source, plate)
    if not ok then
        debug('warn', ('RemoveTempKeys failed source=%s plate=%s err=%s'):format(source, tostring(plate), tostring(result)))
        return false
    end

    if type(pr_lib.vehicle_key.RemoveKeyItem) == 'function' then
        local itemOk, itemResult = pcall(pr_lib.vehicle_key.RemoveKeyItem, source, plate)
        if not itemOk then
            debug('warn', ('RemoveKeyItem failed source=%s plate=%s err=%s'):format(source, tostring(plate), tostring(itemResult)))
        end
    end

    return result ~= false
end

local function calculateBilling(rental, fuelLevel)
    local billing = normalizeBilling(rental.billing or RentalService.config.billing, RentalService.config.accounts)
    local startedAt = tonumber(rental.startedAt) or os.time()
    local elapsedSeconds = math.max(0, os.time() - startedAt)
    local elapsedMinutes = math.max(1, math.ceil(elapsedSeconds / 60))
    local intervals = billing.pricePerInterval > 0 and math.max(1, math.ceil(elapsedMinutes / billing.timeIntervalMinutes)) or 0
    local currentFuel = clampNumber(fuelLevel, 0.0, billing.fullTankLiters)
    local missingFuelLiters = math.max(0.0, billing.fullTankLiters - currentFuel)
    local timeFee = math.max(0, intervals * billing.pricePerInterval)
    local fuelFee = math.max(0, math.ceil(missingFuelLiters * billing.fuelPricePerLiter))
    local insuranceFee = math.max(0, billing.insuranceFee)

    return {
        account = billing.account,
        startedAt = startedAt,
        elapsedSeconds = elapsedSeconds,
        elapsedMinutes = elapsedMinutes,
        intervals = intervals,
        currentFuel = currentFuel,
        fullTankLiters = billing.fullTankLiters,
        missingFuelLiters = missingFuelLiters,
        timeIntervalMinutes = billing.timeIntervalMinutes,
        pricePerInterval = billing.pricePerInterval,
        fuelPricePerLiter = billing.fuelPricePerLiter,
        insuranceFee = insuranceFee,
        timeFee = timeFee,
        fuelFee = fuelFee,
        total = insuranceFee + timeFee + fuelFee,
    }
end

function RentalService.rentVehicle(source, locationId, vehicleModel)
    if not RentalService.config.enabled then return false, 'system_disabled' end

    local debtSummary = getSourceDebtSummary(source)
    if debtSummary.total > 0 then return false, 'debt_pending' end

    local location = RentalService.locations[normalizeId(locationId)]
    if not location or not location.enabled then return false, 'location_unavailable' end
    if not playerNearLocation(source, location, 100.0) then return false, 'too_far' end

    local stock = findStock(location, vehicleModel)
    if not stock or stock.enabled == false then return false, 'vehicle_unavailable' end

    local netId, plate = pr_lib.callback.awaitClient(
        source,
        'forge-rental:client:createVehicle',
        10000,
        stock.model,
        location.vehicleSpawn,
        RentalService.config.spawnCheckRadius,
        RentalService.config.billing.fullTankLiters
    )

    netId = tonumber(netId)
    if not netId or not plate then return false, 'no_spawn' end

    local vehicle = waitForNetworkEntity(netId, 2500)
    if vehicle then setRentalVehicleState(vehicle) end

    local identifier = pr_lib.framework.GetPlayerIdentifier(source)
    local startedAt = os.time()
    RentalService.activeRentals[netId] = {
        renter = identifier,
        plate = plate,
        startedAt = startedAt,
        initialFuel = RentalService.config.billing.fullTankLiters,
        billing = RentalService.config.billing,
        locationId = location.id,
        vehicleModel = stock.model,
        vehicleLabel = stock.label,
    }

    local renterName = getPlayerFullName(source)
    local metadata = {
        plate = plate,
        rentalLocation = location.id,
        vehNetId = netId,
        vehName = stock.label,
        renter = renterName,
        startedAt = startedAt,
        initialFuel = RentalService.config.billing.fullTankLiters,
        billing = RentalService.config.billing,
        description = locale('RentalMenus.PaperWorkItem', location.label, stock.label, plate, renterName),
    }

    local added = pr_lib.inventory.AddItem(source, RentalService.config.paperworkItem, 1, metadata)
    if added == false then
        RentalService.activeRentals[netId] = nil
        if vehicle then DeleteEntity(vehicle) end
        return false, 'paperwork_failed'
    end

    local keyGiven, keyError = giveRentalKey(source, plate, netId)
    if not keyGiven then
        pr_lib.inventory.RemoveItem(source, RentalService.config.paperworkItem, 1)
        RentalService.activeRentals[netId] = nil
        if vehicle then DeleteEntity(vehicle) end
        return false, keyError
    end

    return true, { netId = netId, plate = plate, label = stock.label, billing = RentalService.config.billing }
end

function RentalService.returnVehicle(source, locationId, plate, netId, slot, fuelLevel)
    local location = RentalService.locations[normalizeId(locationId)]
    if not location then return false, 'location_unavailable' end
    if not playerNearLocation(source, location, RentalService.config.returnRadius) then return false, 'too_far' end

    netId = tonumber(netId)
    local rental = netId and RentalService.activeRentals[netId] or nil
    if not rental then return false, 'rental_not_found' end
    if rental.plate ~= plate or rental.locationId ~= location.id then return false, 'rental_mismatch' end

    local identifier = pr_lib.framework.GetPlayerIdentifier(source)
    if rental.renter ~= identifier then return false, 'not_renter' end

    local vehicle = waitForNetworkEntity(netId, 1000)
    if not vehicle then return false, 'vehicle_not_found' end

    local vehicleCoords = GetEntityCoords(vehicle)
    local locationCoords = vector3(location.coords.x, location.coords.y, location.coords.z)
    if #(vehicleCoords - locationCoords) > RentalService.config.returnVehicleRadius then return false, 'too_far' end

    local invoice = calculateBilling(rental, fuelLevel)
    local paid, account = tryChargePlayer(source, invoice.total, invoice.account, 'forge-rental:return')
    if not paid then
        local debtSaved, debtResult = createDebt(source, rental, invoice)
        if not debtSaved then return false, debtResult or 'debt_save_failed' end
        invoice.debtCreated = true
        invoice.debtId = debtResult.id
    else
        invoice.paidAccount = account
    end

    pr_lib.inventory.RemoveItem(source, RentalService.config.paperworkItem, 1, nil, slot)
    removeRentalKey(source, rental.plate)

    DeleteEntity(vehicle)
    RentalService.activeRentals[netId] = nil

    debug('info', ('return source=%s plate=%s total=%s time=%s fuel=%s insurance=%s'):format(source, rental.plate, invoice.total, invoice.timeFee, invoice.fuelFee, invoice.insuranceFee))

    return true, invoice
end

PRCore.callback.register('forge-rental:server:getConfig', function(source)
    if not RentalService.config then RentalService.loadConfig() end
    return RentalService.config
end)

PRCore.callback.register('forge-rental:server:rentVehicle', function(source, locationId, vehicleModel)
    local ok, result = RentalService.rentVehicle(source, locationId, vehicleModel)
    if not ok then notifyPlayer(source, locale('RentalMenus.' .. result), 'error') end
    return ok, result
end)

PRCore.callback.register('forge-rental:server:returnVehicle', function(source, locationId, plate, netId, slot, fuelLevel)
    local ok, result = RentalService.returnVehicle(source, locationId, plate, netId, slot, fuelLevel)
    if not ok then notifyPlayer(source, locale('RentalMenus.' .. result), 'error') end
    return ok, result
end)

PRCore.callback.register('forge-rental:server:getDebtSummary', function(source)
    return getSourceDebtSummary(source)
end)

PRCore.callback.register('forge-rental:server:payDebts', function(source)
    local ok, result = payActiveDebts(source)
    if not ok then notifyPlayer(source, locale('RentalMenus.' .. result), 'error') end
    return ok, result
end)

PRCore.callback.register('forge-rental:server:adminGetConfig', function(source)
    if not hasAdminAccess(source) then return false, 'no_permission' end
    return true, RentalService.config
end)

PRCore.callback.register('forge-rental:server:adminSaveConfig', function(source, config)
    if not hasAdminAccess(source) then return false, 'no_permission' end

    local ok, result = RentalService.saveConfig(config)
    if not ok then return false, result end

    refreshClients()
    return true, RentalService.config
end)

PRCore.callback.register('forge-rental:server:adminReloadConfig', function(source)
    if not hasAdminAccess(source) then return false, 'no_permission' end

    RentalService.loadConfig()
    refreshClients()

    return true, RentalService.config
end)

RentalService.loadConfig()
RentalService.loadDebts()

pr_lib.addCommand(RentalService.config.command or 'rentaladmin', {
    help = locale('Admin.CommandHelp'),
    restricted = 'group.admin',
}, function(source)
    if not hasAdminAccess(source) then
        notifyPlayer(source, locale('Admin.NoPermission'), 'error')
        return
    end

    pr_lib.callback.awaitClient(source, 'forge-rental:client:openAdminMenu', 5000, RentalService.config)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for netId in pairs(RentalService.activeRentals) do
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
    end
end)
