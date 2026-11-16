Locales = Locales or {}

Locales['ru'] = {
    ['spot_discovered']      = 'Вы обнаружили спот: %s',
    ['spot_activated']       = 'Внимание! Спот активирован: %s',
    ['enemies_remaining']    = 'Спот: %s | Враги: %s/%s',
    ['spot_cleared']         = 'Спот "%s" зачищен! Найдите ящик с хабаром.',
    ['spot_abandoned']       = 'Спот сброшен: игроки покинули зону.',
    ['search_crate']         = 'Открыть ящик с хабаром',
    ['searching_crate']      = 'Открытие ящика...',
    ['crate_already_looted'] = 'Этот ящик уже был обыскан.',
    ['crate_too_far']        = 'Вы слишком далеко от ящика.',
    ['crate_looted_title']   = 'Хабар спота',
    ['received_money']       = 'Найдено денег: +$%s',
    ['received_item']        = '%s x%s',
    ['crate_closed_notify']  = 'Хабар собран. Спот ушел на перезарядку.',
    ['inventory_full']       = 'Не все предметы поместились в инвентарь!',
    ['spot_cooldown']        = 'Спот ушел на перезарядку (%s мин).',
    ['spot_respawned']       = 'Спот "%s" снова доступен для зачистки!',

    -- Admin commands
    ['admin_only']           = 'Эта команда доступна только администраторам.',
    ['spot_not_found']       = 'Спот с ID "%s" не найден.',
    ['spot_respawned_admin'] = 'Спот "%s" принудительно перезапущен.',
    ['spots_list_header']    = '=== СПИСОК СПОТОВ ===',
    ['spots_list_item']      = '[%s] %s | Статус: %s | Враги: %s',
    ['teleported_to_spot']   = 'Телепортация на спот "%s".'
}

function _U(str, ...)
    if Locales and Locales['ru'] and Locales['ru'][str] then
        return string.format(Locales['ru'][str], ...)
    end
    return str or ''
end

