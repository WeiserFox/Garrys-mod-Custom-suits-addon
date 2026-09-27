CustomSuitsHUD = CustomSuitsHUD or {}

local M = CustomSuitsHUD
M.Registry = M.Registry or {}
M._playerStates = M._playerStates or {}

local NET_STATE = "CustomSuitsHUD_State"
local NET_SELECT = "CustomSuitsHUD_Select"

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local function normalizeConfig(config)
    if type(config) ~= "table" then return nil end

    local defaultId = config.default
    if type(defaultId) ~= "string" or defaultId == "" then
        return nil
    end

    local available = {}
    local seen = {}

    for _, id in ipairs(config.available or {}) do
        if type(id) == "string" and id ~= "" and not seen[id] then
            seen[id] = true
            available[#available + 1] = id
        end
    end

    if not seen[defaultId] then
        table.insert(available, 1, defaultId)
    end

    return {
        default = defaultId,
        allow_player_selection = config.allow_player_selection == true,
        available = available
    }
end

local function copyState(state)
    if not state then return nil end

    return {
        active_id = state.active_id,
        config = state.config and {
            default = state.config.default,
            allow_player_selection = state.config.allow_player_selection,
            available = table.Copy(state.config.available or {})
        } or nil
    }
end

if SERVER then
    util.AddNetworkString(NET_STATE)
    util.AddNetworkString(NET_SELECT)

    local function sendState(ply, state)
        if not IsValid(ply) then return end

        net.Start(NET_STATE)
            net.WriteString(util.TableToJSON(copyState(state) or {}, false))
        net.Send(ply)
    end

    function M.SetSuitHUD(ply, hudConfig)
        if not IsValid(ply) or not ply:IsPlayer() then return end

        local config = normalizeConfig(hudConfig)
        local state = {
            config = config,
            active_id = config and config.default or ""
        }

        M._playerStates[ply] = state
        sendState(ply, state)
    end

    function M.ClearSuitHUD(ply)
        if not IsValid(ply) then return end

        local state = {
            config = nil,
            active_id = ""
        }

        M._playerStates[ply] = state
        sendState(ply, state)
    end

    function M.GetPlayerHUDState(ply)
        local state = M._playerStates[ply]
        return state and copyState(state) or nil
    end

    net.Receive(NET_SELECT, function(_, ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end

        local requestedId = net.ReadString()
        local state = M._playerStates[ply]
        if not state or not state.config then return end
        if not ply.bIsWearingSuit then return end
        if not state.config.allow_player_selection then return end
        if not contains(state.config.available, requestedId) then return end

        state.active_id = requestedId
        sendState(ply, state)
    end)

    hook.Add("PlayerDisconnected", "CustomSuitsHUD_ClearState", function(ply)
        M._playerStates[ply] = nil
    end)
else
    M.ActiveId = M.ActiveId or nil
    M.ActiveContext = M.ActiveContext or nil
    M.SuitState = M.SuitState or nil
    M._pendingState = M._pendingState or nil

    local function scopedId(hudId, localName)
        return "CustomSuitsHUD:" .. hudId .. ":" .. localName
    end

    local function makeContext(hudId, state)
        local ctx = {
            Id = hudId,
            State = state,
            _hooks = {},
            _timers = {},
            _cleanup = {}
        }

        function ctx:IsActive()
            return M.ActiveId == self.Id and M.ActiveContext == self
        end

        function ctx:Hook(eventName, localName, callback)
            assert(type(eventName) == "string", "CustomSuitsHUD context Hook: eventName must be a string")
            assert(type(localName) == "string", "CustomSuitsHUD context Hook: localName must be a string")
            assert(type(callback) == "function", "CustomSuitsHUD context Hook: callback must be a function")

            local id = scopedId(self.Id, localName)
            hook.Add(eventName, id, callback)
            self._hooks[id] = eventName
            return id
        end

        function ctx:HookId(localName)
            return scopedId(self.Id, localName)
        end

        function ctx:Timer(localName, delay, repetitions, callback)
            assert(type(localName) == "string", "CustomSuitsHUD context Timer: localName must be a string")
            assert(type(delay) == "number", "CustomSuitsHUD context Timer: delay must be a number")
            assert(type(repetitions) == "number", "CustomSuitsHUD context Timer: repetitions must be a number")
            assert(type(callback) == "function", "CustomSuitsHUD context Timer: callback must be a function")

            local id = scopedId(self.Id, localName)
            timer.Create(id, delay, repetitions, callback)
            self._timers[id] = true
            return id
        end

        function ctx:AddCleanup(callback)
            assert(type(callback) == "function", "CustomSuitsHUD context AddCleanup: callback must be a function")
            self._cleanup[#self._cleanup + 1] = callback
        end

        function ctx:IsAllowed(hudId)
            local config = self.State and self.State.config
            return config and contains(config.available, hudId) or false
        end

        return ctx
    end

    local function cleanupContext(ctx)
        if not ctx then return end

        for id, eventName in pairs(ctx._hooks or {}) do
            hook.Remove(eventName, id)
        end

        for id in pairs(ctx._timers or {}) do
            timer.Remove(id)
        end

        for i = #ctx._cleanup, 1, -1 do
            local cleanup = ctx._cleanup[i]
            local ok, err = pcall(cleanup)
            if not ok then
                ErrorNoHalt("[CustomSuitsHUD] Cleanup error: " .. tostring(err) .. "\n")
            end
        end
    end

    local function deactivateCurrent()
        local ctx = M.ActiveContext
        if not ctx then
            M.ActiveId = nil
            return
        end

        local module = M.Registry[ctx.Id]
        if module and type(module.Deactivate) == "function" then
            local ok, err = pcall(module.Deactivate, ctx)
            if not ok then
                ErrorNoHalt("[CustomSuitsHUD] HUD '" .. ctx.Id .. "' Deactivate error: " .. tostring(err) .. "\n")
            end
        end

        cleanupContext(ctx)

        M.ActiveId = nil
        M.ActiveContext = nil
    end

    local function tryActivate(hudId, state)
        if type(hudId) ~= "string" or hudId == "" then
            deactivateCurrent()
            return
        end

        if M.ActiveId == hudId and M.ActiveContext then
            M.ActiveContext.State = state
            M.SuitState = state

            local module = M.Registry[hudId]
            if module and type(module.Update) == "function" then
                local ok, err = pcall(module.Update, M.ActiveContext)
                if not ok then
                    ErrorNoHalt("[CustomSuitsHUD] HUD '" .. hudId .. "' Update error: " .. tostring(err) .. "\n")
                end
            end

            return
        end

        deactivateCurrent()

        local module = M.Registry[hudId]
        if not module then
            M._pendingState = {
                active_id = hudId,
                config = state and state.config or nil
            }
            M.SuitState = state
            return
        end

        local ctx = makeContext(hudId, state)
        M.ActiveId = hudId
        M.ActiveContext = ctx
        M.SuitState = state

        if type(module.Activate) == "function" then
            local ok, err = pcall(module.Activate, ctx)
            if not ok then
                ErrorNoHalt("[CustomSuitsHUD] HUD '" .. hudId .. "' Activate error: " .. tostring(err) .. "\n")
                deactivateCurrent()
            end
        end
    end

    function M.Register(hudId, module)
        if type(hudId) ~= "string" or hudId == "" then
            error("CustomSuitsHUD.Register: HUD id must be a non-empty string")
        end

        if type(module) ~= "table" then
            error("CustomSuitsHUD.Register: module must be a table")
        end

        M.Registry[hudId] = module

        if M._pendingState and M._pendingState.active_id == hudId then
            local pending = M._pendingState
            M._pendingState = nil
            tryActivate(pending.active_id, {
                active_id = pending.active_id,
                config = pending.config
            })
        end
    end

    function M.Deactivate()
        deactivateCurrent()
        M.SuitState = nil
        M._pendingState = nil
    end

    function M.IsActive(hudId)
        return M.ActiveId == hudId
    end

    function M.GetActiveId()
        return M.ActiveId
    end

    function M.GetSuitHUDState()
        return copyState(M.SuitState)
    end

    function M.GetAvailableHUDs()
        local state = M.SuitState
        if not state or not state.config then return {} end
        return table.Copy(state.config.available or {})
    end

    function M.CanPlayerSelect()
        local state = M.SuitState
        return state and state.config and state.config.allow_player_selection == true or false
    end

    function M.RequestSelection(hudId)
        if type(hudId) ~= "string" or hudId == "" then return false end
        if not M.CanPlayerSelect() then return false end
        if not contains(M.GetAvailableHUDs(), hudId) then return false end

        net.Start(NET_SELECT)
            net.WriteString(hudId)
        net.SendToServer()

        return true
    end

    net.Receive(NET_STATE, function()
        local raw = net.ReadString()
        local state = util.JSONToTable(raw) or {}

        local activeId = state.active_id
        local config = state.config

        if type(activeId) ~= "string" or activeId == "" then
            M.Deactivate()
            return
        end

        tryActivate(activeId, {
            active_id = activeId,
            config = config
        })
    end)
end
