--------------------------------------------------------------
-- PM Toolbar — compact floating panel
-- Keep this open while painting. Drag it to a corner.
-- Colorize/Desaturate with one click, see results live.
--------------------------------------------------------------

local WORK_SATURATION = 5
local MARKER_SATURATION = 100   -- S% markers are set to by PaletteManager

local function ensureSprite()
  local spr = app.sprite
  if not spr then
    app.alert("Please open or create a sprite first!")
    return nil
  end
  return spr
end

local function applysat(newSat)
  local spr = ensureSprite()
  if not spr then return end

  app.transaction("Set Saturation", function()
    local pal = spr.palettes[1]
    local total = #pal
    local markerHue = nil
    for i = 0, total - 1 do
      local c = pal:getColor(i)
      if c.saturation * 100 == MARKER_SATURATION then
        markerHue = c.hue
      elseif markerHue then
        pal:setColor(i, Color{
          hue = markerHue,
          saturation = newSat / 100,
          value = c.value,
          alpha = 255
        })
      end
    end
  end)
  app.refresh()
end

local dlg = Dialog("PM Toolbar")

dlg:slider{
  id="sat",
  label="S%",
  min=5,
  max=MARKER_SATURATION - 1,
  value=70
}

dlg:button{
  id="colorize",
  text="Colorize",
  onclick=function()
    applysat(dlg.data.sat)
  end
}

dlg:button{
  id="desaturate",
  text="Desaturate",
  onclick=function()
    applysat(WORK_SATURATION)
  end
}

dlg:show{wait=false}
