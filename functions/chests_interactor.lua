local Movement = require("functions.movement")
local menu = require("menu")
local interactive_patterns = require("enums.interactive_patterns")

local ChestsInteractor = {}

-- Estados da FSM
local States = {
    IDLE = "IDLE",
    MOVING = "MOVING",
    INTERACTING = "INTERACTING",
    CHECKING_VFX = "CHECKING_VFX"
}

-- Variáveis de estado
local currentState = States.IDLE
local targetObject = nil
local interactedObjects = {}
local expiration_time = 10
local blacklist = {}
local failed_attempts = 0
local max_attempts = 3
local vfx_check_start_time = 0
local vfx_check_duration = 5  -- Duração em segundos para verificar os efeitos visuais

-- Funções auxiliares
local function getDistance(pos1, pos2)
    return pos1:dist_to(pos2)
end

local function isObjectInteractable(obj, interactive_patterns)
    local obj_name = obj:get_skin_name()
    -- Verifica se o nome do objeto começa com "usz_rewardGizmo_"
    if obj_name and string.find(obj_name, "^usz_rewardGizmo_") then
        return interactive_patterns[obj_name] and 
               (not interactedObjects[obj_name] or os.clock() > interactedObjects[obj_name])
    end
    return false
end

-- Função para verificar se o objeto está na blacklist
local function is_blacklisted(obj)
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    
    for _, blacklisted_obj in ipairs(blacklist) do
        if blacklisted_obj.name == obj_name and blacklisted_obj.position:dist_to(obj_pos) < 0.1 then
            return true
        end
    end
    
    return false
end

-- Função para adicionar objeto à blacklist
local function add_to_blacklist(obj)
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()

    local pos_string = "unknown position"
    if obj_pos then
        -- Usar os métodos x(), y(), e z() para acessar as coordenadas
        pos_string = string.format("(%.2f, %.2f, %.2f)", obj_pos:x(), obj_pos:y(), obj_pos:z())
    end

    table.insert(blacklist, {name = obj_name, position = obj_pos})
    console.print("Added " .. obj_name .. " to blacklist at position: " .. pos_string)
end

-- Função para verificar se o baú foi aberto
local function check_chest_opened()
    local actors = actors_manager.get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "Hell_Prop_Chest_Helltide_01_Client_Dyn" then
            console.print("Chest opened successfully: " .. name)
            return true
        end
    end
    return false
end

-- Funções de estado
local stateFunctions = {
    [States.IDLE] = function(objects, interactive_patterns)
        for _, obj in ipairs(objects) do
            if isObjectInteractable(obj, interactive_patterns) and not is_blacklisted(obj) then
                targetObject = obj
                return States.MOVING
            end
        end
        return States.IDLE
    end,

    [States.MOVING] = function()
        if not targetObject or not isObjectInteractable(targetObject, interactive_patterns) then 
            return States.IDLE 
         end     
   
        local player_pos = get_player_position()
        local obj_pos = targetObject:get_position()
        local distance = getDistance(player_pos, obj_pos)
        
        if distance < 2.0 then
            if isObjectInteractable(targetObject, interactive_patterns) then
                return States.INTERACTING
        else
            return States.IDLE
        end
        elseif distance < menu.move_threshold_slider:get() then
            pathfinder.request_move(obj_pos)
            return States.MOVING
        else
            return States.IDLE
        end
    end,

    [States.INTERACTING] = function()
        if not targetObject then return States.IDLE end

        Movement.set_interacting(true)
        local obj_name = targetObject:get_skin_name()
        interactedObjects[obj_name] = os.clock() + expiration_time
        interact_object(targetObject)
        console.print("Interacting with " .. obj_name)
        vfx_check_start_time = os.clock()
        return States.CHECKING_VFX
    end,

    [States.CHECKING_VFX] = function()
        if os.clock() - vfx_check_start_time > vfx_check_duration then
            console.print("VFX check timed out")
            failed_attempts = failed_attempts + 1
            if failed_attempts >= max_attempts then
                console.print("Max attempts reached, moving to next chest")
                targetObject = nil
                failed_attempts = 0
                Movement.set_interacting(false)
                return States.IDLE
            else
                return States.INTERACTING
            end
        end

        if check_chest_opened() then
            console.print("Chest confirmed opened")
            add_to_blacklist(targetObject)
            targetObject = nil
            failed_attempts = 0
            Movement.set_interacting(false)
            return States.IDLE
        end

        return States.CHECKING_VFX
    end
}

-- Função principal de interação
function ChestsInteractor.interactWithObjects(doorsEnabled, interactive_patterns)
    local local_player = get_local_player()
    if not local_player then return end
    
    local objects = actors_manager.get_ally_actors()
    if not objects then return end
    
    local newState = stateFunctions[currentState](objects, interactive_patterns)
    if newState ~= currentState then
        console.print("State changed from " .. currentState .. " to " .. newState)
        currentState = newState
    end
end

-- Função para limpar objetos interagidos
function ChestsInteractor.clearInteractedObjects()
    interactedObjects = {}
    console.print("Cleared interacted objects list")
end

-- Função para limpar a blacklist
function ChestsInteractor.clearBlacklist()
    blacklist = {}
    console.print("Cleared blacklist")
end

-- Função para imprimir a blacklist (para debug)
function ChestsInteractor.printBlacklist()
    console.print("Current Blacklist:")
    for i, item in ipairs(blacklist) do
        console.print(i .. ": " .. item.name .. " at position: " .. item.position:to_string())
    end
end

return ChestsInteractor