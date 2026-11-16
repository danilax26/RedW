Config = {}

-- =========================================================================
-- ОБЩИЕ НАСТРОЙКИ МОДА
-- =========================================================================
Config.Debug = false
Config.Locale = 'ru'

-- Дистанции и тайминги
Config.ActivationDistance = 65.0      -- Дистанция приближения игрока для активации спота (в метрах)
Config.DeactivationDistance = 120.0   -- Дистанция выхода из зоны, после которой тикает таймер сброса
Config.AbandonTimeout = 90            -- Время (сек) до сброса спота, если игроки убежали из зоны
Config.LootDespawnTimer = 300         -- Время (сек) жизни несобранного сундука до авто-деспавна
Config.DefaultCooldown = 300          -- Стандартный кулдаун спота после зачистки (сек)

-- Карта и метки
Config.ShowBlips = true               -- Показывать метки на глобальной карте
Config.BlipHideOnCooldown = false     -- Скрывать метку во время перезарядки спота

-- Звуки зомби
Config.ZombieGroans = true            -- Воспроизводить рычание/крики зомби при спавне и атаке

-- =========================================================================
-- ШАБЛОНЫ ВРАГОВ (ARCHETYPES)
-- =========================================================================
Config.Archetypes = {
    ['zombies'] = {
        models = {
            'a_m_m_nitefolk_01',
            'g_m_m_uniinbred_01',
            'g_m_m_unimountainmen_01',
            's_m_m_unibutchers_01',
        },
        weapons = {
            'weapon_melee_knife',
            'weapon_melee_machete',
            'weapon_melee_cleaver',
        },
        health = 220,
        combatMovement = 2,           -- Наступление на цель
        combatRange = 0,              -- Ближний бой
    },
    ['shooters'] = {
        models = {
            'a_m_m_valcriminals_01',
            'g_m_m_unibanditos_01',
            'a_m_m_unigunslinger_01',
            'a_m_m_vhtthug_01',
            'g_m_m_unicriminals_01',
        },
        weapons = {
            'weapon_revolver_cattleman',
            'weapon_repeater_carbine',
            'weapon_shotgun_pump',
            'weapon_rifle_springfield',
        },
        health = 175,
        accuracy = 35,                -- Меткость стрельбы (0-100%)
        combatMovement = 2,           -- Тактическое перемещение
        combatRange = 2,              -- Дистанционный бой
    }
}

-- =========================================================================
-- СПИСОК СПОТОВ (CONFIG.SPOTS)
-- =========================================================================
-- Доступно ДВА ТИПА СПАВНА:
-- 
-- 1) spawnType = 'exact'  -> ТОЧНЫЙ СПАВН:
--    Вы вручную указываете конкретные координаты (vector4: x, y, z, heading) для каждого врага.
--    Количество мобов автоматически равно числу указанных точек!
--    Можно задать просто координаты: vector4(x, y, z, h)
--    Либо с деталями: { coords = vector4(x, y, z, h), weapon = 'weapon_...', model = '...' }
--
-- 2) spawnType = 'area'   -> СПАВН ПО ОБЛАСТИ:
--    Враги случайно распределяются по радиусу вокруг центра (radius).
--    Вы задаете только: radius и enemyCount (число или диапазон { min = 4, max = 7 }).
-- =========================================================================

Config.Spots = {

    -- ---------------------------------------------------------------------
    -- ПРИМЕР ТИПА 1: ТОЧНЫЙ СПАВН (spawnType = 'exact')
    -- Стрелки на конкретных позициях в лагере бандитов (Клеменс-Пойнт)
    -- ---------------------------------------------------------------------
    {
        id = 'spot_bandit_camp_exact',
        name = 'Лагерь бандитов (Точный спавн)',
        spawnType = 'exact',                        -- ТИП 1: Враги появляются строго в указанных точках
        coords = vector3(1508.00, -1272.00, 76.00), -- Центр спота (проверенная высота земли)
        activationDistance = 70.0,
        prop = {
            model = 'mp005_s_posse_tent_bunk01x',   -- Антуражный проп (нары / лагерная койка)
            coords = vector3(1508.00, -1272.00, 76.00),
            heading = 180.0,
        },
        enemyType = 'shooters',                     -- 'shooters' (стрелки) или 'zombies' (зомби)
        
        -- Список точных точек для каждого врага:
        exactEnemies = {
            { coords = vector4(1503.50, -1268.20, 76.00, 45.0),  weapon = 'weapon_repeater_carbine', model = 'a_m_m_valcriminals_01' },
            { coords = vector4(1512.30, -1269.80, 76.00, 310.0), weapon = 'weapon_shotgun_pump',       model = 'g_m_m_unibanditos_01' },
            { coords = vector4(1511.00, -1276.50, 76.00, 200.0), weapon = 'weapon_revolver_cattleman',  model = 'a_m_m_unigunslinger_01' },
            { coords = vector4(1501.80, -1275.40, 76.00, 120.0), weapon = 'weapon_rifle_springfield',  model = 'a_m_m_vhtthug_01' },
        },

        lootBox = {
            model = 'p_chest01x',                   -- Модель сундука (деревянно-кованый сундук)
            coords = vector3(1509.50, -1271.00, 76.00),
            heading = 180.0,
            searchDuration = 6000,                  -- Время обыска (мс)
        },
        cooldown = 420,                             -- Перезарядка (7 минут)
        blip = {
            sprite = 'blip_ambient_camp',
            color = 'BLIP_MODIFIER_COLOR_PURPLE',
            scale = 0.2,
            label = 'Спот: Лагерь бандитов'
        },
        lootTable = {
            money = { chance = 100, currency = 'cash', min = 25.0, max = 60.0 },
            items = {
                { item = 'blood_dollar', min = 5, max = 15, chance = 80 },
                { item = 'ammo_box_rifle', min = 1, max = 2, chance = 70 },
                { item = 'ammo_box_shotgun', min = 1, max = 2, chance = 60 },
                { item = 'coffee', min = 1, max = 2, chance = 85 },
                { item = 'weapon_repeater_carbine', min = 1, max = 1, chance = 15 },
                { item = 'mexico_key', min = 1, max = 1, chance = 35 },
            }
        }
    },

    -- ---------------------------------------------------------------------
    -- ПРИМЕР ТИПА 2: СПАВН ПО ОБЛАСТИ (spawnType = 'area')
    -- Зомби случайно разбросаны вокруг разбитой повозки (Валентайн)
    -- ---------------------------------------------------------------------
    {
        id = 'spot_wagon_zombies_area',
        name = 'Разбитая повозка (Спавн по области)',
        spawnType = 'area',                         -- ТИП 2: Враги случайно спавнятся по всей зоне
        coords = vector3(-188.84, 647.22, 113.15),  -- Центр зоны возле Валентайна
        radius = 28.0,                              -- Радиус области спавна врагов
        enemyCount = { min = 4, max = 6 },          -- Сколько врагов случайно заспавнить в зоне
        activationDistance = 65.0,
        prop = {
            model = 's_wagonbroken01x',             -- Антуражный проп (разбитая повозка)
            coords = vector3(-188.84, 647.22, 113.15),
            heading = 75.0,
        },
        enemyType = 'zombies',                      -- 'zombies' (зомби) или 'shooters' (стрелки)
        lootBox = {
            model = 'p_chest01x',                   -- Модель ящика с хабаром
            coords = vector3(-186.50, 646.00, 113.15),
            heading = 75.0,
            searchDuration = 5000,
        },
        cooldown = 300,                             -- Перезарядка (5 минут)
        blip = {
            sprite = 'blip_ambient_camp',
            color = 'BLIP_MODIFIER_COLOR_RED',
            scale = 0.2,
            label = 'Спот: Разбитая повозка'
        },
        lootTable = {
            money = { chance = 100, currency = 'cash', min = 10.0, max = 25.0 },
            items = {
                { item = 'bread', min = 1, max = 3, chance = 100 },
                { item = 'water', min = 1, max = 2, chance = 90 },
                { item = 'ammo_box_revolver', min = 1, max = 2, chance = 75 },
                { item = 'ammo_box_repeater', min = 1, max = 1, chance = 50 },
                { item = 'weapon_melee_knife', min = 1, max = 1, chance = 20 },
                { item = 'mexico_key', min = 1, max = 1, chance = 25 },
            }
        }
    },

    -- ---------------------------------------------------------------------
    -- ПРИМЕР ТИПА 2: ЕЩЕ ОДИН СПАВН ПО ОБЛАСТИ (spawnType = 'area')
    -- Заброшенный схрон с ящиками и зараженными (Окрестности Изумрудного ранчо)
    -- ---------------------------------------------------------------------
    {
        id = 'spot_crates_zombies_area',
        name = 'Заброшенный схрон (Спавн по области)',
        spawnType = 'area',                         -- ТИП 2: Спавн по радиусу
        coords = vector3(1396.73, 345.73, 87.58),   -- Поля возле Эмеральд
        radius = 25.0,                              -- Радиус зоны
        enemyCount = { min = 5, max = 7 },          -- Число врагов в зоне
        activationDistance = 60.0,
        prop = {
            model = 'p_crate01x',                   -- Антуражный проп (деревянные ящики)
            coords = vector3(1396.73, 345.73, 87.58),
            heading = 40.0,
        },
        enemyType = 'zombies',
        lootBox = {
            model = 'p_chest01x',
            coords = vector3(1398.20, 346.50, 87.58),
            heading = 40.0,
            searchDuration = 5000,
        },
        cooldown = 300,
        blip = {
            sprite = 'blip_ambient_camp',
            color = 'BLIP_MODIFIER_COLOR_RED',
            scale = 0.2,
            label = 'Спот: Заброшенный схрон'
        },
        lootTable = {
            money = { chance = 100, currency = 'cash', min = 15.0, max = 30.0 },
            items = {
                { item = 'bread', min = 1, max = 3, chance = 100 },
                { item = 'beer', min = 1, max = 3, chance = 80 },
                { item = 'ammo_box_pistol', min = 1, max = 2, chance = 70 },
                { item = 'blood_cent', min = 25, max = 60, chance = 70 },
                { item = 'stew', min = 1, max = 2, chance = 40 },
                { item = 'mexico_key', min = 1, max = 1, chance = 30 },
            }
        }
    }
}
