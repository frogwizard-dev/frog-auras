local ADDON, ns = ...

-- FrogAuras: WeakAuras-style trackers. Each aura has a trigger (what to watch) and a display (an
-- icon on screen, a glow on the action button that holds the spell, a sound).
--
-- Triggers so far:
--   "usable": a spell becomes usable, e.g. Revenge after you block, dodge or parry. The icon shows
--             while it's usable (tinted blue while you lack the rage or mana for it), with a
--             countdown of the window and the spell's own cooldown.
-- New trigger types slot in beside it in Aura.lua (TRIGGERS).

-- One aura's settings; every aura is filled out with these.
ns.AURA_DEFAULTS = {
    name = "New aura",
    enabled = true,
    trigger = { type = "usable", spell = "" },
    size = 48,
    point = { "CENTER", "CENTER", 0, -140 },
    window = 5,          -- seconds the proc lasts (a countdown on the icon; 0 = none)
    glow = true,         -- pulse the action button that holds the spell
    sound = false,       -- a chime when it procs
    combatOnly = false,  -- only show it in combat
    showTimer = true,
}

-- What a fresh install starts with.
local FIRST_AURAS = {
    { name = "Revenge", trigger = { type = "usable", spell = "Revenge" }, window = 5 },
}

ns.defaults = {
    locked = true, -- unlocked: every aura shows (a sample) and can be dragged
}

function ns.Print(...)
    print("|cff7fd15fFrogAuras|r:", ...)
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.CopyDefaults = CopyDefaults

function ns.NewAura(template)
    local aura = template or {}
    CopyDefaults(ns.AURA_DEFAULTS, aura)
    return aura
end

function ns.Refresh()
    ns.Auras:Rebuild()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        FrogAurasDB = FrogAurasDB or {}
        local db = FrogAurasDB
        if not db.auras then
            db.auras = {}
            for _, aura in ipairs(FIRST_AURAS) do table.insert(db.auras, aura) end
        end
        for _, aura in ipairs(db.auras) do ns.NewAura(aura) end
        CopyDefaults(ns.defaults, db)
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        ns.Auras:Init()
    end
end)

SLASH_FROGAURAS1 = "/fa"
SLASH_FROGAURAS2 = "/frogauras"
SlashCmdList.FROGAURAS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" or msg == "unlock" then
        ns.db.locked = msg == "lock"
        ns.Refresh()
    else
        ns.ToggleConfig()
    end
end
function FrogAuras_OnCompartmentClick() ns.ToggleConfig() end
