local RSGCore = exports['rsg-core']:GetCoreObject()

local SpotStates = {}

--- Получить конфигурацию спота по ID
--- @param spotId string
--- @return table|nil
function GetSpotConfig(spotId)
    for _, spot in ipairs(Config.Spots) do
        if spot.id == spotId then
            return spot
        end
    end
    return nil
end

--- Получить состояние спота в рантайме
--- @param spotId string
--- @return table
function GetSpotRuntimeState(spotId)
    if not SpotStates[spotId] then
        SpotStates[spotId] = {
            state = 'IDLE',          -- 'IDLE', 'ACTIVE', 'CLEARED', 'COOLDOWN'
            enemies = {},            -- [netId] = true/false
            aliveCount = 0,
            totalCount = 0,
            hostSource = nil,
            cooldownUntil = 0,
            abandonTimer = 0,
            looted = false,
            lootTimeout = 0
        }
    end
    return SpotStates[spotId]
end

--- Полный сброс спота в исходное состояние
--- @param spotId string
function ResetSpot(spotId)
    local state = GetSpotRuntimeState(spotId)
    local spot = GetSpotConfig(spotId)

    -- Удаляем врагов, если они были заспавнены
    if state.enemies and next(state.enemies) then
        TriggerClientEvent('rsg-spots:client:cleanupEnemies', -1, spotId)
    end

    -- Удаляем сундук, если он стоял
    TriggerClientEvent('rsg-spots:client:removeLootChest', -1, spotId)

    -- Удаляем временный инвентарь сундука из памяти rsg-inventory и базы данных
    local stashId = 'spot_stash_' .. spotId
    pcall(function()
        exports['rsg-inventory']:DeleteInventory(stashId)
        MySQL.query('DELETE FROM inventories WHERE identifier = ?', { stashId })
    end)

    state.state = 'IDLE'
    state.enemies = {}
    state.killedEnemies = {}
    state.aliveCount = 0
    state.totalCount = 0
    state.hostSource = nil
    state.cooldownUntil = 0
    state.abandonTimer = 0
    state.looted = false
    state.lootTimeout = 0
    state.stashCash = 0

    TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'IDLE', 0)

    if Config.Debug then
        print(string.format('[RSG-SPOTS] Спот "%s" сброшен в IDLE.', spotId))
    end
end

-- Инициализация всех спотов при запуске ресурса
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, spot in ipairs(Config.Spots) do
        GetSpotRuntimeState(spot.id)
    end
    print(string.format('^2[RSG-SPOTS]^7 Мод успешно запущен. Загружено спотов: %d', #Config.Spots))
end)

-- Запрос от клиента на получение текущих состояний всех спотов
RegisterNetEvent('rsg-spots:server:requestAllStates', function()
    local src = source
    local statesSummary = {}
    for _, spot in ipairs(Config.Spots) do
        local state = GetSpotRuntimeState(spot.id)
        statesSummary[spot.id] = {
            state = state.state,
            cooldownUntil = state.cooldownUntil,
            aliveCount = state.aliveCount,
            totalCount = state.totalCount,
            looted = state.looted
        }
    end
    TriggerClientEvent('rsg-spots:client:receiveAllStates', src, statesSummary)
end)

-- Запрос на активацию спота игроком (при приближении к зоне)
RegisterNetEvent('rsg-spots:server:requestActivation', function(spotId)
    local src = source
    local spot = GetSpotConfig(spotId)
    if not spot then return end

    local state = GetSpotRuntimeState(spotId)
    if state.state ~= 'IDLE' then
        return
    end

    local ped = GetPlayerPed(src)
    local coords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil

    -- Проверка расстояния, если сервер знает координаты
    if coords and #(coords) > 1.0 then
        local dist = #(coords - spot.coords)
        if dist > (spot.activationDistance or Config.ActivationDistance) + 25.0 then
            return
        end
    end

    -- Сразу вычисляем число врагов на сервере
    local isExact = (spot.spawnType == 'exact' or spot.spawnMode == 'fixed_points')
    local exactList = spot.exactEnemies or spot.fixedPoints or {}
    local enemyCount = 4

    if isExact and #exactList > 0 then
        enemyCount = #exactList
    elseif type(spot.enemyCount) == 'table' then
        enemyCount = math.random(spot.enemyCount.min or 3, spot.enemyCount.max or 6)
    elseif type(spot.enemyCount) == 'number' then
        enemyCount = spot.enemyCount
    end

    state.state = 'ACTIVE'
    state.hostSource = src
    state.abandonTimer = 0
    state.looted = false
    state.totalCount = enemyCount
    state.aliveCount = enemyCount
    state.enemies = {}
    state.killedEnemies = {}
    for i = 1, enemyCount do
        state.enemies[i] = true
    end

    print(string.format('^2[RSG-SPOTS]^7 Игрок [%d] активировал спот "%s" (врагов: %d)', src, spotId, enemyCount))

    -- Назначаем игрока хостом для сетевого спавна NPC
    TriggerClientEvent('rsg-spots:client:spawnSpotEnemies', src, spotId, enemyCount)
    TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'ACTIVE', 0)
    TriggerClientEvent('rsg-spots:client:updateSpotStatus', -1, spotId, state.aliveCount, state.totalCount)
end)

-- Регистрация сетевых сущностей заспавненных мобов хостом
RegisterNetEvent('rsg-spots:server:registerEnemies', function(spotId, enemyIds)
    local src = source
    local state = GetSpotRuntimeState(spotId)
    local spot = GetSpotConfig(spotId)
    if not spot or state.state ~= 'ACTIVE' then return end

    if enemyIds and #enemyIds > 0 then
        state.enemies = {}
        for _, id in ipairs(enemyIds) do
            state.enemies[id] = true
        end
        state.totalCount = #enemyIds

        -- Считаем актуальное количество живых, не сбрасывая уже засчитанные убийства
        local killedCount = 0
        if state.killedEnemies then
            for _ in pairs(state.killedEnemies) do
                killedCount = killedCount + 1
            end
        end
        state.aliveCount = math.max(0, state.totalCount - killedCount)

        print(string.format('^2[RSG-SPOTS]^7 На споте "%s" зарегистрировано %d врагов (хост: %d, живых: %d)', spotId, #enemyIds, src, state.aliveCount))
        TriggerClientEvent('rsg-spots:client:updateSpotStatus', -1, spotId, state.aliveCount, state.totalCount)
    end
end)

-- Уведомление о смерти одного из врагов
RegisterNetEvent('rsg-spots:server:enemyDied', function(spotId, enemyId)
    local state = GetSpotRuntimeState(spotId)
    local spot = GetSpotConfig(spotId)
    if not spot or state.state ~= 'ACTIVE' then return end

    if not state.killedEnemies then state.killedEnemies = {} end

    if not state.killedEnemies[enemyId] then
        state.killedEnemies[enemyId] = true

        local killedCount = 0
        for _ in pairs(state.killedEnemies) do
            killedCount = killedCount + 1
        end

        local total = (state.totalCount and state.totalCount > 0) and state.totalCount or 4
        state.aliveCount = math.max(0, total - killedCount)

        print(string.format('^3[RSG-SPOTS]^7 На споте "%s" убит враг #%s. Осталось живых: %d/%d',
            spotId, tostring(enemyId), state.aliveCount, state.totalCount))

        TriggerClientEvent('rsg-spots:client:updateSpotStatus', -1, spotId, state.aliveCount, state.totalCount)

        -- Если все враги перебиты -> СПОТ ЗАЧИЩЕН!
        if state.aliveCount <= 0 then
            state.state = 'CLEARED'
            state.looted = false
            state.lootTimeout = os.time() + (Config.LootDespawnTimer or 300)

            print(string.format('^2[RSG-SPOTS]^7 Спот "%s" полностью зачищен! Создаем сундук с лутом.', spotId))

            -- Подготавливаем инвентарь сундука для лута
            local stashId = 'spot_stash_' .. spotId
            PrepareSpotStash(spotId, spot, stashId)

            -- Создаем ящик с хабаром у клиентов
            TriggerClientEvent('rsg-spots:client:spotCleared', -1, spotId, spot.lootBox)
            TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'CLEARED', 0)
        end
    end
end)

-- Резервное событие: гарантированный триггер зачистки спота от клиента
RegisterNetEvent('rsg-spots:server:allEnemiesKilled', function(spotId)
    local state = GetSpotRuntimeState(spotId)
    local spot = GetSpotConfig(spotId)
    if not spot or state.state ~= 'ACTIVE' then return end

    state.aliveCount = 0
    state.state = 'CLEARED'
    state.looted = false
    state.lootTimeout = os.time() + (Config.LootDespawnTimer or 300)

    print(string.format('^2[RSG-SPOTS]^7 Все враги спота "%s" мертвы! Создаем сундук с лутом.', spotId))

    -- Подготавливаем инвентарь сундука для лута
    local stashId = 'spot_stash_' .. spotId
    PrepareSpotStash(spotId, spot, stashId)

    TriggerClientEvent('rsg-spots:client:updateSpotStatus', -1, spotId, 0, state.totalCount)
    TriggerClientEvent('rsg-spots:client:spotCleared', -1, spotId, spot.lootBox)
    TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'CLEARED', 0)
end)

-- Запрос на открытие ящика с хабаром (открытие инвентаря)
RegisterNetEvent('rsg-spots:server:openLootChest', function(spotId)
    local src = source
    local spot = GetSpotConfig(spotId)
    if not spot then return end

    local state = GetSpotRuntimeState(spotId)
    if state.state ~= 'CLEARED' or state.looted then
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('crate_looted_title'),
            description = _U('crate_already_looted'),
            type = 'error'
        })
        return
    end

    -- Проверка дистанции игрока до сундука
    local ped = GetPlayerPed(src)
    local pCoords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil
    local boxCoords = (spot.lootBox and spot.lootBox.coords) or spot.coords
    local targetCoords = vector3(boxCoords.x, boxCoords.y, boxCoords.z)

    -- Проверяем дистанцию, только если серверные координаты синхронизированы и не равны (0, 0, 0)
    if pCoords and #(pCoords) > 1.0 then
        local dist = #(pCoords - targetCoords)
        local maxAllowed = math.max(35.0, (spot.radius or 25.0) + 15.0)

        if dist > maxAllowed then
            print(string.format('^3[RSG-SPOTS]^7 Игрок [%d] попытался открыть ящик спота "%s", но слишком далеко (дистанция: %.1fм, макс: %.1fм)',
                src, spotId, dist, maxAllowed))
            TriggerClientEvent('ox_lib:notify', src, {
                title = _U('crate_looted_title'),
                description = _U('crate_too_far'),
                type = 'error'
            })
            return
        end
    end

    -- СРАЗУ удаляем все трупы врагов со спота при открытии/облутывании ящика!
    TriggerClientEvent('rsg-spots:client:cleanupEnemies', -1, spotId)

    -- Начисление денег в кошелек игрока (если они выпали в луте)
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player and state.stashCash and state.stashCash > 0 then
        Player.Functions.AddMoney('cash', state.stashCash, 'spot-loot-' .. spotId)
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('crate_looted_title'),
            description = _U('received_money', string.format('%.2f', state.stashCash)),
            type = 'success',
            duration = 5000
        })
        state.stashCash = 0
    end

    -- Открываем инвентарь сундука через rsg-inventory
    local stashId = 'spot_stash_' .. spotId
    local stashData = {
        label = spot.name .. ' (Хабар)',
        maxweight = 100000,
        slots = 24
    }

    local success = pcall(function()
        exports['rsg-inventory']:OpenInventory(src, stashId, stashData)
    end)

    if not success then
        -- Резервное поведение, если инвентарь не удалось открыть
        print(string.format('^1[RSG-SPOTS]^7 Ошибка открытия инвентаря "%s", выдаем лут напрямую.', stashId))
        GiveSpotLoot(src, spot)
        state.looted = true
        state.state = 'COOLDOWN'
        local cooldownDuration = spot.cooldown or Config.DefaultCooldown
        state.cooldownUntil = os.time() + cooldownDuration
        TriggerClientEvent('rsg-spots:client:removeLootChest', -1, spotId)
        TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'COOLDOWN', state.cooldownUntil)
    end
end)

-- Обработка закрытия инвентаря сундука спота (завершение сбора хабара)
RegisterNetEvent('rsg-inventory:server:closeInventory', function(inventory)
    if not inventory or type(inventory) ~= 'string' then return end
    local spotId = inventory:match('^spot_stash_(.+)$')
    if not spotId then return end

    local spot = GetSpotConfig(spotId)
    if not spot then return end

    local state = GetSpotRuntimeState(spotId)
    if state.state == 'CLEARED' then
        state.looted = true
        state.state = 'COOLDOWN'
        local cooldownDuration = spot.cooldown or Config.DefaultCooldown
        state.cooldownUntil = os.time() + cooldownDuration

        -- Удаляем ящик и окончательно чистим трупы у всех клиентов
        TriggerClientEvent('rsg-spots:client:removeLootChest', -1, spotId)
        TriggerClientEvent('rsg-spots:client:cleanupEnemies', -1, spotId)
        TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'COOLDOWN', state.cooldownUntil)

        -- Уведомление игроку о закрытии и уходе спота на перезарядку
        TriggerClientEvent('ox_lib:notify', source, {
            title = _U('crate_looted_title'),
            description = _U('crate_closed_notify'),
            type = 'inform',
            duration = 4000
        })

        -- Удаляем временный инвентарь сундука
        pcall(function()
            exports['rsg-inventory']:DeleteInventory(inventory)
            MySQL.query('DELETE FROM inventories WHERE identifier = ?', { inventory })
        end)

        if Config.Debug then
            print(string.format('[RSG-SPOTS] Игрок [%d] закрыл инвентарь сундука "%s". Спот ушел на кулдаун %d сек.',
                source, spotId, cooldownDuration))
        end
    end
end)

-- Запрос на сбор лута из сундука (прямой сбор / fallback)
RegisterNetEvent('rsg-spots:server:claimLoot', function(spotId)
    local src = source
    local spot = GetSpotConfig(spotId)
    if not spot then return end

    local state = GetSpotRuntimeState(spotId)
    if state.state ~= 'CLEARED' or state.looted then
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('crate_looted_title'),
            description = _U('crate_already_looted'),
            type = 'error'
        })
        return
    end

    -- Проверка дистанции игрока до сундука
    local ped = GetPlayerPed(src)
    local pCoords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil
    local boxCoords = (spot.lootBox and spot.lootBox.coords) or spot.coords
    local targetCoords = vector3(boxCoords.x, boxCoords.y, boxCoords.z)

    -- Проверяем дистанцию, только если серверные координаты синхронизированы и не равны (0, 0, 0)
    if pCoords and #(pCoords) > 1.0 then
        local dist = #(pCoords - targetCoords)
        local maxAllowed = math.max(35.0, (spot.radius or 25.0) + 15.0)

        if dist > maxAllowed then
            print(string.format('^3[RSG-SPOTS]^7 Игрок [%d] попытался залутать ящик спота "%s", но слишком далеко (дистанция: %.1fм, макс: %.1fм)',
                src, spotId, dist, maxAllowed))
            TriggerClientEvent('ox_lib:notify', src, {
                title = _U('crate_looted_title'),
                description = _U('crate_too_far'),
                type = 'error'
            })
            return
        end
    end

    -- Фиксируем сбор лута
    state.looted = true
    state.state = 'COOLDOWN'
    local cooldownDuration = spot.cooldown or Config.DefaultCooldown
    state.cooldownUntil = os.time() + cooldownDuration

    -- Удаляем ящик и трупы у всех клиентов
    TriggerClientEvent('rsg-spots:client:removeLootChest', -1, spotId)
    TriggerClientEvent('rsg-spots:client:cleanupEnemies', -1, spotId)
    TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spotId, 'COOLDOWN', state.cooldownUntil)

    -- Очищаем инвентарь сундука
    local stashId = 'spot_stash_' .. spotId
    pcall(function()
        exports['rsg-inventory']:DeleteInventory(stashId)
        MySQL.query('DELETE FROM inventories WHERE identifier = ?', { stashId })
    end)

    -- Выдаем награду игроку
    GiveSpotLoot(src, spot)

    if Config.Debug then
        print(string.format('[RSG-SPOTS] Игрок [%d] собрал лут со спота "%s". Спот на кулдауне %d сек.',
            src, spotId, cooldownDuration))
    end
end)

-- Обработка отключения игрока (защита от краша/выхода хоста спота)
AddEventHandler('playerDropped', function(reason)
    local src = source
    for _, spot in ipairs(Config.Spots) do
        local state = GetSpotRuntimeState(spot.id)
        if state.state == 'ACTIVE' and state.hostSource == src then
            local newHost = nil
            local deactDist = spot.deactivationDistance or Config.DeactivationDistance
            for _, playerId in ipairs(GetPlayers()) do
                local p = tonumber(playerId)
                if p and p ~= src then
                    local pPed = GetPlayerPed(p)
                    if DoesEntityExist(pPed) then
                        local coords = GetEntityCoords(pPed)
                        if #(coords - spot.coords) <= deactDist then
                            newHost = p
                            break
                        end
                    end
                end
            end

            if newHost then
                state.hostSource = newHost
                if Config.Debug then
                    print(string.format('[RSG-SPOTS] Хост спота "%s" отключился. Новый хост: [%d]', spot.id, newHost))
                end
            else
                if Config.Debug then
                    print(string.format('[RSG-SPOTS] Хост спота "%s" отключился, игроков рядом нет. Сброс спота.', spot.id))
                end
                ResetSpot(spot.id)
            end
        end
    end
end)

-- Периодический цикл проверки деспавна, покидания зоны и окончания кулдауна
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()

        for _, spot in ipairs(Config.Spots) do
            local state = GetSpotRuntimeState(spot.id)

            -- 1. Проверка кулдауна
            if state.state == 'COOLDOWN' then
                if now >= state.cooldownUntil then
                    ResetSpot(spot.id)
                    if Config.Debug then
                        print(string.format('[RSG-SPOTS] Кулдаун спота "%s" завершен. Готов к новой зачистке.', spot.id))
                    end
                end

            -- 2. Проверка зачищенного, но несобранного сундука (деспавн по таймеру)
            elseif state.state == 'CLEARED' and not state.looted then
                if now >= state.lootTimeout then
                    if Config.Debug then
                        print(string.format('[RSG-SPOTS] Сундук на споте "%s" не был собран вовремя. Деспавн.', spot.id))
                    end
                    state.state = 'COOLDOWN'
                    state.cooldownUntil = now + (spot.cooldown or Config.DefaultCooldown)
                    TriggerClientEvent('rsg-spots:client:removeLootChest', -1, spot.id)
                    TriggerClientEvent('rsg-spots:client:cleanupEnemies', -1, spot.id)
                    TriggerClientEvent('rsg-spots:client:syncSpotState', -1, spot.id, 'COOLDOWN', state.cooldownUntil)

                    local stashId = 'spot_stash_' .. spot.id
                    pcall(function()
                        exports['rsg-inventory']:DeleteInventory(stashId)
                        MySQL.query('DELETE FROM inventories WHERE identifier = ?', { stashId })
                    end)
                end

            -- 3. Проверка покидания зоны игроками на активном споте
            elseif state.state == 'ACTIVE' then
                local playerNear = false
                local deactDist = spot.deactivationDistance or Config.DeactivationDistance

                for _, playerId in ipairs(GetPlayers()) do
                    local ped = GetPlayerPed(playerId)
                    if DoesEntityExist(ped) then
                        local coords = GetEntityCoords(ped)
                        if #(coords - spot.coords) <= deactDist then
                            playerNear = true
                            break
                        end
                    end
                end

                if not playerNear then
                    state.abandonTimer = state.abandonTimer + 5
                    if state.abandonTimer >= (Config.AbandonTimeout or 90) then
                        if Config.Debug then
                            print(string.format('[RSG-SPOTS] Игроки покинули спот "%s". Сброс.', spot.id))
                        end
                        ResetSpot(spot.id)
                    end
                else
                    state.abandonTimer = 0
                end
            end
        end
    end
end)
