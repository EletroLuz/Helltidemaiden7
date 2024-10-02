local actors = {}

local interacted_objects_blacklist = {}
local temporary_ignore_objects = {}
local expiration_time = 10 -- Tempo de expiração em segundos para objetos temporariamente ignorados

-- Tabela para armazenar os temporizadores de movimento dos objetos
local movement_timers = {}
local max_movement_time = 8 -- Tempo máximo em segundos para tentar se mover até um objeto

local ignored_objects = {
    "Lilith",
    "QST_Class_Necro_Shrine",
    "LE_Shrine_Goatman_Props_Arrangement_SP",
    "fxKit_seamlessSphere_twoSided2_lilithShrine_idle",
    "LE_Shrine_Zombie_Props_Arrangement_SP",
    "_Shrine_Moss_",
    "g_gold"
}

local function should_ignore_object(skin_name)
    for _, ignored_pattern in ipairs(ignored_objects) do
        if skin_name:match(ignored_pattern) then
            return true
        end
    end
    return false
end

local actor_types = {
    shrine = {
        pattern = "Shrine_",
        move_threshold = 12,
        interact_threshold = 2.5,
        interact_function = function(obj) 
            interact_object(obj)
        end
    },
    goblin = {
        pattern = "treasure_goblin",
        move_threshold = 20,
        interact_threshold = 2,
        interact_function = function(actor)
            console.print("Interacting with the Goblin")
        end
    },
    harvest_node = {
        pattern = "HarvestNode_Ore",
        move_threshold = 12,
        interact_threshold = 1.0,
        interact_function = function(obj)
            interact_object(obj)
        end
    },
    Misterious_Chest = {
        pattern = "Hell_Prop_Chest_Rare_Locked",
        move_threshold = 12,
        interact_threshold = 1.0,
        interact_function = function(obj)
            interact_object(obj)
        end
    },
    Herbs = {
        pattern = "HarvestNode_Herb",
        move_threshold = 8,
        interact_threshold = 1.0,
        interact_function = function(obj)
            interact_object(obj)
        end
    }
}

local function is_actor_of_type(skin_name, actor_type)
    return skin_name:match(actor_types[actor_type].pattern) and not should_ignore_object(skin_name)
end

local function should_interact_with_actor(actor_position, player_position, actor_type)
    local distance_threshold = actor_types[actor_type].interact_threshold
    return actor_position:dist_to(player_position) < distance_threshold
end

local function move_to_actor(actor_position, player_position, actor_type)
    local move_threshold = actor_types[actor_type].move_threshold
    local distance = actor_position:dist_to(player_position)
    
    if distance <= move_threshold then
        pathfinder.request_move(actor_position)
        return true
    end
    
    return false
end

function actors.update()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    local player_pos = local_player:get_position()
    local all_actors = actors_manager.get_ally_actors()
    local current_time = os.clock()

    -- Limpar objetos expirados da lista de ignorados temporários
    for id, timestamp in pairs(temporary_ignore_objects) do
        if current_time - timestamp > expiration_time then
            temporary_ignore_objects[id] = nil
        end
    end

    -- Ordenar atores por distância
    table.sort(all_actors, function(a, b)
        return a:get_position():squared_dist_to_ignore_z(player_pos) <
               b:get_position():squared_dist_to_ignore_z(player_pos)
    end)

    for _, obj in ipairs(all_actors) do
        if obj and not temporary_ignore_objects[obj:get_id()] then
            local position = obj:get_position()
            local skin_name = obj:get_skin_name()

            for actor_type, config in pairs(actor_types) do
                if skin_name and is_actor_of_type(skin_name, actor_type) and not obj:can_not_interact() then
                    local distance = position:dist_to(player_pos)
                    if distance <= config.move_threshold then
                        -- Iniciar o temporizador de movimento se ainda não existir
                        if not movement_timers[obj:get_id()] then
                            movement_timers[obj:get_id()] = current_time
                        end

                        -- Verificar se o tempo limite de movimento foi atingido
                        if current_time - movement_timers[obj:get_id()] > max_movement_time then
                            temporary_ignore_objects[obj:get_id()] = current_time
                            movement_timers[obj:get_id()] = nil
                            console.print("Tempo limite de movimento atingido para " .. actor_type .. ": " .. skin_name .. ". Ignorando temporariamente.")
                        else
                            if move_to_actor(position, player_pos, actor_type) then
                                if should_interact_with_actor(position, player_pos, actor_type) then
                                    config.interact_function(obj)
                                    temporary_ignore_objects[obj:get_id()] = current_time
                                    movement_timers[obj:get_id()] = nil
                                    console.print("Interagiu com " .. actor_type .. ": " .. skin_name)
                                end
                            end
                        end
                    else
                        -- Se o objeto estiver fora do alcance, resetamos o temporizador
                        movement_timers[obj:get_id()] = nil
                    end
                end
            end
        end
    end
end

-- Função para limpar a lista de objetos ignorados temporariamente
function actors.clear_temporary_ignore_list()
    temporary_ignore_objects = {}
    movement_timers = {}
    console.print("Listas de objetos ignorados temporariamente e temporizadores de movimento foram limpas")
end

return actors