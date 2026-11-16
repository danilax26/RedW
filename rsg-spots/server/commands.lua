local RSGCore = exports['rsg-core']:GetCoreObject()

--- Команда: Список всех спотов и их текущих статусов
RSGCore.Commands.Add('spots_list', 'Показать статус всех спотов сервера', {}, false, function(source, args)
    if source ~= 0 then
        local Player = RSGCore.Functions.GetPlayer(source)
        if not Player then return end
    end

    local lines = { _U('spots_list_header') }

    for _, spot in ipairs(Config.Spots) do
        local stateInfo = GetSpotRuntimeState(spot.id)
        local statusStr = stateInfo.state
        local enemyStr = '0/0'

        if stateInfo.state == 'ACTIVE' then
            enemyStr = string.format('%d/%d', stateInfo.aliveCount, stateInfo.totalCount)
        elseif stateInfo.state == 'COOLDOWN' then
            local timeLeft = math.max(0, stateInfo.cooldownUntil - os.time())
            statusStr = string.format('COOLDOWN (%dс)', timeLeft)
        end

        table.insert(lines, _U('spots_list_item', spot.id, spot.name, statusStr, enemyStr))
    end

    local result = table.concat(lines, '\n')
    if source == 0 then
        print(result)
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = { 255, 180, 50 },
            multiline = true,
            args = { 'RSG-SPOTS', result }
        })
    end
end, 'admin')

--- Команда: Принудительный перезапуск спота
RSGCore.Commands.Add('spots_respawn', 'Принудительно перезапустить спот (или all)', {
    { name = 'id', help = 'ID спота (или "all" для всех)' }
}, true, function(source, args)
    local targetId = args[1]
    if not targetId then
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'RSG-SPOTS',
                description = 'Укажите ID спота или "all"',
                type = 'error'
            })
        end
        return
    end

    if targetId:lower() == 'all' then
        for _, spot in ipairs(Config.Spots) do
            ResetSpot(spot.id)
        end
        local msg = 'Все споты были успешно перезапущены.'
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { title = 'RSG-SPOTS', description = msg, type = 'success' })
        else
            print('[RSG-SPOTS] ' .. msg)
        end
    else
        local spot = GetSpotConfig(targetId)
        if not spot then
            local err = _U('spot_not_found', targetId)
            if source ~= 0 then
                TriggerClientEvent('ox_lib:notify', source, { title = 'RSG-SPOTS', description = err, type = 'error' })
            else
                print('[RSG-SPOTS] ' .. err)
            end
            return
        end

        ResetSpot(targetId)
        local ok = _U('spot_respawned_admin', spot.name)
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { title = 'RSG-SPOTS', description = ok, type = 'success' })
        else
            print('[RSG-SPOTS] ' .. ok)
        end
    end
end, 'admin')

--- Команда: Телепортация администратора к споту
RSGCore.Commands.Add('spots_tp', 'Телепортироваться к координатам спота', {
    { name = 'id', help = 'ID спота' }
}, true, function(source, args)
    if source == 0 then
        print('[RSG-SPOTS] Нельзя телепортироваться из консоли сервера!')
        return
    end

    local targetId = args[1]
    local spot = GetSpotConfig(targetId)
    if not spot then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'RSG-SPOTS',
            description = _U('spot_not_found', tostring(targetId)),
            type = 'error'
        })
        return
    end

    -- Передаем телепортацию клиенту для безопасной загрузки коллизий и уровня земли
    TriggerClientEvent('rsg-spots:client:teleportToSpot', source, spot.coords, spot.name)
end, 'admin')

