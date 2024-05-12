-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil

CRED = CRED or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
Counter = Counter or 0

-- Define custom colors for printing messages
colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    yellow = "\27[33m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Define a custom function to check if two points are within a given range.
local function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Define a custom function to calculate the Euclidean distance between two points.
local function calculateDistance(x1, y1, x2, y2)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- Define a custom function to find the closest opponent to the player.
local function findClosestOpponent(player)
    local closestOpponent = nil
    local minDistance = math.huge

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            local dist = calculateDistance(player.x, player.y, state.x, state.y)
            if dist < minDistance then
                minDistance = dist
                closestOpponent = state
            end
        end
    end

    return closestOpponent
end

-- Define a custom function to predict the future movement of the closest opponent using linear extrapolation with inertia.
local function predictOpponentMovement(player, opponent)
    local dx = opponent.x - player.x
    local dy = opponent.y - player.y
    local maxDist = 3         -- Maximum distance to predict
    local inertiaFactor = 0.8 -- Inertia factor for opponent movement

    -- Linear extrapolation with inertia
    local predictedX = opponent.x + (dx > 0 and maxDist or -maxDist) * inertiaFactor
    local predictedY = opponent.y + (dy > 0 and maxDist or -maxDist) * inertiaFactor

    local dirX = predictedX > opponent.x and "Right" or "Left"
    local dirY = predictedY > opponent.y and "Down" or "Up"

    return math.abs(dx) > math.abs(dy) and dirX or dirY
end

-- Define a custom function to decide the next action based on player proximity, energy, and a custom decision tree.
local function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetInRange = false
    local closestOpponent = findClosestOpponent(player)
    local action, params = nil, nil

    -- Check if any player is within attack range
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
            targetInRange = true
            break
        end
    end

    if player.health < 30 then
        -- If health is low, move away from the closest opponent
        local moveDir = getOppositeDirection(player.x, player.y, closestOpponent.x, closestOpponent.y)
        print(colors.red .. "Health low. Retreating to " .. moveDir .. colors.reset)
        action, params = "PlayerMove", { Direction = moveDir }
    elseif player.energy > 50 and targetInRange then
        -- If energy is high and an opponent is in range, attack
        print(colors.red .. "Opponent in range. Attacking..." .. colors.reset)
        action, params = "PlayerAttack", { AttackEnergy = tostring(player.energy) }
    elseif player.energy > 50 then
        -- If energy is high and no opponents are in range, move towards the predicted future position of the closest opponent
        local moveDir = predictOpponentMovement(player, closestOpponent)
        print(colors.cyan .. "Moving towards predicted opponent position in direction: " .. moveDir .. colors.reset)
        action, params = "PlayerMove", { Direction = moveDir }
    else
        -- If health and energy are moderate, gather resources or move randomly
        action, params = gatherResources(player)
        if action == "PlayerMove" then
            print(colors.yellow .. "No resources found. Moving randomly." .. colors.reset)
        end
    end

    -- Send the action and parameters to the game engine
    print(colors.blue .. "Taking action: " .. action .. " with params: " .. inspect(params) .. colors.reset)
    ao.send({ Target = Game, Action = action, Params = params })
end

-- Define a custom function to return the opposite direction of the given direction.
local function getOppositeDirection(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1

    if math.abs(dx) > math.abs(dy) then
        return dx > 0 and "Left" or "Right"
    else
        return dy > 0 and "Up" or "Down"
    end
end

-- Define a custom function to move towards the nearest resource to gather it.
local function gatherResources(player)
    local nearestResource = nil
    local minDistance = math.huge

    for _, resource in pairs(LatestGameState.Resources) do
        local dist = calculateDistance(player.x, player.y, resource.x, resource.y)
        if dist < minDistance then
            minDistance = dist
            nearestResource = resource
        end
    end

    if nearestResource then
        local dx = nearestResource.x - player.x
        local dy = nearestResource.y - player.y

        if math.abs(dx) > math.abs(dy) then
            return "CollectResource", { ResourceId = nearestResource.id, Direction = dx > 0 and "Right" or "Left" }
        else
            return "CollectResource", { ResourceId = nearestResource.id, Direction = dy > 0 and "Down" or "Up" }
        end
    else
        -- No resources found, move randomly
        local directionMap = { "Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft" }
        local randomIndex = math.random(#directionMap)
        return "PlayerMove", { Direction = directionMap[randomIndex] }
    end
end

-- Define a custom function to inspect tables (useful for debugging)
local function inspect(t, indent)
    local indent = indent or ""
    local str = "{\n"
    for k, v in pairs(t) do
        if type(v) == "table" then
            str = str .. indent .. "  " .. k .. " = " .. inspect(v, indent .. "  ") .. ",\n"
        else
            str = str .. indent .. "  " .. k .. " = " .. tostring(v) .. ",\n"
        end
    end
    return str .. indent .. "}"
end

-- Handlers to update game state and trigger actions.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        -- Send an action to retrieve the game state immediately after an announcement
        ao.send({ Target = Game, Action = "GetGameState" })
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
        print("Location: " .. "row: " .. LatestGameState.Players[ao.id].x .. ' col: ' .. LatestGameState.Players[ao.id]
            .y)
    end
)

Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        -- Make decisions based on the updated game state
        decideNextAction()
    end
)

-- Utility function to determine the game phase based on the current tick counter.
local function determineGamePhase()
    local tickCounter = Counter
    local earlyGameThreshold = 500
    local midGameThreshold = 1000

    local gamePhase = ""
    if tickCounter <= earlyGameThreshold then
        gamePhase = "Early"
    elseif tickCounter <= midGameThreshold then
        gamePhase = "Mid"
    else
        gamePhase = "Late"
    end

    print(colors.yellow .. "Game phase: " .. gamePhase .. colors.reset)
end

Handlers.add(
    "TickUpdate",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function(msg)
        -- Update the game state on each tick
        ao.send({ Target = Game, Action = "GetGameState" })
        -- Determine the current game phase
        determineGamePhase()
    end
)

Prompt = function() return Name .. "> " end
