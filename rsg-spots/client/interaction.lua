local RSGCore = exports['rsg-core']:GetCoreObject()
local SpawnedChests = {} -- [spotId] = { entity = obj, coords = vector3, duration = number, blip = blipHandle }
local isLooting = false

--- Надежный поиск Z-координаты земли
local function GetGroundZ(x, y, approxZ)
    for offset = 20.0, -20.0, -1.5 do
        local found, gz = GetGroundZFor_3dCoord(x, y, approxZ + offset, true)
        if found and gz > 0.0 then
            return gz
        end
    end
    return approxZ
end

--- Безопасная загрузка модели сундука с несколькими проверенными резервными вариантами
--- @param preferredModel string|number
--- @return number|nil hash, string|nil usedName
local function SafeLoadChestModel(preferredModel)
    local candidates = {
        preferredModel,
        'p_chest01x',
        'p_crate01x',
        'p_bag01x'
    }

    for _, modelName in ipairs(candidates) do
        if modelName and modelName ~= '' then
            local hash = type(modelName) == 'string' and joaat(modelName) or modelName
            if hash and hash ~= 0 then
                RequestModel(hash)
                local timeout = GetGameTimer() + 3000
                while not HasModelLoaded(hash) and GetGameTimer() < timeout do
                    Wait(20)
                end
                if HasModelLoaded(hash) then
                    return hash, modelName
                end
            end
        end
    end

    return nil, nil
end

--- Создание сундука на клиенте
local function CreateLootChest(spotId, lootBoxData)
    if not lootBoxData then return end

    -- Если ящик уже есть, удаляем старый
    if SpawnedChests[spotId] then
        if DoesEntityExist(SpawnedChests[spotId].entity) then
            DeleteEntity(SpawnedChests[spotId].entity)
        end
        if SpawnedChests[spotId].blip then
            RemoveBlip(SpawnedChests[spotId].blip)
        end
        SpawnedChests[spotId] = nil
    end

    local modelHash, usedModel = SafeLoadChestModel(lootBoxData.model)
    if not modelHash then
        print(string.format('^1[RSG-SPOTS ERROR]^7 Не удалось загрузить ни одну модель сундука для спота "%s"!', spotId))
        return
    end

    local coords = lootBoxData.coords
    local cx = coords.x or coords[1]
    local cy = coords.y or coords[2]
    local cz = coords.z or coords[3]
    local heading = lootBoxData.heading or 0.0

    local groundZ = GetGroundZ(cx, cy, cz)
    local obj = CreateObject(modelHash, cx, cy, groundZ, false, false, false)

    if DoesEntityExist(obj) then
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
        SetEntityHeading(obj, heading)
        SetEntityAsMissionEntity(obj, true, true)

        local actualCoords = GetEntityCoords(obj)

        -- Создаем яркую золотую метку на сундуке
        local chestBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, actualCoords.x, actualCoords.y, actualCoords.z)
        SetBlipSprite(chestBlip, joaat('blip_ambient_camp'), true)
        SetBlipScale(chestBlip, 0.25)
        Citizen.InvokeNative(0x9CB1A1623062F402, chestBlip, 'Сундук с хабаром')
        Citizen.InvokeNative(0x662D364AB941DB58, chestBlip, joaat('BLIP_MODIFIER_COLOR_YELLOW'))

        SpawnedChests[spotId] = {
            entity = obj,
            coords = actualCoords,
            duration = lootBoxData.searchDuration or 3000,
            blip = chestBlip
        }

        print(string.format('^2[RSG-SPOTS]^7 Сундук успешно заспавнен на споте "%s" (модель: %s, координаты: %.2f, %.2f, %.2f)',
            spotId, tostring(usedModel), actualCoords.x, actualCoords.y, actualCoords.z))
    end

    SetModelAsNoLongerNeeded(modelHash)
end

--- Спавн ящика с хабаром при зачистке спота
RegisterNetEvent('rsg-spots:client:spotCleared', function(spotId, lootBoxData)
    if not lootBoxData then return end

    CreateLootChest(spotId, lootBoxData)

    -- Звуковой и визуальный эффект завершения
    PlaySoundFrontend('CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true, 1)

    local spotName = spotId
    for _, s in ipairs(Config.Spots) do
        if s.id == spotId then spotName = s.name break end
    end

    lib.notify({
        title = 'RSG-SPOTS',
        description = _U('spot_cleared', spotName),
        type = 'success',
        duration = 8000
    })
end)

--- Удаление ящика с хабаром (после сбора лута или деспавна)
RegisterNetEvent('rsg-spots:client:removeLootChest', function(spotId)
    if SpawnedChests[spotId] then
        if DoesEntityExist(SpawnedChests[spotId].entity) then
            DeleteEntity(SpawnedChests[spotId].entity)
        end
        if SpawnedChests[spotId].blip then
            RemoveBlip(SpawnedChests[spotId].blip)
        end
        SpawnedChests[spotId] = nil
    end
end)

--- Запуск процесса обыска ящика игроком
--- @param spotId string
local function StartLooting(spotId)
    local chestData = SpawnedChests[spotId]
    if not chestData or isLooting then return end

    isLooting = true
    local ped = PlayerPedId()

    -- Анимация осмотра / обыска земли
    TaskStartScenarioInPlace(ped, joaat('WORLD_HUMAN_CROUCH_INSPECT'), 0, true)

    local completed = lib.progressBar({
        duration = chestData.duration or 3000,
        label = _U('searching_crate'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            combat = true,
            mouse = false
        }
    })

    ClearPedTasks(ped)
    isLooting = false

    if completed then
        TriggerServerEvent('rsg-spots:server:openLootChest', spotId)
    end
end

--- Отрисовка 3D-текста над ящиком
--- @param coords vector3
--- @param text string
local function DrawText3D(coords, text)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if onScreen then
        SetTextColor(255, 255, 255, 220)
        SetTextScale(0.35, 0.35)
        SetTextFontForCurrentCommand(1)
        SetTextCentre(1)
        local str = CreateVarString(10, "LITERAL_STRING", text, Citizen.ResultAsLong())
        DisplayText(str, screenX, screenY)
    end
end

--- Цикл взаимодействия с сундуками
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)

        for spotId, chestData in pairs(SpawnedChests) do
            if DoesEntityExist(chestData.entity) then
                local dist = #(pCoords - chestData.coords)

                -- 3D-текст виден с расстояния до 25 метров для легкого обнаружения в лагере
                if dist < 25.0 then
                    sleep = 4
                    local textZ = chestData.coords.z + 0.65
                    DrawText3D(vector3(chestData.coords.x, chestData.coords.y, textZ), '[~e~E~q~] ' .. _U('search_crate'))

                    if dist < 2.5 and not isLooting then
                        if IsControlJustPressed(0, 0xCEFD9220) then -- Клавиша [E] в RedM
                            StartLooting(spotId)
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- Очистка при перезагрузке ресурса
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for spotId, chestData in pairs(SpawnedChests) do
        if DoesEntityExist(chestData.entity) then
            DeleteEntity(chestData.entity)
        end
        if chestData.blip then
            RemoveBlip(chestData.blip)
        end
    end
    SpawnedChests = {}
end)
