local _, ns = ...

-- The auras: each one's trigger is looked at when the game says something it hangs on changed (a spell's usability
-- or cooldown, combat, your spells), not every frame; its icon, timer, cooldown and button glow follow. The window's
-- countdown is the one thing that runs on a clock, ten times a second, and only while one is showing.

local Auras = {}
ns.Auras = Auras

local issecret = FrogLib.issecret
local displays = {}   -- index -> icon frame
local state = {}      -- aura table -> { active, since }
local resolved = {}   -- aura table -> { spellID, name, icon } or false: its spell, looked up once (spells change it)
local glowing = {}    -- lower-case spell names glowing now, the table reused
local inCombat = false
local cooldownDirty = true
local countdown       -- the ticker for the windows' countdowns, while any shows

------------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------------

-- A spell typed by name or ID -> its ID, name and icon, or nil if you don't know it. By name, any
-- rank you have counts.
local function LookUp(spell)
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

local function Spell(aura)
    local known = resolved[aura]
    if known == nil then
        local spellID, name, icon = LookUp(aura.trigger.spell)
        known = spellID and { spellID = spellID, name = name, icon = icon } or false
        resolved[aura] = known
    end
    return known or nil
end

local function IsUsable(spellID)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(spellID) end
    return IsUsableSpell(spellID)
end

------------------------------------------------------------------------------
-- Triggers: each returns active, noPower
------------------------------------------------------------------------------

local TRIGGERS = {}

-- A spell becomes usable (Revenge after a block, dodge or parry). Active while it's usable, or
-- would be but for rage or mana (shown tinted blue then, as the action buttons do).
TRIGGERS.usable = function(spell)
    local usable, noPower = IsUsable(spell.spellID)
    return (usable or noPower) and true or false, noPower and not usable
end

------------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------------

local function SavePoint(display, aura)
    local point, _, relativePoint, x, y = display:GetPoint()
    aura.point = { point, relativePoint, x, y }
end

local function Display(index)
    local display = displays[index]
    if display then return display end
    display = CreateFrame("Frame", nil, UIParent)
    display:SetFrameStrata("MEDIUM")
    display:SetClampedToScreen(true)
    display:SetMovable(true)
    FrogLib.Mover.Make(display, { save = function()
        local aura = ns.db.auras[display.index]
        if aura then SavePoint(display, aura) end
    end })

    local back = display:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.9)
    display.icon = display:CreateTexture(nil, "ARTWORK")
    display.icon:SetPoint("TOPLEFT", 1, -1)
    display.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    display.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    display.cooldown = CreateFrame("Cooldown", nil, display, "CooldownFrameTemplate")
    display.cooldown:SetAllPoints(display.icon)
    display.cooldown:SetDrawEdge(false)
    if display.cooldown.SetDrawBling then display.cooldown:SetDrawBling(false) end
    if display.cooldown.SetHideCountdownNumbers then display.cooldown:SetHideCountdownNumbers(true) end

    local top = CreateFrame("Frame", nil, display)
    top:SetAllPoints()
    top:SetFrameLevel(display.cooldown:GetFrameLevel() + 2)
    display.timer = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    display.timer:SetPoint("CENTER")
    display.timer:SetShadowOffset(1, -1)
    display.label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    display.label:SetPoint("TOP", display, "BOTTOM", 0, -2)

    display:Hide()
    displays[index] = display
    return display
end

local function Layout(display, aura)
    display:SetSize(aura.size, aura.size)
    local point = aura.point
    display:ClearAllPoints()
    display:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    local font = display.timer:GetFont()
    if font then display.timer:SetFont(font, math.max(10, math.floor(aura.size * 0.4)), "OUTLINE") end
end

local function PlayProc()
    local kit = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 12889
    pcall(PlaySound, kit, "Master")
end

-- The spell's cooldown on the icon. In combat its times can be secret, which SetCooldown refuses (quietly): then the
-- game's duration object for it, which the cooldown frame takes as it is.
local function ShowCooldown(display, spellID)
    local cooldown = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if not (cooldown and cooldown.isEnabled) then
        display.cooldown:Clear()
        return
    end
    if not (issecret(cooldown.startTime) or issecret(cooldown.duration)) then
        pcall(display.cooldown.SetCooldown, display.cooldown, cooldown.startTime, cooldown.duration, cooldown.modRate)
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellID)
    if not (duration and display.cooldown.SetCooldownFromDurationObject
        and pcall(display.cooldown.SetCooldownFromDurationObject, display.cooldown, duration)) then
        display.cooldown:Clear()
    end
end

------------------------------------------------------------------------------
-- Looking again
------------------------------------------------------------------------------

-- The window's countdown, from when it opened. Returns whether it's still counting.
local function Countdown(display, aura, tracked, now)
    local left = aura.window - (now - (tracked.since or now))
    if aura.showTimer and aura.window > 0 and left > 0 then
        display.timer:SetFormattedText(left < 3 and "%.1f" or "%d", left)
        return true
    end
    display.timer:SetText("")
    return false
end

-- One aura. Returns whether its countdown is running.
local function UpdateAura(index, aura, now)
    local display = Display(index)
    display.index = index
    local unlocked = not ns.db.locked
    local trigger = TRIGGERS[aura.trigger.type]
    local spell = aura.enabled and trigger and Spell(aura)
    local active, noPower = false, false
    if spell then active, noPower = trigger(spell) end

    local tracked = state[aura]
    if not tracked then
        tracked = {}
        state[aura] = tracked
    end
    if active and not tracked.active then
        tracked.since = now
        if aura.sound then PlayProc() end
    end
    tracked.active = active

    local shown = active and (not aura.combatOnly or inCombat)
    if shown and aura.glow and spell then glowing[spell.name:lower()] = true end

    if unlocked then
        -- A sample of every aura, to place them.
        local sample = Spell(aura)
        display.icon:SetTexture(sample and sample.icon or 134400)
        display.icon:SetVertexColor(1, 1, 1)
        display.label:SetText(aura.name)
        display.timer:SetText(aura.window > 0 and aura.showTimer and aura.window or "")
        display.cooldown:Clear()
        display:EnableMouse(true)
        display:Show()
        return false
    end
    display.label:SetText("")
    display:EnableMouse(false)
    if not shown then
        display:Hide()
        return false
    end

    display.icon:SetTexture(spell.icon)
    if noPower then display.icon:SetVertexColor(0.5, 0.5, 1) else display.icon:SetVertexColor(1, 1, 1) end
    local counting = Countdown(display, aura, tracked, now)
    if cooldownDirty or not display:IsShown() then ShowCooldown(display, spell.spellID) end
    display:Show()
    return counting
end

local Tick

-- The countdowns alone, ten times a second while one runs (nothing else changes between events).
local function Count()
    local now, any = GetTime(), false
    for index, aura in ipairs(ns.db.auras) do
        local display, tracked = displays[index], state[aura]
        if display and display:IsShown() and tracked and tracked.active and ns.db.locked then
            if Countdown(display, aura, tracked, now) then any = true end
        end
    end
    if not any and countdown then
        countdown:Cancel()
        countdown = nil
    end
end

function Tick()
    local now, counting = GetTime(), false
    wipe(glowing)
    for index, aura in ipairs(ns.db.auras) do
        if UpdateAura(index, aura, now) then counting = true end
    end
    for index = #ns.db.auras + 1, #displays do displays[index]:Hide() end
    cooldownDirty = false
    ns.Glow:Update(glowing)
    if counting and not countdown then
        countdown = C_Timer.NewTicker(0.1, Count)
    elseif not counting and countdown then
        countdown:Cancel()
        countdown = nil
    end
end

-- Events come in bursts (a power tick sends several): one look a frame later.
local queued = false
local function Soon()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Tick()
    end)
end

Auras.Soon = Soon -- (Glow.lua asks for a look after the bars change)

function Auras:Rebuild()
    wipe(resolved) -- the spells may have changed with the settings
    for index, aura in ipairs(ns.db.auras) do Layout(Display(index), aura) end
    for index = #ns.db.auras + 1, #displays do displays[index]:Hide() end
    cooldownDirty = true
    Soon()
end

function Auras:Init()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_COOLDOWN",
        "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            cooldownDirty = true
        elseif event == "SPELLS_CHANGED" then
            wipe(resolved) -- a new rank, a talent
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            inCombat = event == "PLAYER_REGEN_DISABLED"
        end
        Soon()
    end)
    self:Rebuild()
end
