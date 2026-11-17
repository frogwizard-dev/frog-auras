local _, ns = ...

-- A pulsing gold glow on every action button that holds a given spell (directly, or as a macro's
-- spell). Our own frames on top of the buttons, rather than Blizzard's spell alerts: those belong
-- to Blizzard's secure buttons, and driving them from an add-on could taint them. The pulse is an animation the game
-- plays, not a script every frame; the buttons are found once, and looked over only when what glows changes.

local Glow = {}
ns.Glow = Glow

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local issecret = FrogLib.issecret
local slotSpell = {}  -- action slot -> lower-case spell name (or false), cached until bars change
local glows = {}      -- button -> glow frame
local buttons         -- every action button, found once
local lastKey = ""    -- the names glowing at the last update, sorted and joined
local keyParts = {}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function SlotSpell(slot)
    local cached = slotSpell[slot]
    if cached ~= nil then return cached end
    local name = false
    local kind, id = GetActionInfo(slot)
    -- What a button holds can turn secret in an instance's fight: not looked up then (tried again next time).
    if issecret(kind) or issecret(id) then return false end
    if kind == "spell" and id then
        name = SpellName(id)
    elseif kind == "macro" and id and GetMacroSpell then
        local spellID = GetMacroSpell(id)
        name = spellID and not issecret(spellID) and SpellName(spellID)
    end
    name = name and name:lower() or false
    slotSpell[slot] = name
    return name
end

local function Buttons()
    if buttons then return buttons end
    buttons = {}
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button then buttons[#buttons + 1] = button end
        end
    end
    return buttons
end

local function Edge(frame, from, to, horizontal)
    local edge = frame:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(1, 0.82, 0.25, 1)
    edge:SetPoint(from)
    edge:SetPoint(to)
    if horizontal then edge:SetHeight(2) else edge:SetWidth(2) end
end

local function GlowFrame(button)
    local glow = glows[button]
    if glow then return glow end
    glow = CreateFrame("Frame", nil, button)
    glow:SetAllPoints()
    glow:SetFrameLevel(button:GetFrameLevel() + 10)
    -- A crisp square edge (it suits FrogUI's square buttons) with a soft halo behind it.
    local halo = glow:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    halo:SetBlendMode("ADD")
    halo:SetVertexColor(1, 0.8, 0.3)
    halo:SetPoint("CENTER")
    glow.halo = halo
    Edge(glow, "TOPLEFT", "TOPRIGHT", true)
    Edge(glow, "BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge(glow, "TOPLEFT", "BOTTOMLEFT", false)
    Edge(glow, "TOPRIGHT", "BOTTOMRIGHT", false)
    -- The pulse, 0.1 to 1 and back about once a second (as the sine it was).
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.1)
    fade:SetDuration(0.52)
    fade:SetSmoothing("IN_OUT")
    glow.pulse = pulse
    glow:Hide()
    glows[button] = glow
    return glow
end

-- names: { revenge = true }, lower-case spell names to glow; every other button stops. Only looked over when the set
-- changes (or forced, after the bars change).
function Glow:Update(names, force)
    wipe(keyParts)
    for name in pairs(names) do keyParts[#keyParts + 1] = name end
    table.sort(keyParts)
    local key = table.concat(keyParts, "|")
    if key == lastKey and not force then return end
    lastKey = key
    for _, button in ipairs(Buttons()) do
        local name = button.action and SlotSpell(button.action)
        local on = name and names[name] and button:IsVisible()
        if on then
            local glow = GlowFrame(button)
            local width = button:GetWidth()
            glow.halo:SetSize(width * 1.9, width * 1.9)
            glow:Show()
            if not glow.pulse:IsPlaying() then glow.pulse:Play() end
        elseif glows[button] then
            glows[button].pulse:Stop()
            glows[button]:Hide()
        end
    end
end

-- Bars change: a slot's spell is looked up again, and the glows laid on again.
local events = CreateFrame("Frame")
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_MACROS", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    wipe(slotSpell)
    lastKey = nil -- the next update looks every button over
    if ns.Auras and ns.Auras.Soon then ns.Auras.Soon() end
end)
