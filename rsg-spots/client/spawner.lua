local ActiveEnemies = {}    -- [spotId] = { { id = 1, entity = ped, dead = false }, ... }
local CompletedSpots = {}   -- [spotId] = true
local HostileRelationshipGroup = nil

--- Инициализация группы враждебности
local function EnsureHostileGroup()
    if not HostileRelationshipGroup then
        local _, group = AddRelationshipGroup('RSG_SPOTS_ENEMY')
        HostileRelationshipGroup = group or joaat('RSG_SPOTS_ENEMY')
    end

    SetRelationshipBetweenGroups(5, HostileRelationshipGroup, GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), HostileRelationshipGroup)
    SetRelationshipBetweenGroups(5, HostileRelationshipGroup, joaat('PLAYER'))
    SetRelationshipBetweenGroups(5, joaat('PLAYER'), HostileRelationshipGroup)

    local playerPed = PlayerPedId()
    local pGroup = GetPedRelationshipGroupHash(playerPed)
    if pGroup and pGroup ~= 0 then
        SetRelationshipBetweenGroups(5, HostileRelationshipGroup, pGroup)
        SetRelationshipBetweenGroups(5, pGroup, HostileRelationshipGroup)
    end

    return HostileRelationshipGroup
end

--- Найти надежную Z-координату земли для точки спавна
--- @param x number
--- @param y number
--- @param approxZ number
--- @return number
local function GetGroundZ(x, y, approxZ)
    for offset = 30.0, -20.0, -2.0 do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, approxZ + offset, true)
        if found and groundZ > 0.0 then
            return groundZ
        end
    end
    return approxZ
end

--- Безопасная быстрая загрузка модели с резервными вариантами
--- @param modelInput string|number
--- @param fallback string|number
--- @return number|nil hash
local function SafeLoadModel(modelInput, fallback)
    local modelsToTry = {
        modelInput,
        fallback,
        'a_m_m_valcriminals_01',
        'g_m_m_unibanditos_01'
    }

    for _, candidate in ipairs(modelsToTry) do
        if candidate then
            local hash = type(candidate) == 'string' and joaat(candidate) or candidate
            if hash and hash ~= 0 then
                if IsModelValid(hash) or IsModelInCdimage(hash) then
                    RequestModel(hash)
                    local timeout = GetGameTimer() + 2000
                    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
                        Wait(20)
                    end
                    if HasModelLoaded(hash) then
                        return hash
                    end
                end
            end
        end
    end

    return nil
end

--- Проверка, повержены ли абсолютно все враги на споте
local function CheckAllEnemiesDead(spotId)
    local enemies = ActiveEnemies[spotId]
    if not enemies or #enemies == 0 then return end
    if CompletedSpots[spotId] then return end

    local allDead = true
    for _, enemy in ipairs(enemies) do
        if not enemy.dead then
            allDead = false
            break
        end
    end

    if allDead then
        CompletedSpots[spotId] = true
        print(string.format('^2[RSG-SPOTS]^7 Все враги на споте "%s" повержены!', spotId))
        TriggerServerEvent('rsg-spots:server:allEnemiesKilled', spotId)
    end
end

--- Фиксация смерти врага
local function NotifyEnemyDied(spotId, enemy)
    if enemy.dead then return end
    enemy.dead = true
    print(string.format('^3[RSG-SPOTS]^7 Враг #%d на споте "%s" убит (entity: %s)',
        enemy.id, spotId, tostring(enemy.entity)))
    TriggerServerEvent('rsg-spots:server:enemyDied', spotId, enemy.id)
    CheckAllEnemiesDead(spotId)
end

--- Спавн мобов для спота (выполняется клиентом-хостом)
RegisterNetEvent('rsg-spots:client:spawnSpotEnemies', function(spotId, targetCount)
    local spot = nil
    for _, s in ipairs(Config.Spots) do
        if s.id == spotId then spot = s break end
    end
    if not spot then return end

    -- Очищаем предыдущих мобов, если они были
    if ActiveEnemies[spotId] then
        for _, enemy in ipairs(ActiveEnemies[spotId]) do
            if DoesEntityExist(enemy.entity) then
                DeleteEntity(enemy.entity)
            end
        end
    end

    ActiveEnemies[spotId] = {}
    CompletedSpots[spotId] = nil

    local archetype = Config.Archetypes[spot.enemyType] or Config.Archetypes['shooters']
    local modelsList = spot.enemyModels or archetype.models or { 'a_m_m_valcriminals_01' }
    local weaponsList = spot.enemyWeapons or archetype.weapons or { 'weapon_revolver_cattleman' }
    local fallbackModel = spot.enemyType == 'zombies' and 'g_m_m_uniinbred_01' or 'a_m_m_valcriminals_01'

    local isExact = (spot.spawnType == 'exact' or spot.spawnMode == 'fixed_points')
    local exactList = spot.exactEnemies or spot.fixedPoints or {}

    -- Количество мобов
    local count = targetCount or 4
    if not targetCount then
        if isExact and #exactList > 0 then
            count = #exactList
        elseif type(spot.enemyCount) == 'table' then
            count = math.random(spot.enemyCount.min or 3, spot.enemyCount.max or 6)
        elseif type(spot.enemyCount) == 'number' then
            count = spot.enemyCount
        end
    end

    local playerPed = PlayerPedId()
    local enemyGroup = EnsureHostileGroup()
    local enemyIds = {}

    print(string.format('^3[RSG-SPOTS]^7 Спавн %d врагов для спота "%s" (тип: %s)...',
        count, spotId, isExact and 'exact' or 'area'))

    for i = 1, count do
        local spawnPos = vector3(spot.coords.x, spot.coords.y, spot.coords.z)
        local spawnHeading = math.random(0, 360) + 0.0
        local pointModel = nil
        local pointWeapon = nil
        local pointHealth = nil

        -- 1. ТОЧНЫЙ СПАВН (EXACT)
        if isExact and #exactList > 0 then
            local pt = exactList[((i - 1) % #exactList) + 1]
            if type(pt) == 'vector4' then
                local gz = GetGroundZ(pt.x, pt.y, pt.z)
                spawnPos = vector3(pt.x, pt.y, gz)
                spawnHeading = pt.w or 0.0
            elseif type(pt) == 'table' then
                local c = pt.coords or pt
                local gz = GetGroundZ(c.x, c.y, c.z)
                spawnPos = vector3(c.x, c.y, gz)
                spawnHeading = c.w or pt.heading or 0.0
                pointModel = pt.model
                pointWeapon = pt.weapon
                pointHealth = pt.health
            end
        else
            -- 2. СПАВН ПО ОБЛАСТИ (AREA)
            local angle = math.random() * 2.0 * math.pi
            local maxR = math.max(6, math.floor(spot.radius or 25.0))
            local dist = math.random(4, maxR)
            local rx = spot.coords.x + dist * math.cos(angle)
            local ry = spot.coords.y + dist * math.sin(angle)
            local rz = GetGroundZ(rx, ry, spot.coords.z)
            spawnPos = vector3(rx, ry, rz)
        end

        local modelName = pointModel or modelsList[math.random(1, #modelsList)]
        local modelHash = SafeLoadModel(modelName, fallbackModel)

        if modelHash then
            local ped = CreatePed(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, false, 0, 0)

            if DoesEntityExist(ped) and ped ~= 0 then
                -- СРАЗУ регистрируем сущность в ActiveEnemies
                table.insert(ActiveEnemies[spotId], {
                    id = i,
                    entity = ped,
                    dead = false
                })
                table.insert(enemyIds, i)

                -- Безопасная настройка боевого ИИ
                pcall(function()
                    SetRandomOutfitVariation(ped, true)
                    SetEntityAsMissionEntity(ped, true, true)
                    SetPedCanRagdoll(ped, true)
                    TaskSetBlockingOfNonTemporaryEvents(ped, true)
                    SetPedFleeAttributes(ped, 0, 0)

                    -- Здоровье
                    local health = pointHealth or archetype.health or 200
                    SetEntityMaxHealth(ped, health)
                    SetEntityHealth(ped, health, 0)

                    -- Оружие
                    local chosenWeapon = pointWeapon or weaponsList[math.random(1, #weaponsList)]
                    if chosenWeapon and chosenWeapon ~= 'weapon_unarmed' then
                        local wHash = joaat(chosenWeapon)
                        GiveWeaponToPed(ped, wHash, 999, true, true)
                        SetCurrentPedWeapon(ped, wHash, true)
                    end

                    -- Враждебность
                    SetPedRelationshipGroupHash(ped, enemyGroup)

                    pcall(function()
                        SetPedCombatAttributes(ped, 46, true) -- AlwaysFight
                        SetPedCombatAttributes(ped, 5, true)  -- FightRegardless
                        if spot.enemyType == 'zombies' then
                            SetPedCombatAttributes(ped, 0, false)
                        else
                            SetPedCombatAttributes(ped, 0, true)
                        end
                    end)

                    -- Атака игрока
                    ClearPedTasks(ped)
                    TaskCombatPed(ped, playerPed, 0, 16)
                    if spot.enemyType == 'zombies' then
                        TaskPutPedDirectlyIntoMelee(ped, playerPed, 0.0, -1.0, 0.0, 0)
                    end
                end)

                print(string.format('^2[RSG-SPOTS]^7 Враг #%d (ped: %d, model: %s) заспавнен на (%.1f, %.1f, %.1f)',
                    i, ped, tostring(modelName), spawnPos.x, spawnPos.y, spawnPos.z))
            end

            SetModelAsNoLongerNeeded(modelHash)
        end

        Wait(50)
    end

    -- Передаем серверу число созданных мобов
    TriggerServerEvent('rsg-spots:server:registerEnemies', spotId, enemyIds)
end)

--- Моментальный перехват урона и смертей через игровой ивент
AddEventHandler('gameEventTriggered', function(eventName, args)
    if eventName == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        local isDead = args[6] == 1 or IsEntityDead(victim) or (GetEntityHealth(victim) <= 0)

        if isDead then
            for spotId, enemies in pairs(ActiveEnemies) do
                for _, enemy in ipairs(enemies) do
                    if not enemy.dead and enemy.entity == victim then
                        NotifyEnemyDied(spotId, enemy)
                        break
                    end
                end
            end
        end
    end
end)

--- Резервный поток мониторинга смертей (проверяет каждые 250мс)
CreateThread(function()
    while true do
        Wait(250)

        for spotId, enemies in pairs(ActiveEnemies) do
            local allDead = true
            local hasEnemies = #enemies > 0

            for _, enemy in ipairs(enemies) do
                if not enemy.dead then
                    local ped = enemy.entity
                    local isDead = not DoesEntityExist(ped) or IsEntityDead(ped) or GetEntityHealth(ped) <= 0

                    if isDead then
                        NotifyEnemyDied(spotId, enemy)
                    else
                        allDead = false
                    end
                end
            end

            if hasEnemies and allDead and not CompletedSpots[spotId] then
                CompletedSpots[spotId] = true
                TriggerServerEvent('rsg-spots:server:allEnemiesKilled', spotId)
            end
        end
    end
end)

--- Цикл агрессивного удержания боя (Aggro Heartbeat)
CreateThread(function()
    while true do
        Wait(2000)
        local playerPed = PlayerPedId()
        if not IsEntityDead(playerPed) then
            local pCoords = GetEntityCoords(playerPed)

            for spotId, enemies in pairs(ActiveEnemies) do
                for _, enemy in ipairs(enemies) do
                    if not enemy.dead and DoesEntityExist(enemy.entity) then
                        local ePed = enemy.entity
                        local dist = #(pCoords - GetEntityCoords(ePed))

                        if dist <= 120.0 then
                            local inCombat = false
                            pcall(function()
                                inCombat = IsPedInCombat(ePed, playerPed)
                            end)

                            if not inCombat then
                                TaskCombatPed(ePed, playerPed, 0, 16)
                            end
                        end
                    end
                end
            end
        end
    end
end)

--- Очистка мобов (удаление трупов и живых NPC спота)
RegisterNetEvent('rsg-spots:client:cleanupEnemies', function(spotId)
    CompletedSpots[spotId] = nil

    -- 1. Удаляем из локального трекера заспавненных сущностей
    if ActiveEnemies[spotId] then
        for _, enemy in ipairs(ActiveEnemies[spotId]) do
            local ped = enemy.entity
            if DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                NetworkRequestControlOfEntity(ped)
                DeletePed(ped)
                DeleteEntity(ped)
            end
        end
        ActiveEnemies[spotId] = nil
    end

    -- 2. Дополнительная зачистка всех трупов NPC в радиусе спота
    local spot = nil
    for _, s in ipairs(Config.Spots) do
        if s.id == spotId then spot = s break end
    end

    if spot then
        local peds = GetGamePool('CPed')
        local sCoords = spot.coords
        local maxRadius = (spot.radius or 35.0) + 40.0

        for _, ped in ipairs(peds) do
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) and IsEntityDead(ped) then
                local pCoord = GetEntityCoords(ped)
                if #(pCoord - sCoords) <= maxRadius then
                    SetEntityAsMissionEntity(ped, true, true)
                    NetworkRequestControlOfEntity(ped)
                    DeletePed(ped)
                    DeleteEntity(ped)
                end
            end
        end
    end
end)
