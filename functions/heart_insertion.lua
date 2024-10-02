local heart_insertion = {}
local circular_movement = require("functions/circular_movement")

-- Estados da FSM
local States = {
    IDLE = "IDLE",
    MOVING = "MOVING",
    INTERACTING = "INTERACTING",
    CHECKING_VFX = "CHECKING_VFX"
}

-- Variáveis de estado
local currentState = States.IDLE
local targetAltars = {}
local currentTargetIndex = 1
local blacklist = {}
local expiration_time = 10  -- Tempo de expiração da blacklist em segundos
local failed_attempts = 0
local max_attempts = 3
local vfx_check_start_time = 0
local vfx_check_duration = 5  -- Duração em segundos para verificar os efeitos visuais
local last_interaction_time = 0
local interaction_timeout = 5  -- 5 segundos de timeout para cada interação
local last_move_request_time = 0
local move_request_interval = 2  -- Intervalo mínimo entre solicitações de movimento

-- Variáveis globais relacionadas à inserção de corações
local insert_hearts = 0
local insert_hearts_afterboss = 0
local insert_hearts_time = 0
local insert_hearts_waiter = 0
local insert_hearts_waiter_interval = 10.0
local insert_hearts_waiter_elapsed = 0
local old_currenthearts = 0
local last_insert_hearts_waiter_time = 0
local seen_boss_dead = 0
local seen_boss_dead_time = 0
local seen_enemies = 0
local last_seen_enemies_elapsed = 0
local insert_only_with_npcs_playercount = 0

-- Funções auxiliares
local function getDistance(pos1, pos2)
    return pos1:dist_to(pos2)
end

local function is_blacklisted(obj)
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    local current_time = os.clock()
    
    for i, blacklisted_obj in ipairs(blacklist) do
        if blacklisted_obj.name == obj_name and blacklisted_obj.position:dist_to(obj_pos) < 1.0 then
            if current_time > blacklisted_obj.expiration_time then
                table.remove(blacklist, i)
                return false
            end
            return true
        end
    end
    
    return false
end

local function add_to_blacklist(obj)
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    local current_time = os.clock()

    local pos_string = "unknown position"
    if obj_pos then
        pos_string = string.format("(%.2f, %.2f, %.2f)", obj_pos:x(), obj_pos:y(), obj_pos:z())
    end

    table.insert(blacklist, {
        name = obj_name, 
        position = obj_pos, 
        expiration_time = current_time + expiration_time
    })
    console.print("Added " .. obj_name .. " to blacklist at position: " .. pos_string .. " for " .. expiration_time .. " seconds")
end

local function check_altar_opened()
    local actors = actors_manager.get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "VFX_BloodSplash_Vertical_01" or name == "vfx_carryablePickUp_smoke" then
            --console.print("Altar Interacted successfully: " .. name)
            return true
        end
    end
    if os.clock() - last_interaction_time > interaction_timeout then
        --console.print("Interaction timeout reached")
        return true  -- Considera como sucesso para avançar para o próximo altar
    end
    return false
end

local function request_move_to_position(target_pos)
    local current_time = os.clock()
    if current_time - last_move_request_time >= move_request_interval then
        pathfinder.request_move(target_pos)
        last_move_request_time = current_time
        --console.print("Requesting move to position: " .. target_pos:to_string())
        return true
    end
    return false
end

local function is_helltide_boss_spawn_present()
    local actors = actors_manager.get_all_actors()
    for _, actor in ipairs(actors) do
        local name = actor:get_skin_name()
        if name == "S04_helltidebossSpawn_egg" then
            --console.print("Helltide Boss Spawn Egg detected. Pausing heart insertion.")
            return true
        end
    end
    return false
end

-- Funções de estado
local stateFunctions = {
    [States.IDLE] = function(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
        if not menu_elements.main_helltide_maiden_auto_plugin_insert_hearts:get() then
            return States.IDLE
        end

        if is_helltide_boss_spawn_present() then
            return States.IDLE
        end

        local current_hearts = get_helltide_coin_hearts()

        if current_hearts > 0 and (seen_enemies == 0 or seen_boss_dead == 1) then
            local actors = actors_manager.get_all_actors()
            targetAltars = {}
            for _, actor in ipairs(actors) do
                local name = string.lower(actor:get_skin_name())
                if name == "s04_smp_succuboss_altar_a_dyn" and not is_blacklisted(actor) then
                    table.insert(targetAltars, actor)
                end
            end
            if #targetAltars > 0 then
                currentTargetIndex = 1
                failed_attempts = 0
                --console.print("Found " .. #targetAltars .. " altars. Moving to the first one.")
                return States.MOVING
            end
        end

        return States.IDLE
    end,

    [States.MOVING] = function(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
        if #targetAltars == 0 or currentTargetIndex > #targetAltars then 
            --console.print("No more altars to interact with. Returning to IDLE.")
            return States.IDLE 
        end

        local currentTarget = targetAltars[currentTargetIndex]
        local player_pos = get_player_position()
        local altar_pos = currentTarget:get_position()
        local distance = getDistance(player_pos, altar_pos)
        
        --console.print("Distance to current altar: " .. distance)
        
        if distance < 2.0 then
            --console.print("Close enough to altar. Switching to INTERACTING.")
            return States.INTERACTING
        else
            if request_move_to_position(altar_pos) then
                --console.print("Requested move towards altar.")
            else
                --console.print("Waiting before requesting next move.")
            end
            return States.MOVING
        end
    end,

    [States.INTERACTING] = function(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
        if #targetAltars == 0 or currentTargetIndex > #targetAltars then 
            --console.print("No more altars to interact with. Returning to IDLE.")
            return States.IDLE 
        end

        local currentTarget = targetAltars[currentTargetIndex]
        local current_hearts = get_helltide_coin_hearts()
        if current_hearts > 0 then
            --console.print("Interacting with the altar to insert hearts.")
            interact_object(currentTarget)
            last_interaction_time = os.clock()
            vfx_check_start_time = os.clock()
            return States.CHECKING_VFX
        else
            --console.print("No hearts available for insertion. Moving to next altar.")
            currentTargetIndex = currentTargetIndex + 1
            if currentTargetIndex > #targetAltars then
                return States.IDLE
            else
                return States.MOVING
            end
        end
    end,

    [States.CHECKING_VFX] = function(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
        if check_altar_opened() then
            --console.print("Altar interaction confirmed or timed out")
            add_to_blacklist(targetAltars[currentTargetIndex])
            currentTargetIndex = currentTargetIndex + 1
            failed_attempts = 0
            if currentTargetIndex > #targetAltars then
                return States.IDLE
            else
                return States.MOVING
            end
        end

        if os.clock() - vfx_check_start_time > vfx_check_duration then
            --console.print("VFX check timed out")
            failed_attempts = failed_attempts + 1
            if failed_attempts >= max_attempts then
                --console.print("Max attempts reached, moving to next altar")
                currentTargetIndex = currentTargetIndex + 1
                failed_attempts = 0
                if currentTargetIndex > #targetAltars then
                    return States.IDLE
                else
                    return States.MOVING
                end
            else
                return States.INTERACTING
            end
        end

        return States.CHECKING_VFX
    end
}

-- Função principal de inserção de corações
function heart_insertion.update(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
    local local_player = get_local_player()
    if not local_player then return end
    
    if not menu_elements.main_helltide_maiden_auto_plugin_enabled:get() then return end

    -- Ativa o estado de inserção de corações
    circular_movement.set_heart_insertion_state(true)

    if is_helltide_boss_spawn_present() then
        --console.print("Helltide Boss Spawn Egg present. Pausing heart insertion.")
        currentState = States.IDLE
        circular_movement.set_heart_insertion_state(false)
        return
    end

    --console.print("Current State: " .. currentState)
    --console.print("Current Target Index: " .. currentTargetIndex)
    --console.print("Number of Target Altars: " .. #targetAltars)

    local newState = stateFunctions[currentState](menu_elements, helltide_final_maidenpos, explorer_circle_radius)
    if newState ~= currentState then
        --console.print("State changed from " .. currentState .. " to " .. newState)
        currentState = newState
    end

    -- Desativa o estado de inserção de corações quando terminar
    if currentState == States.IDLE then
        circular_movement.set_heart_insertion_state(false)
    end
end

-- Função para limpar a blacklist
function heart_insertion.clearBlacklist()
    blacklist = {}
    console.print("Cleared altar blacklist")
end

-- Função para imprimir a blacklist (para debug)
function heart_insertion.printBlacklist()
    console.print("Current Altar Blacklist:")
    for i, item in ipairs(blacklist) do
        console.print(string.format("%d: %s at position: %s (expires in %.2f seconds)", 
            i, item.name, item.position:to_string(), item.expiration_time - os.clock()))
    end
end

return heart_insertion