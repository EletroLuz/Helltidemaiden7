local waypoint_loader = require("functions.waypoint_loader")
local countdown_display = require("graphics.countdown_display")
local teleport = {}

local function cleanup_before_teleport(ChestsInteractor, Movement)
    if not ChestsInteractor or not Movement then
        console.print("ChestsInteractor ou Movement não disponíveis. Não é possível limpar antes do teleporte.")
        return
    end
    collectgarbage("collect")
    waypoint_loader.clear_cached_waypoints()
    ChestsInteractor.clearInteractedObjects()
    Movement.reset()
end

-- Variáveis locais
local current_index = 1
local last_position = nil
local stable_position_count = 0
local stable_position_threshold = 3 -- Ajuste conforme necessário
local teleport_state = "idle"
local teleport_start_time = 0
local teleport_timeout = 10 -- Tempo máximo para teleporte em segundos

-- Variáveis para controle de tentativas e cooldown
local teleport_attempts = 0
local max_teleport_attempts = 5
local teleport_cooldown = 0
local teleport_cooldown_duration = 30 -- segundos

-- Função para obter o próximo local de teleporte
function teleport.get_next_teleport_location()
    local valid_zones = {}
    for zone, info in pairs(waypoint_loader.zone_mappings) do
        table.insert(valid_zones, {name = zone, id = info.id})
    end
    return valid_zones[(current_index % #valid_zones) + 1].name
end

-- Função principal de teleporte
function teleport.tp_to_next(ChestsInteractor, Movement, target_zone)
    local current_time = get_time_since_inject()
    
    if current_time < teleport_cooldown then
        local remaining_cooldown = math.floor(teleport_cooldown - current_time)
        console.print("Teleporte em cooldown. " .. remaining_cooldown .. " segundos restantes.")
        return false
    end

    if teleport_attempts >= max_teleport_attempts then
        console.print("Número máximo de tentativas de teleporte atingido. Entrando em cooldown por " .. teleport_cooldown_duration .. " segundos.")
        teleport_cooldown = current_time + teleport_cooldown_duration
        teleport_attempts = 0
        return false
    end

    local current_world = world.get_current_world()
    if not current_world then
        return false
    end

    local world_name = current_world:get_name()
    local local_player = get_local_player()
    if not local_player then
        return false
    end

    local current_position = local_player:get_position()

    if teleport_state == "idle" then
        teleport_attempts = teleport_attempts + 1
        console.print("Tentativa de teleporte " .. teleport_attempts .. " de " .. max_teleport_attempts)
        cleanup_before_teleport(ChestsInteractor, Movement)
        
        local teleport_destination
        if target_zone then
            -- Se uma zona específica foi fornecida, use-a
            local target_info = waypoint_loader.zone_mappings[target_zone]
            if not target_info then
                console.print("Erro: Zona de destino inválida: " .. target_zone)
                return false
            end
            teleport_destination = {name = target_zone, id = target_info.id}
        else
            -- Se nenhuma zona específica foi fornecida, selecione uma aleatoriamente
            local valid_zones = {}
            for zone, info in pairs(waypoint_loader.zone_mappings) do
                if zone ~= current_world:get_current_zone_name() then
                    table.insert(valid_zones, {name = zone, id = info.id})
                end
            end
            if #valid_zones == 0 then
                console.print("Erro: Não há zonas válidas para teleporte")
                return false
            end
            teleport_destination = valid_zones[current_index]
        end

        teleport_to_waypoint(teleport_destination.id)
        teleport_state = "initiated"
        teleport_start_time = current_time
        last_position = current_position
        console.print("Teleporte iniciado para " .. teleport_destination.name)
        countdown_display.start_countdown(teleport_timeout)
        return false
    elseif teleport_state == "initiated" then
        if current_time - teleport_start_time > teleport_timeout then
            console.print("Teleporte falhou: timeout. Tentando novamente...")
            teleport_state = "idle"
            return false
        elseif world_name:find("Limbo") then
            teleport_state = "in_limbo"
            console.print("Em Limbo, aguardando...")
            return false
        elseif current_position:dist_to(last_position) > 5 then
            console.print("Movimento detectado. Teleporte cancelado. Tentando novamente...")
            teleport_state = "idle"
            return false
        end
    elseif teleport_state == "in_limbo" and not world_name:find("Limbo") then
        teleport_state = "exited_limbo"
        last_position = current_position
        stable_position_count = 0
        console.print("Saiu do Limbo, verificando posição estável")
        return false
    elseif teleport_state == "exited_limbo" then
        if last_position and current_position:dist_to(last_position) < 0.5 then
            stable_position_count = stable_position_count + 1
            if stable_position_count >= stable_position_threshold then
                local current_zone = current_world:get_current_zone_name()
                current_index = current_index % #valid_zones + 1
                teleport_state = "idle"
                console.print("Teleporte concluído com sucesso para " .. current_zone)
                teleport_attempts = 0  -- Reseta as tentativas após sucesso
                return true
            end
        else
            stable_position_count = 0
        end
    end

    last_position = current_position
    return false
end

-- Função para teleportar para uma zona específica
function teleport.tp_to_zone(target_zone, ChestsInteractor, Movement)
    return teleport.tp_to_next(ChestsInteractor, Movement, target_zone)
end

-- Função para resetar o estado do teleporte
function teleport.reset()
    teleport_state = "idle"
    last_position = nil
    stable_position_count = 0
    current_index = 1
    teleport_attempts = 0
    teleport_cooldown = 0
    console.print("Estado do teleporte resetado")
end

-- Função para obter o estado atual do teleporte
function teleport.get_teleport_state()
    return teleport_state
end

-- Função para obter informações detalhadas sobre o teleporte
function teleport.get_teleport_info()
    return {
        state = teleport_state,
        attempts = teleport_attempts,
        max_attempts = max_teleport_attempts,
        cooldown = math.max(0, math.floor(teleport_cooldown - get_time_since_inject()))
    }
end

return teleport