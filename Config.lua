local _, ns = ...

-- The settings controls are FrogLib's (UI.lua); every change calls ns.Refresh().
local UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })

local TRIGGER_TYPES = UI.Options("usable", "Spell becomes usable (procs like Revenge)")

-- The aura being edited. Every control reads and writes it; picking another aura re-shows the
-- page so the controls pick up its values.
local selected = 1
local NONE = ns.NewAura({ name = "(no auras)" }) -- stands in when the list is empty; never saved

local function Selected()
    return ns.db.auras[selected] or NONE
end

local function AuraList()
    local items = {}
    for index, aura in ipairs(ns.db.auras) do
        items[#items + 1] = { name = index .. ". " .. aura.name, path = index }
    end
    return { { items = items } }
end

local function BuildAuras(page)
    local function Reshow()
        C_Timer.After(0, function()
            page:Hide()
            page:Show()
        end)
    end
    local place = UI.Placer()
    place(UI.Checkbox(page, "Unlock: show every aura and drag them into place",
        function() return not ns.db.locked end, function(value) ns.db.locked = not value end), 34)

    place(UI.Dropdown(page, "Aura", AuraList, function() return selected end, function(value)
        selected = value
        Reshow()
    end), 30)
    local add = UI.Button(page, "New aura", 120, 22)
    add:SetScript("OnClick", function()
        table.insert(ns.db.auras, ns.NewAura({ name = "Aura " .. (#ns.db.auras + 1) }))
        selected = #ns.db.auras
        ns.Refresh()
        Reshow()
    end)
    local remove = UI.Button(page, "Delete this aura", 140, 22)
    remove:SetPoint("LEFT", add, "RIGHT", 8, 0)
    remove:SetScript("OnClick", function()
        if not ns.db.auras[selected] then return end
        table.remove(ns.db.auras, selected)
        selected = math.max(1, math.min(selected, #ns.db.auras))
        ns.Refresh()
        Reshow()
    end)
    place(add, 36, 4)

    place(UI.TextBox(page, "Name", function() return Selected().name end,
        function(value) Selected().name = value end), 28)
    place(UI.Checkbox(page, "On",
        function() return Selected().enabled end, function(value) Selected().enabled = value end), 32)

    place(UI.Label(page, "Trigger"), 22)
    place(UI.Dropdown(page, "When", TRIGGER_TYPES, function() return Selected().trigger.type end,
        function(value) Selected().trigger.type = value end), 30)
    place(UI.TextBox(page, "Spell (name or ID)", function() return tostring(Selected().trigger.spell) end,
        function(value) Selected().trigger.spell = strtrim(value) end), 28)
    place(UI.Stepper(page, "Window (seconds)", 0, 30, 0.5, function() return Selected().window end,
        function(value) Selected().window = value end, "%.1f"), 32)

    place(UI.Label(page, "Display"), 22)
    place(UI.Stepper(page, "Icon size", 16, 128, 2, function() return Selected().size end,
        function(value) Selected().size = value end), 28)
    place(UI.Checkbox(page, "Count down the window on the icon",
        function() return Selected().showTimer end, function(value) Selected().showTimer = value end), 26)
    place(UI.Checkbox(page, "Glow on the action button that holds the spell",
        function() return Selected().glow end, function(value) Selected().glow = value end), 26)
    place(UI.Checkbox(page, "Play a sound when it procs",
        function() return Selected().sound end, function(value) Selected().sound = value end), 26)
    place(UI.Checkbox(page, "Only in combat",
        function() return Selected().combatOnly end, function(value) Selected().combatOnly = value end), 34)

    place(UI.Help(page, "Revenge: usable for a few seconds after you block, dodge or parry (5 by default; "
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
FrogLib.Options.Add("FrogAuras", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = {
        { "/fa", "open or close the settings" },
        { "/fa unlock", "show every aura to drag into place (/fa lock when done)" },
    },
})
