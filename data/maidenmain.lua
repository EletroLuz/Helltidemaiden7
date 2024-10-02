local waypoint_loader = require("functions.waypoint_loader")
local GameStateChecker = require("functions.game_state_checker")
local heart_insertion = require("functions.heart_insertion")
local circular_movement = require("functions.circular_movement")
local teleport = require("data.teleport")

local maidenmain = {}

-- Global variables
maidenmain.maiden_positions = {
    vec3:new(-1982.549438, -1143.823364, 12.758240),
    vec3:new(-1517.776733, -20.840151, 105.299805),
    vec3:new(120.874367, -746.962341, 7.089052),
    vec3:new(-680.988770, 725.340576, 0.389648),
    vec3:new(-1070.214600, 449.095276, 16.321373),
    vec3:new(-464.924530, -327.773132, 36.178608)
}
maidenmain.helltide_final_maidenpos = maidenmain.maiden_positions[1]
maidenmain.explorer_circle_radius = 15.0
maidenmain.explorer_circle_radius_prev = 0.0
maidenmain.explorer_point = nil

local helltide_start_time = 0
local helltide_origin_city = nil
local max_teleport_attempts = 5
local next_teleport_attempt_time = 0

-- Menu configuration
local plugin_label = "HELLTIDE_MAIDEN_AUTO_PLUGIN_"
maidenmain.menu_elements = {
    main_helltide_maiden_auto_plugin_enabled = checkbox:new(false, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_enabled")),
    main_helltide_maiden_duration = slider_float:new(1.0, 60.0, 30.0, get_hash(plugin_label .. "main_helltide_maiden_duration")),
    main_helltide_maiden_auto_plugin_run_explorer = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_run_explorer")),
    main_helltide_maiden_auto_plugin_auto_revive = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_auto_revive")),
    main_helltide_maiden_auto_plugin_show_task = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_show_task")),
    main_helltide_maiden_auto_plugin_show_explorer_circle = checkbox:new(true, get_hash("main_helltide_maiden_auto_plugin_show_explorer_circle")),
    main_helltide_maiden_auto_plugin_run_explorer_close_first = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_run_explorer_close_first")),
    main_helltide_maiden_auto_plugin_explorer_threshold = slider_float:new(0.0, 20.0, 1.5, get_hash("main_helltide_maiden_auto_plugin_explorer_threshold")),
    main_helltide_maiden_auto_plugin_explorer_thresholdvar = slider_float:new(0.0, 10.0, 3.0, get_hash("main_helltide_maiden_auto_plugin_explorer_thresholdvar")),
    main_helltide_maiden_auto_plugin_explorer_circle_radius = slider_float:new(5.0, 30.0, 15.0, get_hash("main_helltide_maiden_auto_plugin_explorer_circle_radius")),
    main_helltide_maiden_auto_plugin_insert_hearts = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_insert_hearts")),
    main_helltide_maiden_auto_plugin_insert_hearts_interval_slider = slider_float:new(0.0, 600.0, 300.0, get_hash("main_helltide_maiden_auto_plugin_insert_hearts_interval_slider")),
    main_helltide_maiden_auto_plugin_insert_hearts_afterboss = checkbox:new(false, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_insert_hearts_afterboss")),
    main_helltide_maiden_auto_plugin_insert_hearts_onlywithnpcs = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_insert_hearts_onlywithnpcs")),
    main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies = checkbox:new(true, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies")),
    main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies_interval_slider = slider_float:new(2.0, 600.0, 10.0, get_hash("main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies_interval_slider")),
    main_helltide_maiden_auto_plugin_reset = checkbox:new(false, get_hash(plugin_label .. "main_helltide_maiden_auto_plugin_reset")),
    main_tree = tree_node:new(3),
}

function maidenmain.update_menu_states()
    for k, v in pairs(maidenmain.menu_elements) do
        if type(v) == "table" and v.get then
            maidenmain[k] = v:get()
        end
    end
end

function maidenmain.find_nearest_maiden_position()
    local player = get_local_player()
    if not player then return end

    local player_pos = player:get_position()
    local nearest_pos = maidenmain.maiden_positions[1]
    local nearest_dist = player_pos:dist_to(nearest_pos)

    for i = 2, #maidenmain.maiden_positions do
        local dist = player_pos:dist_to(maidenmain.maiden_positions[i])
        if dist < nearest_dist then
            nearest_pos = maidenmain.maiden_positions[i]
            nearest_dist = dist
        end
    end

    return nearest_pos
end

function maidenmain.determine_helltide_origin_city()
    local local_player = get_local_player()
    local current_world = world.get_current_world()
    
    if local_player and current_world and GameStateChecker.is_in_helltide(local_player) then
        local current_zone = current_world:get_current_zone_name()
        
        if waypoint_loader.zone_mappings[current_zone] then
            helltide_origin_city = current_zone
            console.print("Helltide origem determinada: " .. helltide_origin_city)
            return true
        else
            console.print("Zona atual não reconhecida como uma zona válida de Helltide: " .. current_zone)
            return false
        end
    else
        console.print("Não foi possível determinar a cidade de origem da Helltide.")
        return false
    end
end

function maidenmain.init()
    console.print("Lua Plugin - Helltide Maiden Auto - Version 1.3 loaded")
    helltide_start_time = 0
    helltide_origin_city = nil
    teleport.reset()
end

function maidenmain.update(menu, current_position, ChestsInteractor, Movement, explorer_circle_radius)
    maidenmain.update_menu_states()
    local local_player = get_local_player()
    if not local_player then
        console.print("No local player found")
        return
    end

    if not maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:get() then
        console.print("Maidenmain plugin is disabled")
        return
    end

    local game_state = GameStateChecker.check_game_state()
    if game_state ~= "helltide" then
        console.print("Not in Helltide. Disabling Maidenmain plugin.")
        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
        maidenmain.reset_helltide_state()
        return
    end

    local current_time = get_time_since_inject()
    local duration = maidenmain.menu_elements.main_helltide_maiden_duration:get() * 60 -- Converter minutos para segundos

    if helltide_start_time == 0 or not helltide_origin_city then
        if maidenmain.determine_helltide_origin_city() then
            helltide_start_time = current_time
            local waypoints, zone_id = waypoint_loader.load_route(helltide_origin_city, true)
            if waypoints then
                Movement.set_waypoints(waypoints)
                console.print("Waypoints carregados para a cidade de origem da Helltide: " .. helltide_origin_city)
            else
                console.print("Falha ao carregar waypoints para a cidade de origem da Helltide.")
                return
            end
        else
            console.print("Falha ao determinar a cidade de origem da Helltide. Tentando novamente no próximo ciclo.")
            return
        end
    end

    if current_time - helltide_start_time > duration then
        console.print("Maiden duration expired. Switching to chest farming.")
        local result = maidenmain.switch_to_chest_farming(ChestsInteractor, Movement)
        return result
    end

    maidenmain.helltide_final_maidenpos = maidenmain.find_nearest_maiden_position()

    local player_position = local_player:get_position()

    if circular_movement.is_near_maiden(player_position, maidenmain.helltide_final_maidenpos, maidenmain.explorer_circle_radius) then
        circular_movement.update(maidenmain.menu_elements, maidenmain.helltide_final_maidenpos, maidenmain.explorer_circle_radius)
    else
        --console.print("Too far from Maiden. Skipping circular movement.")
    end

    heart_insertion.update(maidenmain.menu_elements, maidenmain.helltide_final_maidenpos, maidenmain.explorer_circle_radius)

    if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_auto_revive:get() and local_player:is_dead() then
        console.print("Auto-reviving player")
        local_player:revive()
    end

    if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_reset:get() then
        console.print("Resetting Maidenmain")
        maidenmain.explorer_point = nil
        maidenmain.helltide_final_maidenpos = maidenmain.maiden_positions[1]
        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_reset:set(false)
    end
end

function maidenmain.stop_activities()
    -- Interrompe atividades específicas da Maiden
    maidenmain.explorer_point = nil
    maidenmain.helltide_final_maidenpos = maidenmain.maiden_positions[1]

    -- Limpa blacklists, se existirem
    maidenmain.clearBlacklist()

    -- Limpa quaisquer waypoints ou rotas ativas relacionadas à Maiden
    if Movement and type(Movement.clear_waypoints) == "function" then
        Movement.clear_waypoints()
    end

    console.print("Atividades da Maiden interrompidas. Preparando para teleporte e farming de baús.")
end

function maidenmain.switch_to_chest_farming(ChestsInteractor, Movement)
    maidenmain.stop_activities()

    if not helltide_origin_city then
        console.print("Cidade de origem da Helltide não encontrada. Tentando determinar novamente.")
        if not maidenmain.determine_helltide_origin_city() then
            console.print("Falha ao determinar a cidade de origem da Helltide. Não é possível teleportar.")
            return "error"
        end
    end

    console.print("Tentando teleportar para a cidade de origem da Helltide: " .. helltide_origin_city)
    
    local teleport_attempts = 0
    local max_teleport_attempts = 10
    local current_time = get_time_since_inject()

    while teleport_attempts < max_teleport_attempts do
        if current_time < next_teleport_attempt_time then
            console.print("Aguardando para próxima tentativa de teleporte...")
            return "waiting"
        end

        teleport_attempts = teleport_attempts + 1
        console.print("Tentativa de teleporte " .. teleport_attempts .. " de " .. max_teleport_attempts)

        local success = teleport.tp_to_zone(helltide_origin_city, ChestsInteractor, Movement)
        
        if success then
            console.print("Teleporte bem-sucedido. Verificando a zona atual...")
            local current_zone = world.get_current_world():get_current_zone_name()
            console.print("Zona atual após teleporte: " .. tostring(current_zone))
            
            if current_zone == helltide_origin_city then
                console.print("Chegamos à zona correta: " .. current_zone)
                local waypoints, _ = waypoint_loader.load_route(helltide_origin_city, false)
                if waypoints then
                    Movement.set_waypoints(waypoints)
                    console.print("Waypoints para farming de baús carregados para a zona: " .. helltide_origin_city)
                    
                    maidenmain.reset_helltide_state()
                    console.print("Transição para farming de baús concluída.")
                    return "teleport_success"
                else
                    console.print("Falha ao carregar waypoints para farming de baús.")
                    return "error"
                end
            else
                console.print("Teleporte não chegou à zona correta. Zona atual: " .. current_zone .. ", Zona esperada: " .. helltide_origin_city)
            end
        else
            console.print("Falha no teleporte para " .. helltide_origin_city)
        end

        next_teleport_attempt_time = current_time + 5
        current_time = get_time_since_inject()
    end

    console.print("Número máximo de tentativas de teleporte atingido. Desabilitando o plugin Maidenmain.")
    maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
    maidenmain.reset_helltide_state()
    return "disabled"
end

function maidenmain.reset_helltide_state()
    helltide_start_time = 0
    helltide_origin_city = nil
    console.print("Estado da Helltide resetado.")
end

function maidenmain.render()
    if not maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:get() then
        return
    end

    if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_show_explorer_circle:get() then
        if maidenmain.helltide_final_maidenpos then
            local color_white = color.new(255, 255, 255, 255)
            local color_blue = color.new(0, 0, 255, 255)
            
            maidenmain.explorer_circle_radius = maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_circle_radius:get()
            
            graphics.circle_3d(maidenmain.helltide_final_maidenpos, maidenmain.explorer_circle_radius, color_white)
            if maidenmain.explorer_point then
                graphics.circle_3d(maidenmain.explorer_point, 2, color_blue)
            end
        end
    end

    local color_red = color.new(255, 0, 0, 255)
    for _, pos in ipairs(maidenmain.maiden_positions) do
        graphics.circle_3d(pos, 2, color_red)
    end

    if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_show_task:get() then
        -- Implement task display logic here
        -- For example:
        -- local task = "Current task: Exploring"
        -- graphics.draw_text(vec2:new(10, 10), task, color.new(255, 255, 255, 255))
    end
end

function maidenmain.render_menu()
    if not maidenmain.menu_elements.main_tree then
        console.print("Error: main_tree is nil")
        return
    end

    local success = maidenmain.menu_elements.main_tree:push("Mera-Helltide Maiden Auto v1.3")
    if not success then
        console.print("Failed to push main_tree")
        return
    end

    local enabled = maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:get()

    maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:render("Enable Plugin Maiden + Chests", "Enable or disable this plugin for Maiden and Chests", 0, 0)
    
    if enabled then
        maidenmain.menu_elements.main_helltide_maiden_duration:render("Maiden Duration (minutes)", "Set the duration for the Maiden plugin before switching to chest farming", 0, 0)
        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_run_explorer:render("Run Explorer at Maiden", "Walks in circles around the helltide boss maiden within the exploration circle radius.", 0, 0)
        if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_run_explorer:get() then
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_run_explorer_close_first:render("Explorer Runs to Enemies First", "Focuses on close and distant enemies and then tries random positions", 0, 0)
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_threshold:render("Movement Threshold", "Slows down the selection of new positions for anti-bot behavior", 2, 0)
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_thresholdvar:render("Randomizer", "Adds random threshold on top of movement threshold for more randomness", 2, 0)
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_circle_radius:render("Limit Exploration", "Limit exploration location", 2, 0)
        end

        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_auto_revive:render("Auto Revive", "Automatically revive upon death", 0, 0)
        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_show_task:render("Show Task", "Show current task in the top left corner of the screen", 0, 0)
        
        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts:render("Insert Hearts", "Will try to insert hearts after reaching the heart timer, requires available hearts", 0, 0)
        if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts:get() then
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts_interval_slider:render("Insert Interval", "Time interval to try inserting hearts", 2, 0)
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts_afterboss:render("Insert Heart After Maiden Death", "Insert heart directly after the helltide boss maiden's death", 0, 0)
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies:render("Insert Heart After No Enemies", "Insert heart after seeing no enemies for a particular time in the circle", 0, 0)
            if maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies:get() then
                maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts_afternoenemies_interval_slider:render("No Enemies Timer", "Time in seconds after trying to insert heart when no enemy is seen", 2, 0)
            end
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_insert_hearts_onlywithnpcs:render("Insert Only If Players In Range", "Insert hearts only if players are in range, can disable all other features if no player is seen at the altar", 0, 0)
        end

        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_show_explorer_circle:render("Draw Explorer Circle", "Show Exploration Circle to check walking range (white) and target walking points (blue)", 0, 0)
        maidenmain.menu_elements.main_helltide_maiden_auto_plugin_reset:render("Reset (do not keep on)", "Temporarily enable reset mode to reset the plugin", 0, 0)
    end

    maidenmain.menu_elements.main_tree:pop()
end

function maidenmain.debug_print_menu_elements()
    for k, v in pairs(maidenmain.menu_elements) do
        --console.print(k .. ": " .. tostring(v))
    end
end

function maidenmain.clearBlacklist()
    if type(heart_insertion.clearBlacklist) == "function" then
        heart_insertion.clearBlacklist()
    end
    if type(circular_movement.clearBlacklist) == "function" then
        circular_movement.clearBlacklist()
    end
end

return maidenmain