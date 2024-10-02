-- Import modules
local menu = require("menu")
menu.plugin_enabled:set(false)
local menu_renderer = require("graphics.menu_renderer")
local revive = require("data.revive")
local explorer = require("data.explorer")
local automindcage = require("data.automindcage")
local actors = require("data.actors")
local waypoint_loader = require("functions.waypoint_loader")
local interactive_patterns = require("enums.interactive_patterns")
local Movement = require("functions.movement")
local ChestsInteractor = require("functions.chests_interactor")
local teleport = require("data.teleport")
local GameStateChecker = require("functions.game_state_checker")
local maidenmain = require("data.maidenmain")
maidenmain.init()

-- Initialize variables
local plugin_enabled = false
local doorsEnabled = false
local loopEnabled = false
local revive_enabled = false
local profane_mindcage_enabled = false
local profane_mindcage_count = 0
local graphics_enabled = false
local was_in_helltide = false
local last_cleanup_time = get_time_since_inject()
local cleanup_interval = 300 -- 5 minutos
local maidenmain_enabled = false
local last_teleport_attempt = 0
local teleport_cooldown = 10 -- segundos

-- Plugin state
local PluginState = {
    IDLE = "idle",
    HELLTIDE = "helltide",
    TELEPORTING = "teleporting",
    FARMING = "farming",
    ERROR = "error"
}
local current_state = PluginState.IDLE

local function periodic_cleanup()
    local current_time = get_time_since_inject()
    if current_time - last_cleanup_time > cleanup_interval then
        collectgarbage("collect")
        ChestsInteractor.clearInteractedObjects()
        waypoint_loader.clear_cached_waypoints()
        last_cleanup_time = current_time
        console.print("Limpeza periódica realizada")
    end
end

local function load_and_set_waypoints(is_maiden)
    local waypoints, _ = waypoint_loader.load_route(nil, is_maiden)
    if waypoints then
        local randomized_waypoints = {}
        for _, wp in ipairs(waypoints) do
            table.insert(randomized_waypoints, waypoint_loader.randomize_waypoint(wp))
        end
        Movement.set_waypoints(randomized_waypoints)
        Movement.set_moving(true)
        console.print("Waypoints carregados e definidos com sucesso.")
    else
        console.print("Falha ao carregar waypoints. Verifique os arquivos de waypoints.")
        current_state = PluginState.ERROR
    end
end

local function update_menu_states()
    local new_plugin_enabled = menu.plugin_enabled:get()
    local new_maidenmain_enabled = maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:get()

    if new_plugin_enabled and new_maidenmain_enabled then
        if plugin_enabled then
            new_maidenmain_enabled = false
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
            console.print("Plugin Maidenmain desativado devido a conflito com o plugin principal")
        else
            new_plugin_enabled = false
            menu.plugin_enabled:set(false)
            console.print("Plugin principal desativado devido a conflito com o plugin Maidenmain")
        end
    end

    if new_plugin_enabled ~= plugin_enabled then
        plugin_enabled = new_plugin_enabled
        console.print("Plugin de Movimento " .. (plugin_enabled and "ativado" or "desativado"))
        if plugin_enabled then
            load_and_set_waypoints(false)
        else
            Movement.save_last_index()
            Movement.set_moving(false)
        end
    end

    if new_maidenmain_enabled ~= maidenmain_enabled then
        maidenmain_enabled = new_maidenmain_enabled
        console.print("Plugin Maidenmain " .. (maidenmain_enabled and "ativado" or "desativado"))
        if maidenmain_enabled then
            load_and_set_waypoints(true)
            loopEnabled = false
            menu.loop_enabled:set(false)
        else
            Movement.save_last_index()
            Movement.set_moving(false)
        end
    end

    if plugin_enabled and not maidenmain_enabled then
        doorsEnabled = menu.main_openDoors_enabled:get()
        loopEnabled = menu.loop_enabled:get()
    else
        doorsEnabled = false
        loopEnabled = false
    end

    revive_enabled = menu.revive_enabled:get()
    profane_mindcage_enabled = menu.profane_mindcage_toggle:get()
    profane_mindcage_count = menu.profane_mindcage_slider:get()

    if type(maidenmain.update_menu_states) == "function" then
        maidenmain.update_menu_states()
    else
        console.print("Erro: função maidenmain.update_menu_states não encontrada")
    end
end

on_update(function()
    update_menu_states()

    local teleport_info = teleport.get_teleport_info()
    if teleport_info.cooldown > 0 then
        console.print("Teleporte em cooldown. " .. teleport_info.cooldown .. " segundos restantes.")
        return
    end

    if plugin_enabled or maidenmain_enabled then
        periodic_cleanup()
        
        local game_state = GameStateChecker.check_game_state()

        if game_state == "loading_or_limbo" then
            console.print("Carregando ou em Limbo. Pausando operações.")
            current_state = PluginState.IDLE
            return
        end

        if game_state == "no_player" then
            console.print("Nenhum jogador detectado. Aguardando jogador.")
            current_state = PluginState.IDLE
            return
        end

        local local_player = get_local_player()
        local world_instance = world.get_current_world()
        
        if game_state == "helltide" then
            current_state = PluginState.HELLTIDE
            if not was_in_helltide then
                console.print("Entrou em Helltide. Inicializando operações de Helltide.")
                was_in_helltide = true
                Movement.reset(maidenmain_enabled)
                load_and_set_waypoints(maidenmain_enabled)
                ChestsInteractor.clearInteractedObjects()
                ChestsInteractor.clearBlacklist()
            end
            
            if profane_mindcage_enabled then
                automindcage.update()
            end

            if not maidenmain_enabled then
                ChestsInteractor.interactWithObjects(doorsEnabled, interactive_patterns)
            end

            Movement.pulse(plugin_enabled or maidenmain_enabled, loopEnabled, teleport, maidenmain_enabled)
            if revive_enabled then
                revive.check_and_revive()
            end
            actors.update()

            if maidenmain_enabled and type(maidenmain.update) == "function" then
                local current_position = local_player:get_position()
                local result = maidenmain.update(menu, current_position, ChestsInteractor, Movement, maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_circle_radius:get())
                
                if result == "teleport_success" then
                    console.print("Teleporte bem-sucedido. Ativando plugin principal e desativando Maidenmain.")
                    menu.plugin_enabled:set(true)
                    plugin_enabled = true
                    maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
                    maidenmain_enabled = false
                    console.print("Estado atual - Plugin principal: " .. tostring(plugin_enabled) .. ", Maidenmain: " .. tostring(maidenmain_enabled))
                end
            else
                console.print("Erro: função maidenmain.update não encontrada")
            end

            if maidenmain_enabled and Movement.is_idle() then
                explorer.disable()
            end
        else
            if was_in_helltide then
                console.print("Helltide terminou. Realizando limpeza.")
                Movement.reset(false)
                ChestsInteractor.clearInteractedObjects()
                ChestsInteractor.clearBlacklist()
                was_in_helltide = false
                teleport.reset()
                if maidenmain_enabled then
                    maidenmain.clearBlacklist()
                    maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
                    maidenmain_enabled = false
                    console.print("Plugin Maiden desativado após o término do Helltide.")
                end
                explorer.disable()
            end

            current_state = PluginState.TELEPORTING
            local current_time = get_time_since_inject()
            if current_time - last_teleport_attempt > teleport_cooldown then
                console.print("Tentando teleportar...")
                local teleport_result = teleport.tp_to_next(ChestsInteractor, Movement)
                last_teleport_attempt = current_time
                if teleport_result then
                    console.print("Teleporte bem-sucedido. Carregando novos waypoints...")
                    load_and_set_waypoints(false)
                    current_state = PluginState.FARMING
                else
                    local teleport_info = teleport.get_teleport_info()
                    console.print("Teleporte não foi bem-sucedido. Estado atual: " .. teleport_info.state)
                    console.print("Tentativas: " .. teleport_info.attempts .. "/" .. teleport_info.max_attempts)
                    if teleport_info.cooldown > 0 then
                        console.print("Cooldown: " .. teleport_info.cooldown .. " segundos restantes")
                    end
                    current_state = PluginState.ERROR
                end
            else
                console.print("Aguardando cooldown de teleporte: " .. math.floor(teleport_cooldown - (current_time - last_teleport_attempt)) .. " segundos restantes")
            end
        end
    else
        current_state = PluginState.IDLE
    end
end)

on_render_menu(function()
    menu_renderer.render_menu(plugin_enabled, doorsEnabled, loopEnabled, revive_enabled, profane_mindcage_enabled, profane_mindcage_count)
end)

on_render(function()
    if maidenmain_enabled and type(maidenmain.render) == "function" then
        maidenmain.render()
    end
end)

console.print(">>Helltide Chests Farmer Eletroluz V1.5 com integração Maidenmain<<")
console.print("Estado inicial do plugin: " .. current_state)