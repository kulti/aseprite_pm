--------------------------------------------------------------
-- PM Toggle — one hotkey to switch between gray and color
--
-- Detects current palette state by checking ramp saturation.
-- Uses marker hue (S=100%) as the source of truth for each
-- group, to avoid hue drift from RGB rounding.
--
-- Works with any number of value steps per group.
--
-- Bind to a hotkey in Edit > Keyboard Shortcuts (e.g. F5).
--
-- Settings:
local COLORIZE_SATURATION = 70  -- S% when colorizing
local WORK_SATURATION = 5       -- S% when desaturating
local THRESHOLD = 20            -- S% boundary between states
local MARKER_SATURATION = 100   -- S% markers are set to by PaletteManager
--------------------------------------------------------------

local spr = app.sprite
if not spr then return app.alert("No active sprite!") end

local pal = spr.palettes[1]
local total = #pal

-- Detect current state: check ramp colors after first marker
local isColored = true
local foundMarker = false
for i = 0, total - 1 do
  local c = pal:getColor(i)
  if c.saturation * 100 == MARKER_SATURATION then
    foundMarker = true
  elseif foundMarker and c.saturation * 100 < THRESHOLD then
    isColored = false
    break
  end
end

local targetSat = isColored
  and WORK_SATURATION
  or COLORIZE_SATURATION

-- Apply: use marker hue for each group to avoid RGB rounding drift
app.transaction("Toggle Saturation", function()
  local markerHue = nil
  for i = 0, total - 1 do
    local c = pal:getColor(i)
    if c.saturation * 100 == MARKER_SATURATION then
      markerHue = c.hue
    elseif markerHue then
      pal:setColor(i, Color{
        hue = markerHue,
        saturation = targetSat / 100,
        value = c.value,
        alpha = 255
      })
    end
  end
end)

app.refresh()
