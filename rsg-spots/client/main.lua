local RSGCore = exports['rsg-core']:GetCoreObject()

local LocalSpotStates = {}   -- [spotId] = { state = 'IDLE', aliveCount = 0, totalCount = 0, cooldownUntil = 0 }
local SpawnedProps = {}      -- [spotId] = objectHandle
local SpotBlips = {}         -- [spotId] = blipHandle

--- Получить конфиг спота по ID
local function GetSpotConfig(spotId)
    for _, spot in ipairs(Config.Spots) do
        if spot.id == spotId then return spot end
    end
    return nil
end

local function SafeSetBlipAlpha(blip, alpha)
    if SetBlipAlpha then
        SetBlipAlpha(blip, alpha)
    end
end

--- Обновление визуального стиля метки на карте
local function UpdateSpotBlip(spotId)
    if not Config.ShowBlips then return end
    local spot = GetSpotConfig(spotId)
    if not spot or not spot.blip then return end

    local stateInfo = LocalSpotStates[spotId] or { state = 'IDLE' }
    local blip = SpotBlips[spotId]

    if not blip then
        -- Создаем метку, если еще не создана
        local coords = spot.coords
        blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
        SetBlipSprite(blip, joaat(spot.blip.sprite or 'blip_ambient_camp'), true)
        SetBlipScale(blip, spot.blip.scale or 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, spot.blip.label or spot.name)
        SpotBlips[spotId] = blip
    end

    if stateInfo.state == 'COOLDOWN' and Config.BlipHideOnCooldown then
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, spot.name .. ' (Перезарядка)')
        SafeSetBlipAlpha(blip, 60)
    elseif stateInfo.state == 'ACTIVE' then
        SafeSetBlipAlpha(blip, 255)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, spot.name .. ' (В БОЮ)')
    elseif stateInfo.state == 'CLEARED' then
        SafeSetBlipAlpha(blip, 255)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, spot.name .. ' (ХАБАР ЖДЕТ)')
    else
        SafeSetBlipAlpha(blip, 220)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, spot.blip.label or spot.name)
    end
end

-- Инициализация меток при старте
CreateThread(function()
    Wait(2000)
    TriggerServerEvent('rsg-spots:server:requestAllStates')

    for _, spot in ipairs(Config.Spots) do
        UpdateSpotBlip(spot.id)
    end
end)

-- Синхронизация всех состояний при входе
RegisterNetEvent('rsg-spots:client:receiveAllStates', function(states)
    for spotId, data in pairs(states) do
        LocalSpotStates[spotId] = data
        UpdateSpotBlip(spotId)

        if data.state == 'CLEARED' and not data.looted then
            local spot = GetSpotConfig(spotId)
            if spot and spot.lootBox then
                TriggerEvent('rsg-spots:client:spotCleared', spotId, spot.lootBox)
            end
        end
    end
end)

-- Синхронизация изменения состояния спота
RegisterNetEvent('rsg-spots:client:syncSpotState', function(spotId, newState, cooldownUntil)
    LocalSpotStates[spotId] = LocalSpotStates[spotId] or {}
    LocalSpotStates[spotId].state = newState
    LocalSpotStates[spotId].cooldownUntil = cooldownUntil or 0

    UpdateSpotBlip(spotId)

    local spot = GetSpotConfig(spotId)
    if not spot then return end

    if newState == 'ACTIVE' then
        local ped = PlayerPedId()
        if #(GetEntityCoords(ped) - spot.coords) < (spot.activationDistance or Config.ActivationDistance) + 30.0 then
            lib.notify({
                title = 'RSG-SPOTS',
                description = _U('spot_activated', spot.name),
                type = 'warning',
                duration = 5000
            })
        end
    end
end)

-- Обновление счетчика врагов на споте
RegisterNetEvent('rsg-spots:client:updateSpotStatus', function(spotId, aliveCount, totalCount)
    LocalSpotStates[spotId] = LocalSpotStates[spotId] or {}
    LocalSpotStates[spotId].aliveCount = aliveCount
    LocalSpotStates[spotId].totalCount = totalCount

    local spot = GetSpotConfig(spotId)
    if not spot then return end

    local ped = PlayerPedId()
    if #(GetEntityCoords(ped) - spot.coords) <= (spot.radius or 30.0) + 15.0 then
        lib.notify({
            title = spot.name,
            description = _U('enemies_remaining', spot.name, aliveCount, totalCount),
            type = 'inform',
            duration = 3000
        })
    end
end)

-- Безопасная телепортация администратора к споту с загрузкой коллизий и уровня земли
RegisterNetEvent('rsg-spots:client:teleportToSpot', function(coords, spotName)
    local ped = PlayerPedId()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end

    FreezeEntityPosition(ped, true)

    local targetX = coords.x + 0.0
    local targetY = coords.y + 0.0
    local initialZ = (coords.z or 100.0) + 20.0

    SetEntityCoords(ped, targetX, targetY, initialZ, false, false, false, false)
    RequestCollisionAtCoord(targetX, targetY, initialZ)

    -- Ждем загрузки коллизий в чанке вокруг игрока
    local timeout = GetGameTimer() + 4000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(targetX, targetY, initialZ)
        Wait(50)
    end

    -- Сканируем уровень земли сверху вниз
    local groundZ = nil
    for offset = 40.0, -25.0, -2.5 do
        local testZ = (coords.z or 100.0) + offset
        local found, z = GetGroundZFor_3dCoord(targetX, targetY, testZ, true)
        if found and z > 0.0 then
            groundZ = z
            break
        end
        Wait(10)
    end

    local finalZ = (groundZ and groundZ > 0.0) and (groundZ + 1.0) or (coords.z + 1.5)
    SetEntityCoords(ped, targetX, targetY, finalZ, false, false, false, false)

    Wait(300)
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(500)

    lib.notify({
        title = 'RSG-SPOTS',
        description = _U('teleported_to_spot', spotName or 'Спот'),
        type = 'success'
    })
end)

-- Поток управления антуражными пропами спотов (повозка, нары, ящики)
CreateThread(function()
    while true do
        Wait(1500)
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)

        for _, spot in ipairs(Config.Spots) do
            if spot.prop and spot.prop.model then
                local propCoords = spot.prop.coords or spot.coords
                local dist = #(pCoords - propCoords)

                -- Спавним проп при приближении (до 130 метров)
                if dist < 130.0 then
                    if not SpawnedProps[spot.id] or not DoesEntityExist(SpawnedProps[spot.id]) then
                        local modelHash = joaat(spot.prop.model)
                        if IsModelInCdimage(modelHash) and IsModelValid(modelHash) then
                            RequestModel(modelHash)
                            local timeout = GetGameTimer() + 2500
                            while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
                                Wait(20)
                            end

                            if HasModelLoaded(modelHash) then
                                local heading = spot.prop.heading or 0.0
                                local spawnZ = propCoords.z + 1.0
                                local obj = CreateObject(modelHash, propCoords.x, propCoords.y, spawnZ, false, false, false)

                                if DoesEntityExist(obj) then
                                    PlaceObjectOnGroundProperly(obj)
                                    FreezeEntityPosition(obj, true)
                                    SetEntityHeading(obj, heading)
                                    SpawnedProps[spot.id] = obj
                                end

                                SetModelAsNoLongerNeeded(modelHash)
                            end
                        end
                    end
                -- Удаляем локальный проп, если игрок ушел дальше 150 метров
                elseif dist > 150.0 then
                    if SpawnedProps[spot.id] then
                        if DoesEntityExist(SpawnedProps[spot.id]) then
                            DeleteEntity(SpawnedProps[spot.id])
                        end
                        SpawnedProps[spot.id] = nil
                    end
                end
            end
        end
    end
end)

-- Поток мониторинга приближения игрока к спотам
CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if not IsEntityDead(ped) then
            local pCoords = GetEntityCoords(ped)

            for _, spot in ipairs(Config.Spots) do
                local stateInfo = LocalSpotStates[spot.id] or { state = 'IDLE' }

                if stateInfo.state == 'IDLE' then
                    local actDist = spot.activationDistance or Config.ActivationDistance
                    local dist = #(pCoords - spot.coords)

                    if dist <= actDist then
                        -- Запрашиваем у сервера активацию спота
                        TriggerServerEvent('rsg-spots:server:requestActivation', spot.id)
                        Wait(500) -- Небольшая пауза между проверками
                    end
                end
            end
        end
    end
end)

-- Очистка пропов при выгрузке ресурса
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, obj in pairs(SpawnedProps) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
    SpawnedProps = {}

    for _, blip in pairs(SpotBlips) do
        RemoveBlip(blip)
    end
    SpotBlips = {}
end)

