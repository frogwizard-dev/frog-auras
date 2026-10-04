local _, ns = ...
local UI = ns.UI

local TRIGGER_TYPES = UI.Options("usable", "Spell becomes usable (procs like Revenge)")

-- The aura being edited. Every control reads and writes it; picking another aura re-shows the
-- page so the controls pick up its values.
ns.selected = 1
local NONE = ns.NewAura({ name = "(no auras)" }) -- stands in when the list is empty; never saved

local function Selected()
    return ns.db.auras[ns.selected] or NONE
end

local function AuraList()
    local items = {}
    for index, aura in ipairs(ns.db.auras) do
        items[#items + 1] = { name = index .. ". " .. aura.name, path = index }
    end
    return { { items = items } }
end

local function BuildAuras(p)
    local function reshow()
        C_Timer.After(0, function()
            p:Hide()
            p:Show()
        end)
    end
    local place = UI.Placer()
    place(UI.Checkbox(p, "Unlock: show every aura and drag them into place",
        function() return not ns.db.locked end, function(v) ns.db.locked = not v end), 34)

    place(UI.Dropdown(p, "Aura", AuraList, function() return ns.selected end, function(v)
        ns.selected = v
        reshow()
    end), 30)
    local add = UI.Button(p, "New aura", 120, 22)
    add:SetScript("OnClick", function()
        table.insert(ns.db.auras, ns.NewAura({ name = "Aura " .. (#ns.db.auras + 1) }))
        ns.selected = #ns.db.auras
        ns.Refresh()
        reshow()
    end)
    local remove = UI.Button(p, "Delete this aura", 140, 22)
    remove:SetPoint("LEFT", add, "RIGHT", 8, 0)
    remove:SetScript("OnClick", function()
        if not ns.db.auras[ns.selected] then return end
        table.remove(ns.db.auras, ns.selected)
        ns.selected = math.max(1, math.min(ns.selected, #ns.db.auras))
        ns.Refresh()
        reshow()
    end)
    place(add, 36, 4)

    place(UI.TextBox(p, "Name", function() return Selected().name end,
        function(v) Selected().name = v end), 28)
    place(UI.Checkbox(p, "On",
        function() return Selected().enabled end, function(v) Selected().enabled = v end), 32)

    place(UI.Label(p, "Trigger"), 22)
    place(UI.Dropdown(p, "When", TRIGGER_TYPES, function() return Selected().trigger.type end,
        function(v) Selected().trigger.type = v end), 30)
    place(UI.TextBox(p, "Spell (name or ID)", function() return tostring(Selected().trigger.spell) end,
        function(v) Selected().trigger.spell = strtrim(v) end), 28)
    place(UI.Stepper(p, "Window (seconds)", 0, 30, 0.5, function() return Selected().window end,
        function(v) Selected().window = v end, "%.1f"), 32)

    place(UI.Label(p, "Display"), 22)
    place(UI.Stepper(p, "Icon size", 16, 128, 2, function() return Selected().size end,
        function(v) Selected().size = v end), 28)
    place(UI.Checkbox(p, "Count down the window on the icon",
        function() return Selected().showTimer end, function(v) Selected().showTimer = v end), 26)
    place(UI.Checkbox(p, "Glow on the action button that holds the spell",
        function() return Selected().glow end, function(v) Selected().glow = v end), 26)
    place(UI.Checkbox(p, "Play a sound when it procs",
        function() return Selected().sound end, function(v) Selected().sound = v end), 26)
    place(UI.Checkbox(p, "Only in combat",
        function() return Selected().combatOnly end, function(v) Selected().combatOnly = v end), 34)

    place(UI.Help(p, "Revenge: usable for a few seconds after you block, dodge or parry (5 by default; "
        .. "change Window if Forever differs). The icon turns blue while you're short of rage. The "
        .. "countdown starts when it lights up; a second block while it's up isn't seen.", 440), 48)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("FrogAurasConfig", "FrogAuras", 480, 640, {
            { "auras", "Auras", BuildAuras },
        })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end

-- Its entry in the game's Options > AddOns list (Options.lua).
ns.AddOptionsPanel({
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = {
        { "/fa", "open or close the settings" },
        { "/fa unlock", "show every aura to drag into place (/fa lock when done)" },
    },
})
