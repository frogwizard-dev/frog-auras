local _, ns = ...

-- A pulsing gold glow on every action button that holds a given spell (directly, or as a macro's
-- spell). Our own frames on top of the buttons, rather than Blizzard's spell alerts: those belong
-- to Blizzard's secure buttons, and driving them from an add-on could taint them.
--
--   ns.Glow:Update({ revenge = true })  -- lower-case spell names to glow; everything else stops

local Glow = {}
ns.Glow = Glow

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local slotSpell = {}  -- action slot -> lower-case spell name (or false), cached until bars change
local glows = {}      -- button -> glow frame

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function SlotSpell(slot)
    local cached = slotSpell[slot]
    if cached ~= nil then return cached end
    local name = false
    local kind, id = GetActionInfo(slot)
    if kind == "spell" and id then
        name = SpellName(id)
    elseif kind == "macro" and id and GetMacroSpell then
        local spellID = GetMacroSpell(id)
        name = spellID and SpellName(spellID)
    end
    name = name and name:lower() or false
    slotSpell[slot] = name
    return name
end

local function Edge(f, a1, a2, horizontal)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.82, 0.25, 1)
    t:SetPoint(a1)
    t:SetPoint(a2)
    if horizontal then t:SetHeight(2) else t:SetWidth(2) end
end

local function GlowFrame(button)
    local g = glows[button]
    if g then return g end
    g = CreateFrame("Frame", nil, button)
    g:SetAllPoints()
    g:SetFrameLevel(button:GetFrameLevel() + 10)
    -- A crisp square edge (it suits FrogUI's square buttons) with a soft halo behind it.
    local halo = g:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    halo:SetBlendMode("ADD")
    halo:SetVertexColor(1, 0.8, 0.3)
    halo:SetPoint("CENTER")
    g.halo = halo
    Edge(g, "TOPLEFT", "TOPRIGHT", true)
    Edge(g, "BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge(g, "TOPLEFT", "BOTTOMLEFT", false)
    Edge(g, "TOPRIGHT", "BOTTOMRIGHT", false)
    local t = 0
    g:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        self:SetAlpha(0.55 + 0.45 * math.sin(t * 6))
    end)
    g:Hide()
    glows[button] = g
    return g
end

function Glow:Update(names)
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and button.action then
                local name = SlotSpell(button.action)
                local on = name and names[name] and button:IsVisible()
                if on then
                    local g = GlowFrame(button)
                    local w = button:GetWidth()
                    g.halo:SetSize(w * 1.9, w * 1.9)
                    g:Show()
                elseif glows[button] then
                    glows[button]:Hide()
                end
            end
        end
    end
end

-- Bars change: a slot's spell is looked up again.
local events = CreateFrame("Frame")
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_MACROS", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function() wipe(slotSpell) end)
