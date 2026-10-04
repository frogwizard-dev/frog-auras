local _, ns = ...

-- The auras: each one's trigger is checked a few times a second, and its icon, timer, cooldown
-- and button glow follow.

local Auras = {}
ns.Auras = Auras

local TICK = 0.05
local displays = {}   -- index -> icon frame
local state = {}      -- aura table -> { active, since }
local inCombat = false
local cooldownDirty = true

------------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------------

-- A spell typed by name or ID -> its ID, name and icon, or nil if you don't know it. By name, any
-- rank you have counts.
local function Spell(spell)
    if spell == nil or spell == "" then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local key = tonumber(spell) or spell
    local info = C_Spell.GetSpellInfo(key)
    -- An ID for a rank you don't have: go by its name instead (a name finds your own rank).
    if info and type(key) == "number" and IsPlayerSpell and not IsPlayerSpell(info.spellID) then
        info = C_Spell.GetSpellInfo(info.name)
    end
    if not info then return nil end
    return info.spellID, info.name, info.iconID
end

local function IsUsable(spellID)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(spellID) end
    return IsUsableSpell(spellID)
end

------------------------------------------------------------------------------
-- Triggers: each returns active, extra (what the display needs)
------------------------------------------------------------------------------

local TRIGGERS = {}

-- A spell becomes usable (Revenge after a block, dodge or parry). Active while it's usable, or
-- would be but for rage or mana (shown tinted blue then, as the action buttons do).
TRIGGERS.usable = function(trigger)
    local spellID, name, icon = Spell(trigger.spell)
    if not spellID then return false end
    local usable, noPower = IsUsable(spellID)
    return (usable or noPower) and true or false, { spellID = spellID, name = name, icon = icon, noPower = noPower and not usable }
end

------------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------------

local function SavePoint(f, aura)
    local p, _, rp, x, y = f:GetPoint()
    aura.point = { p, rp, x, y }
end

local function Display(index)
    local f = displays[index]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local aura = ns.db.auras[self.index]
        if aura then SavePoint(self, aura) end
    end)

    local back = f:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.9)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints(f.icon)
    f.cooldown:SetDrawEdge(false)
    if f.cooldown.SetDrawBling then f.cooldown:SetDrawBling(false) end
    if f.cooldown.SetHideCountdownNumbers then f.cooldown:SetHideCountdownNumbers(true) end

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f.cooldown:GetFrameLevel() + 2)
    f.timer = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.timer:SetPoint("CENTER")
    f.timer:SetShadowOffset(1, -1)
    f.label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)

    f:Hide()
    displays[index] = f
    return f
end

local function Layout(f, aura)
    f:SetSize(aura.size, aura.size)
    local p = aura.point
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    local font = f.timer:GetFont()
    if font then f.timer:SetFont(font, math.max(10, math.floor(aura.size * 0.4)), "OUTLINE") end
end

local function PlayProc()
    local kit = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 12889
    pcall(PlaySound, kit, "Master")
end

------------------------------------------------------------------------------
-- The loop
------------------------------------------------------------------------------

local function UpdateAura(index, aura, now, glowing)
    local f = Display(index)
    f.index = index
    local unlocked = not ns.db.locked
    local trigger = TRIGGERS[aura.trigger.type]
    local active, extra = false, nil
    if aura.enabled and trigger then active, extra = trigger(aura.trigger) end

    local s = state[aura]
    if not s then
        s = {}
        state[aura] = s
    end
    if active and not s.active then
        s.since = now
        if aura.sound then PlayProc() end
    end
    s.active = active

    local shown = active and (not aura.combatOnly or inCombat)
    if shown and aura.glow and extra and extra.name then glowing[extra.name:lower()] = true end

    if unlocked then
        -- A sample of every aura, to place them.
        local _, name, icon = Spell(aura.trigger.spell)
        f.icon:SetTexture(icon or (extra and extra.icon) or 134400)
        f.icon:SetVertexColor(1, 1, 1)
        f.label:SetText(aura.name)
        f.timer:SetText(aura.window > 0 and aura.showTimer and aura.window or "")
        f.cooldown:Clear()
        f:EnableMouse(true)
        f:Show()
        return
    end
    f.label:SetText("")
    f:EnableMouse(false)
    if not shown then
        f:Hide()
        return
    end

    f.icon:SetTexture(extra.icon)
    if extra.noPower then f.icon:SetVertexColor(0.5, 0.5, 1) else f.icon:SetVertexColor(1, 1, 1) end
    -- The window's countdown, from when it opened.
    local left = aura.window - (now - (s.since or now))
    if aura.showTimer and aura.window > 0 and left > 0 then
        f.timer:SetFormattedText(left < 3 and "%.1f" or "%d", left)
    else
        f.timer:SetText("")
    end
    if cooldownDirty or not f:IsShown() then
        local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(extra.spellID)
        if cd and cd.isEnabled then
            pcall(f.cooldown.SetCooldown, f.cooldown, cd.startTime, cd.duration, cd.modRate)
        else
            f.cooldown:Clear()
        end
    end
    f:Show()
end

local function Tick()
    local now = GetTime()
    local glowing = {}
    for index, aura in ipairs(ns.db.auras) do UpdateAura(index, aura, now, glowing) end
    for index = #ns.db.auras + 1, #displays do displays[index]:Hide() end
    cooldownDirty = false
    ns.Glow:Update(glowing)
end

function Auras:Rebuild()
    for index, aura in ipairs(ns.db.auras) do Layout(Display(index), aura) end
    for index = #ns.db.auras + 1, #displays do displays[index]:Hide() end
    cooldownDirty = true
end

function Auras:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            cooldownDirty = true
        else
            inCombat = event == "PLAYER_REGEN_DISABLED"
        end
    end)
    local t = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t < TICK then return end
        t = 0
        Tick()
    end)
    self:Rebuild()
end

Auras.Spell = Spell
