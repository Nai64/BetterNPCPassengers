-- Better NPC Passengers - Russian Localization
-- TRANSLATORS: Replace the English text after each language.Add() with Russian translations
-- This is a template - fill in the Russian translations

-- Addon name
language.Add("npcpassengers.name", "Better NPC Passengers")
language.Add("npcpassengers.settings", "Настройки")

-- Navigation / Tab names
language.Add("npcpassengers.nav.general", "Общие")
language.Add("npcpassengers.nav.autojoin", "Авто-посадка")
language.Add("npcpassengers.nav.passengers", "Пассажиры")
language.Add("npcpassengers.nav.position", "Позиция")
language.Add("npcpassengers.nav.behaviour", "Поведение")
language.Add("npcpassengers.nav.keybinds", "Клавиши")
language.Add("npcpassengers.nav.hud", "HUD")
language.Add("npcpassengers.nav.driver", "Водитель")
language.Add("npcpassengers.nav.help", "Помощь")

-- General Settings
language.Add("npcpassengers.general.header", "Общие настройки")
language.Add("npcpassengers.allow_multiple", "Разрешить несколько пассажиров")
language.Add("npcpassengers.allow_multiple.help", "Позволяет нескольким NPC ехать в одном транспорте.")
language.Add("npcpassengers.exit_behavior", "Поведение при выходе")
language.Add("npcpassengers.exit_behavior.help", "Когда NPC пассажиры должны покинуть транспорт?")
language.Add("npcpassengers.exit_mode.leave_player", "Покинуть когда игрок выходит")
language.Add("npcpassengers.exit_mode.leave_attack", "Покинуть когда транспорт атакуют")
language.Add("npcpassengers.exit_mode.never", "Никогда не выходить автоматически")

-- Timing Settings
language.Add("npcpassengers.timing.header", "Тайминги")
language.Add("npcpassengers.max_attach_dist", "Макс. дистанция посадки")
language.Add("npcpassengers.max_attach_dist.help", "Максимальное расстояние (единицы) для посадки NPC в транспорт.")
language.Add("npcpassengers.detach_delay", "Задержка выхода")
language.Add("npcpassengers.detach_delay.help", "Секунды ожидания перед выходом после того как игрок покидает транспорт.")
language.Add("npcpassengers.ai_delay", "Задержка восстановления ИИ")
language.Add("npcpassengers.ai_delay.help", "Секунды ожидания перед восстановлением ИИ NPC после выхода.")
language.Add("npcpassengers.cooldown", "Время перезарядки")
language.Add("npcpassengers.cooldown.help", "Перезарядка между посадками NPC в тот же транспорт.")
language.Add("npcpassengers.passenger_limit", "Лимит пассажиров")
language.Add("npcpassengers.passenger_limit.help", "Максимум NPC в транспорте.")

-- Auto-Join Settings
language.Add("npcpassengers.autojoin.header", "Авто-посадка (Поведение отряда)")
language.Add("npcpassengers.autojoin.desc", "Дружественные NPC будут автоматически садиться в ваш транспорт когда вы в него входите - как механика отрядов в Half-Life 2!")
language.Add("npcpassengers.autojoin.enable", "Включить авто-посадку")
language.Add("npcpassengers.autojoin.enable.help", "Поблизости дружественные NPC будут автоматически присоединяться когда вы садитесь в транспорт.")
language.Add("npcpassengers.autojoin.range", "Дальность авто-посадки")
language.Add("npcpassengers.autojoin.range.help", "Максимальное расстояние для поиска NPC для авто-посадки.")
language.Add("npcpassengers.autojoin.max", "Макс. NPC для авто-посадки")
language.Add("npcpassengers.autojoin.max.help", "Максимальное количество NPC которые могут автоматически сесть за раз.")
language.Add("npcpassengers.autojoin.squad_only", "Только члены отряда")
language.Add("npcpassengers.autojoin.squad_only.help", "Только NPC с именем отряда будут автоматически садиться (для отрядов в стиле HL2).")

-- Position Settings
language.Add("npcpassengers.position.header", "Смещения позиции")
language.Add("npcpassengers.position.desc", "Точная настройка позиции NPC в транспорте. Используйте это чтобы исправить проблемы с парением или клиппингом.")
language.Add("npcpassengers.height_offset", "Смещение по высоте")
language.Add("npcpassengers.forward_offset", "Смещение вперед")
language.Add("npcpassengers.right_offset", "Смещение вправо")
language.Add("npcpassengers.angle.header", "Смещения углов")
language.Add("npcpassengers.angle.desc", "Настройка вращения NPC в транспорте.")
language.Add("npcpassengers.yaw_offset", "Рыскание (Вращение)")
language.Add("npcpassengers.pitch_offset", "Тангаж (Наклон вперед)")
language.Add("npcpassengers.roll_offset", "Крен (Наклон вбок)")

-- Behaviour Settings
language.Add("npcpassengers.behaviour.header", "Речь NPC (Расширенное)")
language.Add("npcpassengers.behaviour.desc", "Настройка того как NPC vocalize во время езды в транспорте. Голоса граждан в стиле HL2!")
language.Add("npcpassengers.speech_enable", "Включить речь NPC")
language.Add("npcpassengers.speech_enable.help", "Главный переключатель для всей речи NPC. Отключите чтобы полностью замолчить пассажиров.")
language.Add("npcpassengers.speech_volume", "Громкость речи")
language.Add("npcpassengers.speech_volume.help", "Насколько громко говорят NPC (0 = тихо, 100 = полная громкость).")
language.Add("npcpassengers.pitch_variation", "Вариация тона (+/-)")
language.Add("npcpassengers.pitch_variation.help", "Случайная вариация тона для более естественных голосов. 0 = монотонно, выше = больше разнообразия.")
language.Add("npcpassengers.crash.header", "Реакции на аварии")
language.Add("npcpassengers.crash_enable", "Включить звуки аварий")
language.Add("npcpassengers.crash_enable.help", "NPC стонут/вскрикивают когда транспорт резко замедляется (аварии, резкое торможение).")
language.Add("npcpassengers.crash_threshold", "Чувствительность к авариям")
language.Add("npcpassengers.crash_threshold.help", "Замедление необходимое для triggering звуков аварий. Ниже = более чувствительно.")
language.Add("npcpassengers.crash_cooldown", "Перезарядка звуков аварий")
language.Add("npcpassengers.crash_cooldown.help", "Минимальные секунды между звуками аварий на NPC.")

-- Keybinds
language.Add("npcpassengers.keybinds.header", "Клавиши")
language.Add("npcpassengers.keybinds.desc", "Настройка горячих клавиш для быстрых действий.")
language.Add("npcpassengers.keybind.attach", "Посадить ближайшего NPC")
language.Add("npcpassengers.keybind.attach.help", "Посадить ближайшего дружественного NPC в ваш транспорт.")
language.Add("npcpassengers.keybind.detach_all", "Высадить всех NPC")
language.Add("npcpassengers.keybind.detach_all.help", "Удалить всех пассажиров из вашего транспорта.")
language.Add("npcpassengers.keybind.toggle_autojoin", "Переключить авто-посадку")
language.Add("npcpassengers.keybind.toggle_autojoin.help", "Быстро включить/выключить авто-посадку.")
language.Add("npcpassengers.keybind.menu", "Открыть меню настроек")
language.Add("npcpassengers.keybind.menu.help", "Открыть панель настроек.")
language.Add("npcpassengers.keybind.exit_all", "Выход всех пассажиров")
language.Add("npcpassengers.keybind.exit_all.help", "Заставить всех пассажиров покинуть транспорт.")
language.Add("npcpassengers.keybind.toggle_hud", "Переключить HUD")
language.Add("npcpassengers.keybind.toggle_hud.help", "Показать/скрыть HUD пассажиров.")

-- HUD Settings
language.Add("npcpassengers.hud.header", "Настройки HUD")
language.Add("npcpassengers.hud.enable", "Включить HUD")
language.Add("npcpassengers.hud.enable.help", "Показать оверлей статуса пассажиров на экране.")
language.Add("npcpassengers.hud.position", "Позиция HUD")
language.Add("npcpassengers.hud.position.help", "Где HUD появляется на экране.")
language.Add("npcpassengers.hud.position.topleft", "Слева вверху")
language.Add("npcpassengers.hud.position.topright", "Справа вверху")
language.Add("npcpassengers.hud.position.bottomleft", "Слева внизу")
language.Add("npcpassengers.hud.position.bottomright", "Справа внизу")
language.Add("npcpassengers.hud.scale", "Масштаб HUD")
language.Add("npcpassengers.hud.scale.help", "Множитель размера для HUD.")
language.Add("npcpassengers.hud.opacity", "Прозрачность HUD")
language.Add("npcpassengers.hud.opacity.help", "Прозрачность фона (0 = невидимый, 1 = сплошной).")

-- Driver Settings
language.Add("npcpassengers.driver.header", "NPC Водитель")
language.Add("npcpassengers.driver.desc", "Разрешить NPC водить транспорт за вас.")
language.Add("npcpassengers.driver.enable", "Включить NPC водителей")
language.Add("npcpassengers.driver.enable.help", "Разрешить NPC взять контроль над транспортом.")
language.Add("npcpassengers.driver.behavior", "Поведение водителя")
language.Add("npcpassengers.driver.behavior.help", "Как NPC водит транспорт.")
language.Add("npcpassengers.driver.behavior.cruise", "Случайная поездка")
language.Add("npcpassengers.driver.behavior.follow", "Следовать за игроком")
language.Add("npcpassengers.driver.behavior.patrol", "Патруль")
language.Add("npcpassengers.driver.behavior.flee", "Бежать")
language.Add("npcpassengers.driver.behavior.parked", "Оставаться припаркованным")

-- Help / FAQ
language.Add("npcpassengers.help.header", "Часто задаваемые вопросы")
language.Add("npcpassengers.help.desc", "Быстрые ответы на общие вопросы и устранение проблем.")
language.Add("npcpassengers.help.still_need", "Все еще нужна помощь?")
language.Add("npcpassengers.help.community", "Присоединяйтесь к нашему Discord сообществу для поддержки!")

-- Status messages
language.Add("npcpassengers.status.calm", "СПОКОЕН")
language.Add("npcpassengers.status.alert", "ТРЕВОГА")
language.Add("npcpassengers.status.scared", "ИСПУГАН")
language.Add("npcpassengers.status.drowsy", "СОННЫЙ")
language.Add("npcpassengers.status.dead", "МЕРТВ")
language.Add("npcpassengers.status.calm.desc", "Расслаблен, угроз поблизости нет")
language.Add("npcpassengers.status.alert.desc", "Враг обнаружен, NPC следит за угрозами")
language.Add("npcpassengers.status.scared.desc", "Опасная езда (высокая скорость, аварии)")
language.Add("npcpassengers.status.drowsy.desc", "Долгая спокойная езда, NPC становится сонным")
language.Add("npcpassengers.status.dead.desc", "Здоровье достигло нуля")

-- Chat messages
language.Add("npcpassengers.chat.autojoin_on", "Авто-посадка: ВКЛ")
language.Add("npcpassengers.chat.autojoin_off", "Авто-посадка: ВЫКЛ")
language.Add("npcpassengers.chat.hud_on", "HUD: ВКЛ")
language.Add("npcpassengers.chat.hud_off", "HUD: ВЫКЛ")
language.Add("npcpassengers.chat.prefix", "[Better NPC Passengers]")

-- Error messages
language.Add("npcpassengers.error.no_vehicle", "Транспорта поблизости нет")
language.Add("npcpassengers.error.no_npc", "NPC поблизости нет")
language.Add("npcpassengers.error.vehicle_full", "Транспорт полон")
language.Add("npcpassengers.error.too_far", "NPC слишком далеко от транспорта")

print("[Better NPC Passengers] Russian localization loaded!")
