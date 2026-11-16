local RSGCore = exports['rsg-core']:GetCoreObject()

--- Выдача наград игроку из таблицы лута спота
--- @param source number Идентификатор игрока
--- @param spot table Данные спота из Config.Spots
function GiveSpotLoot(source, spot)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end

    local lootTable = spot.lootTable
    if not lootTable then return end

    local receivedList = {}

    -- 1. Выдача денег
    if lootTable.money and lootTable.money.chance then
        local roll = math.random(1, 100)
        if roll <= lootTable.money.chance then
            local minMoney = lootTable.money.min or 5.0
            local maxMoney = lootTable.money.max or 15.0
            local rawAmount = minMoney + (math.random() * (maxMoney - minMoney))
            local amount = math.floor(rawAmount * 100) / 100 -- округление до центов
            local currency = lootTable.money.currency or 'cash'

            if amount > 0 then
                Player.Functions.AddMoney(currency, amount, 'spot-loot-' .. spot.id)
                table.insert(receivedList, _U('received_money', string.format('%.2f', amount)))
            end
        end
    end

    -- 2. Выдача предметов
    if lootTable.items and #lootTable.items > 0 then
        for _, itemData in ipairs(lootTable.items) do
            local roll = math.random(1, 100)
            if roll <= (itemData.chance or 100) then
                local minCount = itemData.min or 1
                local maxCount = itemData.max or 1
                local count = math.random(minCount, maxCount)

                if count > 0 then
                    local success = Player.Functions.AddItem(itemData.item, count, false, false, 'spot-loot-' .. spot.id)
                    local itemInfo = RSGCore.Shared.Items[itemData.item]
                    local itemLabel = itemInfo and itemInfo.label or itemData.item

                    if success then
                        table.insert(receivedList, _U('received_item', itemLabel, count))
                    else
                        TriggerClientEvent('ox_lib:notify', source, {
                            title = _U('crate_looted_title'),
                            description = _U('inventory_full'),
                            type = 'warning',
                            duration = 4000
                        })
                    end
                end
            end
        end
    end

    -- 3. Отправка итогового уведомления
    if #receivedList > 0 then
        local description = table.concat(receivedList, '\n')
        TriggerClientEvent('ox_lib:notify', source, {
            title = _U('crate_looted_title'),
            description = description,
            type = 'success',
            duration = 6000
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = _U('crate_looted_title'),
            description = 'В ящике ничего ценного не нашлось...',
            type = 'inform',
            duration = 4000
        })
    end
end

--- Подготовка и наполнение инвентаря сундука предметами в rsg-inventory
--- @param spotId string
--- @param spot table
--- @param stashId string
function PrepareSpotStash(spotId, spot, stashId)
    local state = GetSpotRuntimeState(spotId)
    local lootTable = spot.lootTable
    if not lootTable then return end

    -- Очищаем старый инвентарь сундука из памяти rsg-inventory и базы данных
    pcall(function()
        exports['rsg-inventory']:DeleteInventory(stashId)
        MySQL.query('DELETE FROM inventories WHERE identifier = ?', { stashId })
    end)

    -- Создаем свежий инвентарь сундука
    local stashData = {
        label = spot.name .. ' (Хабар)',
        maxweight = 100000,
        slots = 24
    }
    pcall(function()
        exports['rsg-inventory']:CreateInventory(stashId, stashData)
    end)

    -- 1. Считаем деньги (будут начислены в кошелек игрока при открытии ящика)
    state.stashCash = 0
    if lootTable.money and lootTable.money.chance then
        local roll = math.random(1, 100)
        if roll <= lootTable.money.chance then
            local minMoney = lootTable.money.min or 5.0
            local maxMoney = lootTable.money.max or 15.0
            local rawAmount = minMoney + (math.random() * (maxMoney - minMoney))
            state.stashCash = math.floor(rawAmount * 100) / 100
        end
    end

    -- 2. Генерируем предметы и добавляем их в инвентарь сундука для перетаскивания
    if lootTable.items and #lootTable.items > 0 then
        local slotIndex = 1
        for _, itemData in ipairs(lootTable.items) do
            local roll = math.random(1, 100)
            if roll <= (itemData.chance or 100) then
                local minCount = itemData.min or 1
                local maxCount = itemData.max or 1
                local count = math.random(minCount, maxCount)

                if count > 0 then
                    pcall(function()
                        local added = exports['rsg-inventory']:AddItem(stashId, itemData.item, count, slotIndex, nil, 'spot-reward')
                        if added then
                            slotIndex = slotIndex + 1
                        end
                    end)
                end
            end
        end
    end

    if Config.Debug then
        print(string.format('[RSG-SPOTS] Инвентарь "%s" подготовлен с предметами для спота "%s".', stashId, spotId))
    end
end

