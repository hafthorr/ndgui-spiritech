-- SoftMenu actions that open a window this package ships.
-- Historic targets (pets, perks, research, and the rest) are not listed.

local M = {
  { id = "inventory", label = "Inv", opens = "inventory" },
  { id = "chat", label = "Chat", opens = "chat" },
  { id = "raid", label = "Raid", opens = "raid" },
  { id = "options", label = "Opt", opens = "options" },
}

local by_id = {}
for i = 1, #M do
  by_id[M[i].id] = M[i]
end

local catalog = {}

function catalog.list()
  local out = {}
  for i = 1, #M do
    local item = M[i]
    out[i] = { id = item.id, label = item.label, opens = item.opens }
  end
  return out
end

function catalog.get(id)
  local item = by_id[id]
  if not item then return nil end
  return { id = item.id, label = item.label, opens = item.opens }
end

if ui and ui.define then
  ui.define("ndgui.catalog", function() return catalog end)
end
return catalog
