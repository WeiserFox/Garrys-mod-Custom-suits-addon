local defaultCategory = "Custom Suits"
local configPath = "custom_suits.json"
local entityModel = "models/props_c17/BriefCase001a.mdl"

local SUITS_DATA = {}

-- Инициализация
local function LoadSuitsConfig()
    if not file.Exists(configPath, "DATA") then
        local default = {{
            id = "suit_combine_elite",
            name = "Combine Elite",
            category = "Альянс (Костюмы)",
            model = "models/player/combine_super_soldier.mdl",
            hp = 150,
            armor = 150,
            walk_speed = 170,
            run_speed = 340,
            weapons = {"weapon_ar2", "weapon_pistol"},
            bodygroups = {},
            icon = "materials/entities/base_gmodentity.png",
            hud = {
                default = "combine",
                allow_player_selection = true,
                available = {"combine"}
            }
        }}
        file.Write(configPath, util.TableToJSON(default, true))
    end

    local rawData = file.Read(configPath, "DATA")
    SUITS_DATA = util.JSONToTable(rawData) or {}
    print("[Suits] Loaded " .. #SUITS_DATA .. " suits from JSON.")
end

LoadSuitsConfig()

-- Выгрузка энтити по конфигу
for _, data in ipairs(SUITS_DATA) do
    local ENT = {}
    ENT.Type = "anim"
    ENT.Base = "base_gmodentity"
    ENT.Author = "Beer Fox"
    ENT.PrintName = data.name
    ENT.Spawnable = true
    ENT.Category = data.category or defaultCategory
    
    if data.icon and data.icon ~= "" then
        ENT.IconOverride = data.icon
    end

    ENT.SuitData = data 

    if SERVER then
        function ENT:Initialize()
            self:SetModel(entityModel)
            self:PhysicsInit(SOLID_VPHYSICS)
            self:SetMoveType(MOVETYPE_VPHYSICS)
            self:SetSolid(SOLID_VPHYSICS)
            self:SetUseType(SIMPLE_USE)
            local phys = self:GetPhysicsObject()
            if phys:IsValid() then phys:Wake() end
        end

        function ENT:Use(activator)
            if IsValid(activator) and activator:IsPlayer() and not activator.bIsWearingSuit then
                activator:EquipCustomSuit(self.SuitData)
                self:Remove() 
            end
        end
    else
        
        function ENT:Draw()
            self:DrawModel()

            if self.SuitData and self.SuitData.icon and self.SuitData.icon ~= "" then
                if not self.IconMaterial then
                    self.IconMaterial = Material(self.SuitData.icon, "noclamp smooth")
                end

                if self.IconMaterial and not self.IconMaterial:IsError() then
                    local pos = self:GetPos() + Vector(0, 0, 20) 
                    
                    local ang = LocalPlayer():EyeAngles()
                    ang:RotateAroundAxis(ang:Forward(), 90)
                    ang:RotateAroundAxis(ang:Right(), 90)

                    cam.Start3D2D(pos, ang, 0.1)
                        surface.SetDrawColor(255, 255, 255, 255)
                        surface.SetMaterial(self.IconMaterial)
                        surface.DrawTexturedRect(-64, -64, 128, 128)
                    cam.End3D2D()
                end
            end
        end
    end

    scripted_ents.Register(ENT, data.id)
end

if SERVER then
    local plyMeta = FindMetaTable("Player")



    function plyMeta:EquipCustomSuit(suitData)

        local currentHands = self:GetHands()
        local savedHandsModel = IsValid(currentHands) and currentHands:GetModel() or ""

        if self.bIsWearingSuit then
            self:RemoveCustomSuit()
        end


        local oldBgroups = {}
        for i = 0, self:GetNumBodyGroups() - 1 do
            oldBgroups[i] = self:GetBodygroup(i)
        end

        self.PreSuitData = {
            model = self:GetModel(),
            hands_model = savedHandsModel,
            bgroups = oldBgroups,
            hp = self:Health(),
            maxHp = self:GetMaxHealth(),
            armor = self:Armor(),
            walk = self:GetWalkSpeed(),
            run = self:GetRunSpeed(),
            weaps = {}
        }
        for _, wep in ipairs(self:GetWeapons()) do
            table.insert(self.PreSuitData.weaps, wep:GetClass())
        end

        self.bIsWearingSuit = true
        self:SetModel(suitData.model)
        

        timer.Simple(0.1, function()
            if not IsValid(self) or not self.bIsWearingSuit then return end
            

            for i = 0, self:GetNumBodyGroups() - 1 do
                self:SetBodygroup(i, 0)
            end


            if suitData.bodygroups then
                for id, val in pairs(suitData.bodygroups) do
                    self:SetBodygroup(tonumber(id), tonumber(val))
                end
            end
        end)

        self:SetMaxHealth(suitData.hp)
        self:SetHealth(suitData.hp)
        self:SetArmor(suitData.armor)
        self:SetWalkSpeed(suitData.walk_speed)
        self:SetRunSpeed(suitData.run_speed)


        if IsValid(currentHands) then
            if suitData.hands_model and suitData.hands_model ~= "" then
                currentHands:SetModel(suitData.hands_model)
            else
                local simpleName = player_manager.TranslateToPlayerModelName(suitData.model)
                local handInfo = player_manager.TranslatePlayerHands(simpleName)
                if handInfo and handInfo.model then
                    currentHands:SetModel(handInfo.model)
                end
            end
        end

        self:StripWeapons()
        if suitData.weapons then
            for _, w in ipairs(suitData.weapons) do self:Give(w) end
        end

        if CustomSuitsHUD and CustomSuitsHUD.SetSuitHUD then
            CustomSuitsHUD.SetSuitHUD(self, suitData.hud)
        end

        self:ChatPrint("Костюм '" .. suitData.name .. "' надет!")
    end

    function plyMeta:ClearCustomSuitOnDeath()
        if not self.bIsWearingSuit or not self.PreSuitData then return end

        local old = self.PreSuitData

        if old.model and old.model ~= "" then
            self:SetModel(old.model)
        end

        timer.Simple(0.1, function()
            if not IsValid(self) or not old.bgroups then return end
            for id, val in pairs(old.bgroups) do
                self:SetBodygroup(id, val)
            end
        end)

        self:SetMaxHealth(old.maxHp)
        self:SetArmor(old.armor)
        self:SetWalkSpeed(old.walk)
        self:SetRunSpeed(old.run)

        local currentHands = self:GetHands()
        if IsValid(currentHands) and old.hands_model and old.hands_model ~= "" then
            currentHands:SetModel(old.hands_model)
        end

        self.bIsWearingSuit = false

        if CustomSuitsHUD and CustomSuitsHUD.ClearSuitHUD then
            CustomSuitsHUD.ClearSuitHUD(self)
        end

        self.PreSuitData = nil
    end

    function plyMeta:RemoveCustomSuit()
        if not self.bIsWearingSuit or not self.PreSuitData then return end

        local old = self.PreSuitData
        self:SetModel(old.model)
        timer.Simple(0.1, function()
            if not IsValid(self) or not old.bgroups then return end
            for id, val in pairs(old.bgroups) do
                self:SetBodygroup(id, val)
            end
        end)

        self:SetMaxHealth(old.maxHp)
        self:SetHealth(math.min(old.hp, old.maxHp))
        self:SetArmor(old.armor)
        self:SetWalkSpeed(old.walk)
        self:SetRunSpeed(old.run)

        local currentHands = self:GetHands()
        if IsValid(currentHands) and old.hands_model and old.hands_model ~= "" then
            currentHands:SetModel(old.hands_model)
        end

        self:StripWeapons()
        for _, w in ipairs(old.weaps) do self:Give(w) end

        self.bIsWearingSuit = false

        if CustomSuitsHUD and CustomSuitsHUD.ClearSuitHUD then
            CustomSuitsHUD.ClearSuitHUD(self)
        end

        self.PreSuitData = nil
        self:ChatPrint("Снаряжение снято.")
    end

    hook.Add("PlayerDeath", "CustomSuits_ClearOnDeath", function(ply)
        if IsValid(ply) and ply:IsPlayer() and ply.bIsWearingSuit then
            ply:ClearCustomSuitOnDeath()
        end
    end)

    concommand.Add("remove_suit", function(ply)
        if IsValid(ply) then ply:RemoveCustomSuit() end
    end)
end

-- Команда для просмотра bodygroup id шобы удобно было
if SERVER then
    concommand.Add("get_bg", function(ply)
        if not IsValid(ply) then return end
        
        ply:ChatPrint("--- [BODYGROUPS LIST] ---")
        for i = 0, ply:GetNumBodyGroups() - 1 do
            local name = ply:GetBodygroupName(i)
            local count = ply:GetBodygroupCount(i)
            ply:ChatPrint("ID: " .. i .. " | Имя: " .. name .. " | Вариантов: " .. count)
        end
        ply:ChatPrint("-------------------------")
    end)
end