RentalClient = RentalClient or {
    config = nil,
    entities = {},
    blips = {},
    adminConfig = nil,
    adminParent = nil,
}

local notify

local function trim(value)
    if pr_lib.utils and pr_lib.utils.trim then return pr_lib.utils.trim(value) end
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizeId(value, fallback)
    value = trim(value)
    if value == '' then value = fallback or '' end

    return value:lower():gsub('%s+', '_'):gsub('[^%w_%-]', ''):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
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

local function vector3From(value)
    value = type(value) == 'table' and value or {}
    return vector3(numberValue(value.x or value[1]), numberValue(value.y or value[2]), numberValue(value.z or value[3]))
end

local function vector4From(value)
    value = type(value) == 'table' and value or {}
    return vector4(numberValue(value.x or value[1]), numberValue(value.y or value[2]), numberValue(value.z or value[3]), numberValue(value.w or value[4]))
end

local function currentPosition()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    return {
        x = tonumber(('%0.4f'):format(coords.x)),
        y = tonumber(('%0.4f'):format(coords.y)),
        z = tonumber(('%0.4f'):format(coords.z)),
        w = tonumber(('%0.4f'):format(GetEntityHeading(ped))),
    }
end

local function placementToPosition(placement)
    if type(placement) ~= 'table' then return nil end

    return {
        x = numberValue(placement.x),
        y = numberValue(placement.y),
        z = numberValue(placement.z),
        w = numberValue(placement.w or placement.heading),
    }
end

local function placeRentalEntity(model, entityType, cb)
    entityType = trim(entityType) ~= '' and trim(entityType) or 'ped'
    model = trim(model) ~= '' and trim(model) or (entityType == 'object' and 'prop_parkingpay' or 's_m_m_highsec_01')

    local api = pr_lib.devtools
    if not api then
        notify(locale('Admin.DevtoolsUnavailable'), 'error')
        cb(nil)
        return
    end

    local done = function(result)
        cb(placementToPosition(result))
    end

    if entityType == 'object' and type(api.placeObject) == 'function' then
        api.placeObject(model, 1, done, { preview = true })
        return
    end

    if type(api.placePed) == 'function' then
        api.placePed(model, 1, done, { preview = true })
        return
    end

    notify(locale('Admin.DevtoolsUnavailable'), 'error')
    cb(nil)
end

local function placeVehicleSpawns(model, cb)
    model = trim(model) ~= '' and trim(model) or 'sultan'

    local api = pr_lib.devtools
    if not api or type(api.placeVehicle) ~= 'function' then
        notify(locale('Admin.DevtoolsUnavailable'), 'error')
        cb(nil)
        return
    end

    api.placeVehicle(model, 0, function(result)
        local spawns = {}
        if type(result) == 'table' then
            if result.x then
                spawns[#spawns + 1] = placementToPosition(result)
            else
                for index = 1, #result do
                    local spawn = placementToPosition(result[index])
                    if spawn then spawns[#spawns + 1] = spawn end
                end
            end
        end

        cb(spawns)
    end, { preview = true })
end

function notify(description, notifyType)
    pr_lib.notify.Notify({
        title = 'Forge Rental',
        description = description,
        type = notifyType or 'inform',
    })
end

local function registerContext(context)
    pr_lib.menus.RegisterContext(context)
    pr_lib.menus.ShowContext(context.id)
end

local function inputDialog(title, rows)
    return pr_lib.menus.InputDialog(title, rows, { allowCancel = true })
end

local function formatCoords(coords)
    if not coords then return '0.00, 0.00, 0.00' end
    return ('%.2f, %.2f, %.2f'):format(numberValue(coords.x), numberValue(coords.y), numberValue(coords.z))
end

local function formatMoney(value)
    return ('$%s'):format(math.floor(numberValue(value)))
end

local function currentTimestamp()
    if type(GetCloudTimeAsInt) == 'function' then
        local ok, result = pcall(GetCloudTimeAsInt)
        if ok and tonumber(result) then return tonumber(result) end
    end

    return math.floor(GetGameTimer() / 1000)
end

local function getBillingConfig()
    local config = RentalClient.config or RentalClient.adminConfig or {}
    local billing = type(config.billing) == 'table' and config.billing or {}

    return {
        account = trim(billing.account) ~= '' and trim(billing.account) or 'bank',
        timeIntervalMinutes = math.max(1, math.floor(numberValue(billing.timeIntervalMinutes, 10))),
        pricePerInterval = math.max(0, math.floor(numberValue(billing.pricePerInterval, 10))),
        fuelPricePerLiter = math.max(0, math.floor(numberValue(billing.fuelPricePerLiter, 10))),
        insuranceFee = math.max(0, math.floor(numberValue(billing.insuranceFee, 80))),
        fullTankLiters = math.max(1.0, math.min(100.0, numberValue(billing.fullTankLiters, 100.0))),
    }
end

local function getVehicleFuel(vehicle)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        if pr_lib.fuel and type(pr_lib.fuel.GetFuel) == 'function' then
            local ok, result = pcall(pr_lib.fuel.GetFuel, vehicle)
            if ok and tonumber(result) then return tonumber(result) end
        end

        return tonumber(GetVehicleFuelLevel(vehicle)) or 0.0
    end

    return 0.0
end

local function setVehicleFuel(vehicle, amount)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    amount = math.max(0.0, math.min(100.0, numberValue(amount, 100.0)))

    if pr_lib.fuel and type(pr_lib.fuel.SetFuel) == 'function' then
        local ok = pcall(pr_lib.fuel.SetFuel, vehicle, amount)
        if ok then return end
    end

    SetVehicleFuelLevel(vehicle, amount + 0.0)
    if pr_lib.fivem and pr_lib.fivem.vehicleCache then
        pr_lib.fivem.vehicleCache.setState(vehicle, 'fuel', amount + 0.0, true)
    else
        debug('warn', 'vehicleCache unavailable while synchronizing fuel')
    end
end

local function calculateReturnPreview(metadata, vehicle)
    metadata = type(metadata) == 'table' and metadata or {}
    local billing = type(metadata.billing) == 'table' and metadata.billing or getBillingConfig()
    local startedAt = tonumber(metadata.startedAt) or currentTimestamp()
    local elapsedSeconds = math.max(0, currentTimestamp() - startedAt)
    local elapsedMinutes = math.max(1, math.ceil(elapsedSeconds / 60))
    local timeInterval = math.max(1, math.floor(numberValue(billing.timeIntervalMinutes, 10)))
    local pricePerInterval = math.max(0, math.floor(numberValue(billing.pricePerInterval, 10)))
    local fullTank = math.max(1.0, math.min(100.0, numberValue(billing.fullTankLiters, 100.0)))
    local fuel = math.max(0.0, math.min(fullTank, getVehicleFuel(vehicle)))
    local missingFuel = math.max(0.0, fullTank - fuel)
    local intervals = pricePerInterval > 0 and math.max(1, math.ceil(elapsedMinutes / timeInterval)) or 0
    local timeFee = intervals * pricePerInterval
    local fuelFee = math.ceil(missingFuel * math.max(0, math.floor(numberValue(billing.fuelPricePerLiter, 10))))
    local insuranceFee = math.max(0, math.floor(numberValue(billing.insuranceFee, 80)))

    return {
        fuel = fuel,
        fullTank = fullTank,
        missingFuel = missingFuel,
        elapsedMinutes = elapsedMinutes,
        intervals = intervals,
        timeInterval = timeInterval,
        timeFee = timeFee,
        fuelFee = fuelFee,
        insuranceFee = insuranceFee,
        total = insuranceFee + timeFee + fuelFee,
    }
end

local function getLocations(config)
    return type(config) == 'table' and type(config.locations) == 'table' and config.locations or {}
end

local function findLocation(config, locationId)
    locationId = normalizeId(locationId)
    local locations = getLocations(config)

    for index = 1, #locations do
        if normalizeId(locations[index].id) == locationId then return locations[index], index end
    end

    return nil, nil
end

local function findStock(location, model)
    model = normalizeId(model)
    local stock = type(location.stock) == 'table' and location.stock or {}

    for index = 1, #stock do
        if normalizeId(stock[index].model) == model then return stock[index], index end
    end

    return nil, nil
end

local function removeEntity(locationId)
    local entityData = RentalClient.entities[locationId]
    if not entityData then return end

    if entityData.entity and DoesEntityExist(entityData.entity) then
        pr_lib.target.removeLocalEntity(entityData.entity, { entityData.targetName })
        DeleteEntity(entityData.entity)
    end

    RentalClient.entities[locationId] = nil
end

local function removeBlip(locationId)
    local blip = RentalClient.blips[locationId]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    RentalClient.blips[locationId] = nil
end

local function clearLocations()
    for locationId in pairs(RentalClient.entities) do
        removeEntity(locationId)
    end

    for locationId in pairs(RentalClient.blips) do
        removeBlip(locationId)
    end
end

local function createBlip(location)
    local blipData = type(location.blip) == 'table' and location.blip or {}
    if not blipData.enabled then return end

    local coords = vector3From(location.coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, math.floor(numberValue(blipData.sprite, 227)))
    SetBlipColour(blip, math.floor(numberValue(blipData.color, 5)))
    SetBlipScale(blip, numberValue(blipData.scale, 0.8))
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(location.label or location.id or 'Rental')
    EndTextCommandSetBlipName(blip)

    RentalClient.blips[location.id] = blip
end

local function playEntityAnimation(entity, animdata)
    if type(animdata) ~= 'table' or trim(animdata.dict) == '' or trim(animdata.anim) == '' then return end
    if not pr_lib.fivem.streaming.requestAnimDict(animdata.dict, 5000) then return end

    TaskPlayAnim(entity, animdata.dict, animdata.anim, 8.0, -8.0, -1, math.floor(numberValue(animdata.flags, 1)), 0, false, false, false)
end

local function createRentalEntity(location)
    if not location.enabled then return end

    local coords = vector4From(location.coords)
    local entityType = trim(location.entityType) ~= '' and trim(location.entityType) or 'ped'
    local entity

    if entityType == 'ped' then
        entity = pr_lib.fivem.streaming.createPed(location.model, vector3(coords.x, coords.y, coords.z), coords.w, {
            networked = false,
            missionEntity = true,
            freeze = true,
            invincible = true,
            blockingEvents = true,
        })
    else
        entity = pr_lib.fivem.streaming.createObject(location.model, vector3(coords.x, coords.y, coords.z), {
            networked = false,
            missionEntity = true,
            freeze = true,
            invincible = true,
            placementType = 'object',
        })
        if entity and DoesEntityExist(entity) then SetEntityHeading(entity, coords.w) end
    end

    if not entity or not DoesEntityExist(entity) then
        notify(locale('Admin.EntityCreateFailed', location.label or location.id), 'error')
        return
    end

    SetEntityHeading(entity, coords.w)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)

    if entityType == 'ped' then playEntityAnimation(entity, location.animdata) end

    local targetName = ('forge_rental_%s'):format(location.id)
    pr_lib.target.addLocalEntity(entity, {
        {
            name = targetName,
            label = location.label,
            icon = 'fa-solid fa-car',
            distance = 3.0,
            onSelect = function()
                RentalClient.openRentalMenu(location.id)
            end,
        },
    })

    RentalClient.entities[location.id] = {
        entity = entity,
        targetName = targetName,
    }
end

function RentalClient.applyConfig(config)
    RentalClient.config = config
    clearLocations()

    if type(config) ~= 'table' or config.enabled == false then return end

    local locations = getLocations(config)
    for index = 1, #locations do
        createBlip(locations[index])
        createRentalEntity(locations[index])
    end
end

local function checkForMatchedPlate(plate)
    local vehicles = GetGamePool('CVehicle')
    local pedCoords = GetEntityCoords(PlayerPedId())

    for index = 1, #vehicles do
        local vehicle = vehicles[index]
        local vehiclePlate = trim(GetVehicleNumberPlateText(vehicle))

        if vehiclePlate == trim(plate) then
            if #(pedCoords - GetEntityCoords(vehicle)) > numberValue(RentalClient.config and RentalClient.config.returnVehicleRadius, 100.0) then
                return nil
            end

            return NetworkGetNetworkIdFromEntity(vehicle), vehicle
        end
    end

    return nil
end

local function getInventoryItems()
    local inventory = {}

    if type(pr_lib.inventory.GetPlayerInventory) == 'function' then
        inventory = pr_lib.inventory.GetPlayerInventory() or {}
    elseif type(pr_lib.inventory.GetPlayerItems) == 'function' then
        inventory = pr_lib.inventory.GetPlayerItems() or {}
    end

    if type(inventory.items) == 'table' then return inventory.items end
    return inventory
end

local function rentalReturnOptions(location)
    local options = {}
    local items = getInventoryItems()
    local paperworkItem = RentalClient.config and RentalClient.config.paperworkItem or 'rental_paperwork'

    for _, item in pairs(items) do
        if item.name == paperworkItem and type(item.metadata) == 'table' and item.metadata.rentalLocation == location.id and item.metadata.plate then
            local netId, vehicle = checkForMatchedPlate(item.metadata.plate)

            if netId then
                local preview = calculateReturnPreview(item.metadata, vehicle)
                options[#options + 1] = {
                    title = locale('RentalMenus.ReturnTitle'),
                    description = locale('RentalMenus.ReturnDescription', item.metadata.plate, formatMoney(preview.total)),
                    metadata = {
                        { label = locale('RentalMenus.ReturnFuel'), value = ('%.1f / %.1f L'):format(preview.fuel, preview.fullTank) },
                        { label = locale('RentalMenus.ReturnMissingFuel'), value = ('%.1f L'):format(preview.missingFuel) },
                        { label = locale('RentalMenus.ReturnTime'), value = locale('RentalMenus.ReturnTimeValue', preview.elapsedMinutes, preview.intervals) },
                        { label = locale('RentalMenus.ReturnInsuranceFee'), value = formatMoney(preview.insuranceFee) },
                        { label = locale('RentalMenus.ReturnTimeFee'), value = formatMoney(preview.timeFee) },
                        { label = locale('RentalMenus.ReturnFuelFee'), value = formatMoney(preview.fuelFee) },
                        { label = locale('RentalMenus.ReturnTotal'), value = formatMoney(preview.total) },
                    },
                    icon = 'arrow-counterclockwise',
                    iconColor = 'red',
                    onSelect = function()
                        local matchedNetId, vehicle = checkForMatchedPlate(item.metadata.plate)
                        if not matchedNetId then
                            notify(locale('RentalMenus.ReturnNoVehicle'), 'error')
                            return
                        end

                        local fuelLevel = getVehicleFuel(vehicle)
                        local ok, result = pr_lib.callback.await('forge-rental:server:returnVehicle', 10000, location.id, item.metadata.plate, matchedNetId, item.slot, fuelLevel)
                        if not ok then
                            if result == 'timeout' then notify(locale('Notify.RequestTimeout'), 'error') end
                            return
                        end

                        local total = type(result) == 'table' and result.total or 0
                        if type(result) == 'table' and result.debtCreated then
                            notify(locale('Notify.ReturnDebtCreated', formatMoney(total)), 'warning')
                            RentalClient.openRentalMenu(location.id)
                        else
                            notify(locale('Notify.ReturnSuccess', formatMoney(total)), 'success')
                        end
                    end,
                }
            end
        end
    end

    return options
end

local function appendDebtOptions(options, locationId)
    local summary = pr_lib.callback.await('forge-rental:server:getDebtSummary', 5000)
    if type(summary) ~= 'table' or numberValue(summary.total) <= 0 then return false end

    local metadata = {
        { label = locale('RentalMenus.DebtCount'), value = tostring(summary.count or 1) },
        { label = locale('RentalMenus.DebtTotal'), value = formatMoney(summary.total) },
    }

    local debts = type(summary.debts) == 'table' and summary.debts or {}
    for index = 1, math.min(#debts, 8) do
        local debt = type(debts[index]) == 'table' and debts[index] or {}
        metadata[#metadata + 1] = {
            label = debt.plate or ('#%s'):format(index),
            value = formatMoney(debt.amount or 0),
        }
    end

    options[#options + 1] = {
        title = locale('RentalMenus.DebtTitle'),
        description = locale('RentalMenus.DebtDescription', summary.count or 1, formatMoney(summary.total)),
        icon = 'receipt-cutoff',
        iconColor = 'red',
        metadata = metadata,
        onSelect = function()
            local ok, result = pr_lib.callback.await('forge-rental:server:payDebts', 10000)
            if not ok then
                if result == 'timeout' then notify(locale('Notify.RequestTimeout'), 'error') end
                return
            end

            notify(locale('Notify.DebtPaid', formatMoney(result.total or 0)), 'success')
            RentalClient.openRentalMenu(locationId)
        end,
    }

    return true
end

function RentalClient.openRentalMenu(locationId)
    local location = findLocation(RentalClient.config, locationId)
    if not location then return end

    local options = {
        {
            title = location.label,
            description = locale('RentalMenus.TitleDescription'),
            icon = 'car-front-fill',
            iconColor = 'orange',
            disabled = true,
        },
    }

    local hasDebt = appendDebtOptions(options, location.id)

    local stock = type(location.stock) == 'table' and location.stock or {}
    for index = 1, #stock do
        local vehicle = stock[index]
        if vehicle.enabled ~= false then
            local billing = getBillingConfig()
            options[#options + 1] = {
                title = vehicle.label,
                description = hasDebt and locale('RentalMenus.DebtBlocksRent') or locale('RentalMenus.MenuDescription', vehicle.label, formatMoney(billing.insuranceFee), billing.timeIntervalMinutes, formatMoney(billing.pricePerInterval), formatMoney(billing.fuelPricePerLiter)),
                icon = 'car-front',
                iconColor = hasDebt and 'gray' or 'orange',
                disabled = hasDebt,
                onSelect = function()
                    local ok, result = pr_lib.callback.await('forge-rental:server:rentVehicle', 10000, location.id, vehicle.model)
                    if not ok then
                        if result == 'timeout' then notify(locale('Notify.RequestTimeout'), 'error') end
                        return
                    end

                    notify(locale('Notify.RentalSuccess'), 'success')
                end,
            }
        end
    end

    local returns = rentalReturnOptions(location)
    for index = 1, #returns do
        options[#options + 1] = returns[index]
    end

    registerContext({
        id = ('forge_rental_menu_%s'):format(location.id),
        title = location.label,
        options = options,
    })
end

local function findClearSpawnPoint(spawnPoints, radius)
    spawnPoints = type(spawnPoints) == 'table' and spawnPoints or {}
    radius = numberValue(radius, 3.0)

    for index = 1, #spawnPoints do
        local spawn = vector4From(spawnPoints[index])
        local occupied = false
        local vehicles = GetGamePool('CVehicle')

        for vehicleIndex = 1, #vehicles do
            if #(vector3(spawn.x, spawn.y, spawn.z) - GetEntityCoords(vehicles[vehicleIndex])) <= radius then
                occupied = true
                break
            end
        end

        if not occupied then return spawn end
    end

    return nil
end

PRCore.callback.register('forge-rental:client:createVehicle', function(model, spawnPoints, spawnRadius, fullTankLiters)
    local spawn = findClearSpawnPoint(spawnPoints, spawnRadius)
    if not spawn then return false, false end

    local vehicle = pr_lib.fivem.streaming.createVehicle(model, vector3(spawn.x, spawn.y, spawn.z), spawn.w, {
        networked = true,
        missionEntity = true,
        placeProperly = true,
        placementType = 'vehicle',
    })

    if not vehicle or not DoesEntityExist(vehicle) then return false, false end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        NetworkRegisterEntityAsNetworked(vehicle)
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end

    if not netId or netId == 0 then
        DeleteEntity(vehicle)
        return false, false
    end

    SetNetworkIdCanMigrate(netId, true)
    setVehicleFuel(vehicle, fullTankLiters or 100.0)

    local plate = trim(GetVehicleNumberPlateText(vehicle))

    return netId, plate
end)

local function saveAdminConfig()
    local ok, result = pr_lib.callback.await('forge-rental:server:adminSaveConfig', 10000, RentalClient.adminConfig)

    if not ok then
        notify(locale('Notify.ConfigSaveFailed', tostring(result)), 'error')
        return false
    end

    RentalClient.adminConfig = result
    notify(locale('Notify.ConfigSaved'), 'success')
    return true
end

local function reloadAdminConfig()
    local ok, result = pr_lib.callback.await('forge-rental:server:adminReloadConfig', 10000)

    if not ok then
        notify(locale('Notify.ConfigLoadFailed', tostring(result)), 'error')
        return false
    end

    RentalClient.adminConfig = result
    notify(locale('Notify.ConfigReloaded'), 'success')
    return true
end

local function openAdminMain()
    local config = RentalClient.adminConfig
    local locations = getLocations(config)

    registerContext({
        id = 'forge_rental_admin_main',
        title = locale('Admin.Title'),
        menu = RentalClient.adminParent and 'forge_core_main' or nil,
        onBack = RentalClient.adminParent and function()
            SetTimeout(0, function()
                TriggerEvent('forge-core:client:openAdminMenu')
            end)
        end or nil,
        options = {
            {
                title = locale('Admin.Settings'),
                description = locale('Admin.SettingsDescription'),
                icon = 'gear-fill',
                onSelect = function()
                    RentalClient.openAdminSettings()
                end,
            },
            {
                title = locale('Admin.Locations'),
                description = locale('Admin.LocationCount', #locations),
                icon = 'geo-alt-fill',
                onSelect = function()
                    RentalClient.openAdminLocations()
                end,
            },
            {
                title = locale('Admin.Reload'),
                description = locale('Admin.ReloadDescription'),
                icon = 'arrow-clockwise',
                onSelect = function()
                    if reloadAdminConfig() then openAdminMain() end
                end,
            },
        },
    })
end

function RentalClient.openAdminSettings()
    local config = RentalClient.adminConfig
    local accounts = type(config.accounts) == 'table' and config.accounts or {}
    local billing = type(config.billing) == 'table' and config.billing or {}

    local result = inputDialog(locale('Admin.Settings'), {
        {
            type = 'select',
            label = locale('Admin.Enabled'),
            default = config.enabled and 'yes' or 'no',
            options = {
                { label = locale('Admin.Yes'), value = 'yes' },
                { label = locale('Admin.No'), value = 'no' },
            },
            required = true,
        },
        { type = 'input', label = locale('Admin.PaperworkItem'), default = config.paperworkItem or 'rental_paperwork', required = true },
        { type = 'input', label = locale('Admin.ChargeAccount'), default = billing.account or accounts.rent or 'bank', required = true },
        { type = 'number', label = locale('Admin.TimeIntervalMinutes'), default = numberValue(billing.timeIntervalMinutes, 10), required = true, min = 1 },
        { type = 'number', label = locale('Admin.PricePerInterval'), default = numberValue(billing.pricePerInterval, 10), required = true, min = 0 },
        { type = 'number', label = locale('Admin.FuelPricePerLiter'), default = numberValue(billing.fuelPricePerLiter, 10), required = true, min = 0 },
        { type = 'number', label = locale('Admin.InsuranceFee'), default = numberValue(billing.insuranceFee, 80), required = true, min = 0 },
        { type = 'number', label = locale('Admin.FullTankLiters'), default = numberValue(billing.fullTankLiters, 100.0), required = true, min = 1, max = 100 },
        { type = 'input', label = locale('Admin.RentAccount'), default = accounts.rent or 'bank', required = true },
        { type = 'input', label = locale('Admin.RefundAccount'), default = accounts.refund or 'bank', required = true },
        { type = 'number', label = locale('Admin.ReturnRadius'), default = numberValue(config.returnRadius, 5.0), required = true, min = 1 },
        { type = 'number', label = locale('Admin.ReturnVehicleRadius'), default = numberValue(config.returnVehicleRadius, 100.0), required = true, min = 5 },
        { type = 'number', label = locale('Admin.SpawnCheckRadius'), default = numberValue(config.spawnCheckRadius, 3.0), required = true, min = 1 },
    })

    if not result then return openAdminMain() end

    config.enabled = result[1] == 'yes'
    config.paperworkItem = normalizeId(result[2], 'rental_paperwork')
    config.billing = {
        account = trim(result[3]) ~= '' and trim(result[3]) or 'bank',
        timeIntervalMinutes = math.max(1, math.floor(numberValue(result[4], 10))),
        pricePerInterval = math.max(0, math.floor(numberValue(result[5], 10))),
        fuelPricePerLiter = math.max(0, math.floor(numberValue(result[6], 10))),
        insuranceFee = math.max(0, math.floor(numberValue(result[7], 80))),
        fullTankLiters = math.max(1.0, math.min(100.0, numberValue(result[8], 100.0))),
    }
    config.accounts = {
        rent = trim(result[9]) ~= '' and trim(result[9]) or config.billing.account,
        refund = trim(result[10]) ~= '' and trim(result[10]) or 'bank',
    }
    config.returnRadius = numberValue(result[11], 5.0)
    config.returnVehicleRadius = numberValue(result[12], 100.0)
    config.spawnCheckRadius = numberValue(result[13], 3.0)

    saveAdminConfig()
    openAdminMain()
end

function RentalClient.openAdminLocations()
    local config = RentalClient.adminConfig
    local locations = getLocations(config)
    local options = {
        {
            title = locale('Admin.CreateLocation'),
            description = locale('Admin.CreateLocationDescription'),
            icon = 'plus-lg',
            onSelect = function()
                RentalClient.createLocation()
            end,
        },
    }

    for index = 1, #locations do
        local location = locations[index]
        options[#options + 1] = {
            title = location.label,
            description = locale('Admin.LocationDescription', location.enabled and locale('Admin.Active') or locale('Admin.Inactive'), #(location.stock or {}), #(location.vehicleSpawn or {})),
            icon = location.enabled and 'geo-alt-fill' or 'circle',
            iconColor = location.enabled and 'green' or 'gray',
            onSelect = function()
                RentalClient.openLocation(location.id)
            end,
        }
    end

    registerContext({
        id = 'forge_rental_admin_locations',
        title = locale('Admin.Locations'),
        menu = 'forge_rental_admin_main',
        options = options,
    })
end

function RentalClient.createLocation()
    local result = inputDialog(locale('Admin.CreateLocation'), {
        { type = 'input', label = locale('Admin.Label'), required = true },
        { type = 'input', label = locale('Admin.Code'), description = locale('Admin.CodeDescription') },
        {
            type = 'select',
            label = locale('Admin.Enabled'),
            default = 'yes',
            options = {
                { label = locale('Admin.Yes'), value = 'yes' },
                { label = locale('Admin.No'), value = 'no' },
            },
            required = true,
        },
        {
            type = 'select',
            label = locale('Admin.EntityType'),
            default = 'ped',
            options = {
                { label = 'Ped', value = 'ped' },
                { label = 'Objeto', value = 'object' },
            },
            required = true,
        },
        { type = 'input', label = locale('Admin.Model'), default = 's_m_m_highsec_01', required = true },
        { type = 'number', label = locale('Admin.BlipSprite'), default = 227, required = true },
        { type = 'number', label = locale('Admin.BlipColor'), default = 5, required = true },
        { type = 'number', label = locale('Admin.BlipScale'), default = 0.8, required = true, min = 0.1, step = 0.1, precision = 1 },
    })

    if not result then return RentalClient.openAdminLocations() end

    local label = trim(result[1])
    local id = normalizeId(result[2], label)
    local locations = getLocations(RentalClient.adminConfig)

    if findLocation(RentalClient.adminConfig, id) then
        notify(locale('Admin.DuplicateLocation'), 'error')
        return RentalClient.openAdminLocations()
    end

    local location = {
        id = id,
        label = label,
        enabled = result[3] == 'yes',
        coords = nil,
        entityType = result[4],
        model = trim(result[5]),
        blip = {
            enabled = true,
            sprite = math.floor(numberValue(result[6], 227)),
            color = math.floor(numberValue(result[7], 5)),
            scale = numberValue(result[8], 0.8),
        },
        stock = {},
        vehicleSpawn = {},
    }

    notify(locale('Admin.PlaceEntityPrompt'), 'inform')
    placeRentalEntity(location.model, location.entityType, function(coords)
        if not coords then
            notify(locale('Admin.PlacementCancelled'), 'error')
            return RentalClient.openAdminLocations()
        end

        location.coords = coords
        notify(locale('Admin.PlaceSpawnsPrompt'), 'inform')
        placeVehicleSpawns('sultan', function(spawns)
            location.vehicleSpawn = type(spawns) == 'table' and spawns or {}
            locations[#locations + 1] = location
            saveAdminConfig()
            RentalClient.openLocation(location.id)
        end)
    end)
end

function RentalClient.openLocation(locationId)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location then return RentalClient.openAdminLocations() end

    registerContext({
        id = ('forge_rental_admin_location_%s'):format(location.id),
        title = location.label,
        menu = 'forge_rental_admin_locations',
        options = {
            {
                title = locale('Admin.EditLocation'),
                description = locale('Admin.EditLocationDescription', formatCoords(location.coords)),
                icon = 'pencil-fill',
                onSelect = function()
                    RentalClient.editLocation(location.id)
                end,
            },
            {
                title = locale('Admin.Stock'),
                description = locale('Admin.StockDescription', #(location.stock or {})),
                icon = 'car-front-fill',
                onSelect = function()
                    RentalClient.openStock(location.id)
                end,
            },
            {
                title = locale('Admin.Spawns'),
                description = locale('Admin.SpawnDescription', #(location.vehicleSpawn or {})),
                icon = 'p-square-fill',
                onSelect = function()
                    RentalClient.openSpawns(location.id)
                end,
            },
            {
                title = locale('Admin.Teleport'),
                description = formatCoords(location.coords),
                icon = 'cursor-fill',
                onSelect = function()
                    SetEntityCoords(PlayerPedId(), location.coords.x, location.coords.y, location.coords.z, false, false, false, false)
                    SetEntityHeading(PlayerPedId(), numberValue(location.coords.w))
                    RentalClient.openLocation(location.id)
                end,
            },
            {
                title = locale('Admin.RepositionLocation'),
                description = locale('Admin.RepositionLocationDescription'),
                icon = 'crosshair',
                onSelect = function()
                    notify(locale('Admin.PlaceEntityPrompt'), 'inform')
                    placeRentalEntity(location.model, location.entityType, function(coords)
                        if not coords then
                            notify(locale('Admin.PlacementCancelled'), 'error')
                            return RentalClient.openLocation(location.id)
                        end

                        location.coords = coords
                        saveAdminConfig()
                        RentalClient.openLocation(location.id)
                    end)
                end,
            },
            {
                title = location.enabled and locale('Admin.DisableLocation') or locale('Admin.EnableLocation'),
                icon = location.enabled and 'toggle-off' or 'toggle-on',
                iconColor = location.enabled and 'red' or 'green',
                onSelect = function()
                    location.enabled = not location.enabled
                    saveAdminConfig()
                    RentalClient.openLocation(location.id)
                end,
            },
            {
                title = locale('Admin.DeleteLocation'),
                icon = 'trash-fill',
                iconColor = 'red',
                onSelect = function()
                    RentalClient.deleteLocation(location.id)
                end,
            },
        },
    })
end

function RentalClient.editLocation(locationId)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location then return RentalClient.openAdminLocations() end

    local result = inputDialog(locale('Admin.EditLocation'), {
        { type = 'input', label = locale('Admin.Label'), default = location.label, required = true },
        {
            type = 'select',
            label = locale('Admin.Enabled'),
            default = location.enabled and 'yes' or 'no',
            options = {
                { label = locale('Admin.Yes'), value = 'yes' },
                { label = locale('Admin.No'), value = 'no' },
            },
            required = true,
        },
        {
            type = 'select',
            label = locale('Admin.EntityType'),
            default = location.entityType or 'ped',
            options = {
                { label = 'Ped', value = 'ped' },
                { label = 'Objeto', value = 'object' },
            },
            required = true,
        },
        { type = 'input', label = locale('Admin.Model'), default = location.model, required = true },
        { type = 'number', label = locale('Admin.BlipSprite'), default = location.blip and location.blip.sprite or 227, required = true },
        { type = 'number', label = locale('Admin.BlipColor'), default = location.blip and location.blip.color or 5, required = true },
        { type = 'number', label = locale('Admin.BlipScale'), default = location.blip and location.blip.scale or 0.8, required = true, min = 0.1, step = 0.1, precision = 1 },
        { type = 'input', label = locale('Admin.AnimDict'), default = location.animdata and location.animdata.dict or '' },
        { type = 'input', label = locale('Admin.AnimName'), default = location.animdata and location.animdata.anim or '' },
        { type = 'number', label = locale('Admin.AnimFlags'), default = location.animdata and location.animdata.flags or 1 },
    })

    if not result then return RentalClient.openLocation(location.id) end

    location.label = trim(result[1])
    location.enabled = result[2] == 'yes'
    location.entityType = result[3]
    location.model = trim(result[4])
    location.blip = location.blip or {}
    location.blip.enabled = true
    location.blip.sprite = math.floor(numberValue(result[5], 227))
    location.blip.color = math.floor(numberValue(result[6], 5))
    location.blip.scale = numberValue(result[7], 0.8)

    if trim(result[8]) ~= '' and trim(result[9]) ~= '' then
        location.animdata = {
            dict = trim(result[8]),
            anim = trim(result[9]),
            flags = math.floor(numberValue(result[10], 1)),
        }
    else
        location.animdata = nil
    end

    saveAdminConfig()
    RentalClient.openLocation(location.id)
end

function RentalClient.deleteLocation(locationId)
    local _, index = findLocation(RentalClient.adminConfig, locationId)
    if not index then return RentalClient.openAdminLocations() end

    table.remove(RentalClient.adminConfig.locations, index)
    saveAdminConfig()
    RentalClient.openAdminLocations()
end

function RentalClient.openStock(locationId)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location then return RentalClient.openAdminLocations() end

    location.stock = type(location.stock) == 'table' and location.stock or {}

    local options = {
        {
            title = locale('Admin.AddVehicle'),
            description = locale('Admin.AddVehicleDescription'),
            icon = 'plus-lg',
            onSelect = function()
                RentalClient.addStock(location.id)
            end,
        },
    }

    for index = 1, #location.stock do
        local item = location.stock[index]
        options[#options + 1] = {
            title = item.label,
            description = locale('Admin.VehicleDescription', item.model, formatMoney(item.price), item.enabled and locale('Admin.Active') or locale('Admin.Inactive')),
            icon = item.enabled and 'car-front' or 'circle',
            iconColor = item.enabled and 'green' or 'gray',
            onSelect = function()
                RentalClient.editStock(location.id, item.model)
            end,
        }
    end

    registerContext({
        id = ('forge_rental_admin_stock_%s'):format(location.id),
        title = locale('Admin.Stock'),
        menu = ('forge_rental_admin_location_%s'):format(location.id),
        options = options,
    })
end

function RentalClient.addStock(locationId)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location then return RentalClient.openAdminLocations() end

    local result = inputDialog(locale('Admin.AddVehicle'), {
        { type = 'input', label = locale('Admin.VehicleModel'), required = true },
        { type = 'input', label = locale('Admin.Label'), required = true },
        { type = 'number', label = locale('Admin.Price'), default = 500, required = true, min = 0 },
        {
            type = 'select',
            label = locale('Admin.Enabled'),
            default = 'yes',
            options = {
                { label = locale('Admin.Yes'), value = 'yes' },
                { label = locale('Admin.No'), value = 'no' },
            },
            required = true,
        },
    })

    if not result then return RentalClient.openStock(location.id) end

    local model = normalizeId(result[1])
    if findStock(location, model) then
        notify(locale('Admin.DuplicateVehicle'), 'error')
        return RentalClient.openStock(location.id)
    end

    location.stock[#location.stock + 1] = {
        model = model,
        label = trim(result[2]) ~= '' and trim(result[2]) or model,
        price = numberValue(result[3], 0),
        enabled = result[4] == 'yes',
    }

    saveAdminConfig()
    RentalClient.openStock(location.id)
end

function RentalClient.editStock(locationId, model)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location then return RentalClient.openAdminLocations() end

    local item, index = findStock(location, model)
    if not item then return RentalClient.openStock(location.id) end

    local result = inputDialog(locale('Admin.EditVehicle'), {
        { type = 'input', label = locale('Admin.VehicleModel'), default = item.model, required = true },
        { type = 'input', label = locale('Admin.Label'), default = item.label, required = true },
        { type = 'number', label = locale('Admin.Price'), default = item.price, required = true, min = 0 },
        {
            type = 'select',
            label = locale('Admin.Enabled'),
            default = item.enabled and 'yes' or 'no',
            options = {
                { label = locale('Admin.Yes'), value = 'yes' },
                { label = locale('Admin.No'), value = 'no' },
            },
            required = true,
        },
        {
            type = 'select',
            label = locale('Admin.Remove'),
            default = 'no',
            options = {
                { label = locale('Admin.No'), value = 'no' },
                { label = locale('Admin.Yes'), value = 'yes' },
            },
            required = true,
        },
    })

    if not result then return RentalClient.openStock(location.id) end

    if result[5] == 'yes' then
        table.remove(location.stock, index)
    else
        item.model = normalizeId(result[1])
        item.label = trim(result[2]) ~= '' and trim(result[2]) or item.model
        item.price = numberValue(result[3], 0)
        item.enabled = result[4] == 'yes'
    end

    saveAdminConfig()
    RentalClient.openStock(location.id)
end

function RentalClient.openSpawns(locationId)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location then return RentalClient.openAdminLocations() end

    location.vehicleSpawn = type(location.vehicleSpawn) == 'table' and location.vehicleSpawn or {}
    local previewModel = location.stock and location.stock[1] and location.stock[1].model or 'sultan'

    local options = {
        {
            title = locale('Admin.AddSpawn'),
            description = locale('Admin.AddSpawnDescription'),
            icon = 'plus-lg',
            onSelect = function()
                placeVehicleSpawns(previewModel, function(spawns)
                    if type(spawns) ~= 'table' or #spawns < 1 then
                        notify(locale('Admin.PlacementCancelled'), 'error')
                        return RentalClient.openSpawns(location.id)
                    end

                    for index = 1, #spawns do
                        location.vehicleSpawn[#location.vehicleSpawn + 1] = spawns[index]
                    end

                    saveAdminConfig()
                    RentalClient.openSpawns(location.id)
                end)
            end,
        },
    }

    for index = 1, #location.vehicleSpawn do
        local spawn = location.vehicleSpawn[index]
        options[#options + 1] = {
            title = locale('Admin.SpawnTitle', index),
            description = formatCoords(spawn),
            icon = 'p-square-fill',
            onSelect = function()
                RentalClient.openSpawn(location.id, index)
            end,
        }
    end

    registerContext({
        id = ('forge_rental_admin_spawns_%s'):format(location.id),
        title = locale('Admin.Spawns'),
        menu = ('forge_rental_admin_location_%s'):format(location.id),
        options = options,
    })
end

function RentalClient.openSpawn(locationId, spawnIndex)
    local location = findLocation(RentalClient.adminConfig, locationId)
    if not location or not location.vehicleSpawn or not location.vehicleSpawn[spawnIndex] then return RentalClient.openAdminLocations() end

    local spawn = location.vehicleSpawn[spawnIndex]
    local previewModel = location.stock and location.stock[1] and location.stock[1].model or 'sultan'

    registerContext({
        id = ('forge_rental_admin_spawn_%s_%s'):format(location.id, spawnIndex),
        title = locale('Admin.SpawnTitle', spawnIndex),
        menu = ('forge_rental_admin_spawns_%s'):format(location.id),
        options = {
            {
                title = locale('Admin.Teleport'),
                description = formatCoords(spawn),
                icon = 'cursor-fill',
                onSelect = function()
                    SetEntityCoords(PlayerPedId(), spawn.x, spawn.y, spawn.z, false, false, false, false)
                    SetEntityHeading(PlayerPedId(), numberValue(spawn.w))
                    RentalClient.openSpawn(location.id, spawnIndex)
                end,
            },
            {
                title = locale('Admin.UpdateSpawn'),
                description = locale('Admin.UpdateSpawnDescription'),
                icon = 'crosshair',
                onSelect = function()
                    placeVehicleSpawns(previewModel, function(spawns)
                        if type(spawns) ~= 'table' or not spawns[1] then
                            notify(locale('Admin.PlacementCancelled'), 'error')
                            return RentalClient.openSpawn(location.id, spawnIndex)
                        end

                        location.vehicleSpawn[spawnIndex] = spawns[1]
                        saveAdminConfig()
                        RentalClient.openSpawn(location.id, spawnIndex)
                    end)
                end,
            },
            {
                title = locale('Admin.RemoveSpawn'),
                icon = 'trash-fill',
                iconColor = 'red',
                onSelect = function()
                    table.remove(location.vehicleSpawn, spawnIndex)
                    saveAdminConfig()
                    RentalClient.openSpawns(location.id)
                end,
            },
        },
    })
end

PRCore.callback.register('forge-rental:client:refreshConfig', function(config)
    RentalClient.applyConfig(config)
    return true
end)

PRCore.callback.register('forge-rental:client:openAdminMenu', function(config, parent)
    RentalClient.adminConfig = config
    RentalClient.adminParent = parent == 'forge-core' and parent or nil
    openAdminMain()
    return true
end)

CreateThread(function()
    Wait(1000)

    local config = pr_lib.callback.await('forge-rental:server:getConfig', 10000)
    RentalClient.applyConfig(config)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearLocations()
end)
