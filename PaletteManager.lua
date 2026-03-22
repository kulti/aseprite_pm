--------------------------------------------------------------
-- Palette Manager for Aseprite
-- A value-first pixel art workflow tool
--
-- Compact dialog with a shades-based color strip.
-- On open, auto-imports unique hues from the current palette.
-- Left-click a color in the strip to select it for removal.
-- Add colors from the foreground color picker.
-- Generate a full indexed palette with one click.
--
-- Companion scripts:
--   PM_Toolbar.lua  — floating saturation panel
--   PM_Toggle.lua   — one-hotkey colorize/desaturate toggle
--
-- Best used with Indexed Color Mode (Sprite > Color Mode > Indexed)
--
-- Install:
--   File > Scripts > Open Scripts Folder → copy files
--   File > Scripts > Rescan Scripts Folder
--   Run: File > Scripts > PaletteManager
--------------------------------------------------------------

local WORK_SATURATION = 5
local MARKER_SATURATION = 100

local PRESETS = {
  { name = "Full",    bright = 100, dark = 12, steps = 8 },
  { name = "Dark",    bright = 55,  dark = 8,  steps = 6 },
  { name = "Pastel",  bright = 95,  dark = 50, steps = 6 },
  { name = "Custom",  bright = 100, dark = 12, steps = 8 },
}

local function computeValues(bright, dark, steps)
  local vals = {}
  for i = 0, steps - 1 do
    local v = bright - (bright - dark) * i / (steps - 1)
    vals[#vals + 1] = math.floor(v + 0.5)
  end
  return vals
end

local currentValues = computeValues(100, 12, 8)

local function valuesToGrayColors(values)
  local colors = {}
  for _, v in ipairs(values) do
    colors[#colors + 1] = Color{ hue=0, saturation=0, value=v/100, alpha=255 }
  end
  return colors
end

--------------------------------------------------------------
-- Utilities
--------------------------------------------------------------

local function ensureSprite()
  local spr = app.sprite
  if not spr then
    app.alert("Please open or create a sprite first!")
    return nil
  end
  return spr
end

-- Detect existing palette structure by scanning for markers.
-- Returns hues (int degrees), hueColors (sorted by hue for UI),
-- paletteOrder (palette order for generation), and ramp geometry.
local function detectPaletteStructure(pal)
  local hues = {}
  local seen = {}
  local paletteOrder = {}
  local firstMarker = nil
  local rampSize = nil
  local lastMarkerIdx = nil
  local bright = nil
  local dark = nil

  for i = 0, #pal - 1 do
    local c = pal:getColor(i)
    if math.floor(c.saturation * 100 + 0.5) == MARKER_SATURATION then
      if not firstMarker then firstMarker = i end
      if lastMarkerIdx and not rampSize then
        rampSize = i - lastMarkerIdx
      end
      lastMarkerIdx = i
      local h = math.floor(c.hue + 0.5)
      table.insert(hues, h)
      if not seen[h] then
        seen[h] = true
        table.insert(paletteOrder, Color{
          hue = c.hue, saturation = 0.8, value = 0.7, alpha = 255
        })
      end
    end
  end

  -- Fallback: no markers found, scan for any saturated colors (user palettes)
  if #paletteOrder == 0 then
    seen = {}
    for i = 0, #pal - 1 do
      local c = pal:getColor(i)
      local s = c.saturation * 100
      local v = c.value * 100
      if s >= 15 and v > 5 and v < 100 then
        local h = math.floor(c.hue + 0.5)
        if not seen[h] then
          seen[h] = true
          table.insert(paletteOrder, Color{
            hue = c.hue, saturation = 0.8, value = 0.7, alpha = 255
          })
        end
      end
    end
  end

  -- Build hueColors as a hue-sorted copy
  local hueColors = {}
  for _, c in ipairs(paletteOrder) do
    hueColors[#hueColors + 1] = c
  end
  table.sort(hueColors, function(a, b) return a.hue < b.hue end)

  -- Determine bright/dark from first ramp (colors right after first marker)
  if firstMarker and rampSize and rampSize > 1 then
    local firstStep = pal:getColor(firstMarker + 1)
    local lastStep = pal:getColor(firstMarker + rampSize - 1)
    bright = math.floor(firstStep.value * 100 + 0.5)
    dark = math.floor(lastStep.value * 100 + 0.5)
  end

  return {
    hues = hues,
    hueColors = hueColors,
    paletteOrder = paletteOrder,
    fixedColors = firstMarker or 0,
    rampSize = rampSize or 0,
    steps = rampSize and (rampSize - 1) or 0,
    bright = bright,
    dark = dark
  }
end

-- Check if regeneration is safe (won't shift existing indices)
local function isGenerationSafe(oldStruct, newHues, newValues)
  if #oldStruct.hues == 0 then return true, nil end

  local newRampSize = 1 + #newValues
  local newFixedColors = 2 + #newValues

  if oldStruct.rampSize ~= 0 and oldStruct.rampSize ~= newRampSize then
    return false, "Steps count changed (" .. oldStruct.steps .. " → " .. #newValues .. ")"
  end
  if oldStruct.fixedColors ~= 0 and oldStruct.fixedColors ~= newFixedColors then
    return false, "Gray ramp size changed"
  end

  for i, oldH in ipairs(oldStruct.hues) do
    if i > #newHues then
      return false, "Color removed (hue " .. oldH .. "°)"
    end
    local newH = math.floor(newHues[i].hue + 0.5)
    if math.abs(oldH - newH) > 3 then
      return false, "Color order changed at position " .. i ..
        " (was " .. oldH .. "°, now " .. newH .. "°)"
    end
  end

  return true, nil
end

--------------------------------------------------------------
-- State
--------------------------------------------------------------

local hueColors = {}    -- sorted by hue, for UI display
local paletteOrder = {} -- palette order, for generation (new hues append to end)
local selectedIdx = nil -- index of selected color in hueColors (for removal)
local initialStructure = { hues = {}, fixedColors = 0, rampSize = 0, steps = 0 }

--------------------------------------------------------------
-- GENERATE PALETTE
--------------------------------------------------------------

local function generatePalette(targetColors, values)
  local spr = ensureSprite()
  if not spr then return end

  if #targetColors == 0 then
    app.alert("Add at least one color first!")
    return
  end

  local fixedColors = 2 + #values
  local rampSize = 1 + #values
  local totalColors = fixedColors + (#targetColors * rampSize)

  if totalColors > 256 then
    app.alert("Too many colors! Maximum " ..
      math.floor((256 - fixedColors) / rampSize) .. " groups.\n" ..
      "You have " .. #targetColors .. " groups.")
    return
  end

  -- Check if regeneration would shift existing indices
  local safe, reason = isGenerationSafe(initialStructure, targetColors, values)
  if not safe then
    local result = app.alert{
      title = "Warning",
      text = "This will shift palette indices and may break existing art!\n\n" ..
        "Reason: " .. reason .. "\n\n" ..
        "Proceed anyway?",
      buttons = {"Proceed", "Cancel"}
    }
    if result ~= 1 then return end
  end

  app.transaction("Generate Palette", function()
    local pal = spr.palettes[1]
    pal:resize(totalColors)

    pal:setColor(0, Color{r=0, g=0, b=0, a=255})
    pal:setColor(1, Color{r=0, g=0, b=0, a=255})
    for gi, v in ipairs(values) do
      pal:setColor(1 + gi, Color{
        hue = 0,
        saturation = 0,
        value = v / 100,
        alpha = 255
      })
    end

    local idx = fixedColors
    for i, col in ipairs(targetColors) do
      local h = col.hue

      pal:setColor(idx, Color{
        hue = h,
        saturation = MARKER_SATURATION / 100,
        value = 0.99,
        alpha = 255
      })
      idx = idx + 1

      for _, v in ipairs(values) do
        pal:setColor(idx, Color{
          hue = h,
          saturation = WORK_SATURATION / 100,
          value = v / 100,
          alpha = 255
        })
        idx = idx + 1
      end
    end
  end)

  app.refresh()
  local lastGray = 1 + #values
  app.alert("Palette generated!\n\n" ..
    #targetColors .. " group(s), " .. totalColors .. " colors.\n" ..
    "Idx 0=transparent, 1=black, 2-" .. lastGray .. "=gray ramp.\n\n" ..
    "Paint with the gray shades, then use\n" ..
    "PM_Toggle or PM_Toolbar to colorize.")
end

--------------------------------------------------------------
-- ADD GROUP to existing palette
--------------------------------------------------------------

local function addGroup(newColor, values)
  local spr = ensureSprite()
  if not spr then return end

  local pal = spr.palettes[1]
  local oldSize = #pal
  local rampSize = 1 + #values
  local newSize = oldSize + rampSize

  if newSize > 256 then
    app.alert("Not enough room! Palette would exceed 256 colors.")
    return
  end

  app.transaction("Add Group", function()
    pal:resize(newSize)
    local idx = oldSize
    local h = newColor.hue

    pal:setColor(idx, Color{
      hue = h,
      saturation = MARKER_SATURATION / 100,
      value = 0.99,
      alpha = 255
    })
    idx = idx + 1

    for _, v in ipairs(values) do
      pal:setColor(idx, Color{
        hue = h,
        saturation = WORK_SATURATION / 100,
        value = v / 100,
        alpha = 255
      })
      idx = idx + 1
    end
  end)

  app.refresh()
end

--------------------------------------------------------------
-- Update shades widget display
--------------------------------------------------------------

local function updateShades(dlg)
  dlg:modify{id="hueStrip", colors=hueColors}
  dlg:modify{id="status",
    text=#hueColors .. " group(s)" ..
    (selectedIdx and (" | selected: " .. selectedIdx) or "")
  }
end

--------------------------------------------------------------
-- DIALOG
--------------------------------------------------------------

local function showDialog()
  local spr = ensureSprite()
  if not spr then return end

  -- Detect existing palette structure for slider initialization and safety checks
  local pal = spr.palettes[1]
  initialStructure = detectPaletteStructure(pal)

  -- Copy arrays for working state (add/remove will mutate these, not the snapshot)
  paletteOrder = {}
  for _, c in ipairs(initialStructure.paletteOrder) do paletteOrder[#paletteOrder + 1] = c end
  hueColors = {}
  for _, c in ipairs(initialStructure.hueColors) do hueColors[#hueColors + 1] = c end
  selectedIdx = nil

  -- Initialize value settings from detected palette structure
  local initBright = 100
  local initDark = 12
  local initSteps = 8
  if initialStructure.steps > 0 then
    initSteps = initialStructure.steps
    if initialStructure.bright then initBright = initialStructure.bright end
    if initialStructure.dark then initDark = initialStructure.dark end
  end
  currentValues = computeValues(initBright, initDark, initSteps)

  local dlg = Dialog("Palette Manager")

  -- --- Color strip ---
  dlg:separator{text="TARGET COLORS"}

  dlg:shades{
    id="hueStrip",
    label="Hues",
    mode="pick",
    colors=hueColors,
    onclick=function(ev)
      -- Find which color was clicked
      for i, c in ipairs(hueColors) do
        if math.abs(c.hue - ev.color.hue) < 3 and
           math.abs(c.saturation - ev.color.saturation) < 0.05 and
           math.abs(c.value - ev.color.value) < 0.05 then
          selectedIdx = i
          dlg:modify{id="newColor", color=c}
          updateShades(dlg)
          return
        end
      end
    end
  }

  dlg:label{
    id="status",
    text=#hueColors .. " group(s)"
  }

  -- --- Add / Remove ---
  dlg:color{
    id="newColor",
    label="Add color",
    color=Color{hue=60, saturation=0.8, value=0.7, alpha=255}
  }

  dlg:button{
    id="add",
    text="Add",
    onclick=function()
      local c = dlg.data.newColor
      local rh = math.floor(c.hue + 0.5)
      for _, existing in ipairs(hueColors) do
        if math.floor(existing.hue + 0.5) == rh then
          app.alert("Hue " .. rh .. " already exists!")
          return
        end
      end
      local newCol = Color{
        hue = c.hue,
        saturation = 0.8,
        value = 0.7,
        alpha = 255
      }
      -- Append to palette order (new hues go to end, preserving existing indices)
      table.insert(paletteOrder, newCol)
      -- Insert sorted into display list
      table.insert(hueColors, newCol)
      table.sort(hueColors, function(a, b) return a.hue < b.hue end)
      selectedIdx = nil
      updateShades(dlg)
    end
  }

  dlg:button{
    id="remove",
    text="Remove selected",
    onclick=function()
      if selectedIdx and selectedIdx >= 1 and selectedIdx <= #hueColors then
        -- Find and remove from paletteOrder by matching hue
        local removedHue = math.floor(hueColors[selectedIdx].hue + 0.5)
        for j, pc in ipairs(paletteOrder) do
          if math.floor(pc.hue + 0.5) == removedHue then
            table.remove(paletteOrder, j)
            break
          end
        end
        table.remove(hueColors, selectedIdx)
        selectedIdx = nil
        updateShades(dlg)
      else
        app.alert("Click a color in the strip first to select it.")
      end
    end
  }

  -- --- Value Range ---
  dlg:separator{text="VALUE RANGE"}

  local presetNames = {}
  for _, p in ipairs(PRESETS) do
    presetNames[#presetNames + 1] = p.name
  end

  local function updatePreview()
    currentValues = computeValues(dlg.data.bright, dlg.data.dark, dlg.data.steps)
    dlg:modify{id="preview", colors=valuesToGrayColors(currentValues)}
    dlg:modify{id="previewText", text=table.concat(currentValues, " ")}
  end

  local function detectPreset()
    for i, p in ipairs(PRESETS) do
      if p.name ~= "Custom" and
         dlg.data.bright == p.bright and
         dlg.data.dark == p.dark and
         dlg.data.steps == p.steps then
        dlg:modify{id="preset", option=p.name}
        return
      end
    end
    dlg:modify{id="preset", option="Custom"}
  end

  -- Detect initial preset from slider values
  local initPreset = "Custom"
  for _, p in ipairs(PRESETS) do
    if p.name ~= "Custom" and
       initBright == p.bright and
       initDark == p.dark and
       initSteps == p.steps then
      initPreset = p.name
      break
    end
  end

  dlg:combobox{
    id="preset",
    label="Preset",
    option=initPreset,
    options=presetNames,
    onchange=function()
      local name = dlg.data.preset
      for _, p in ipairs(PRESETS) do
        if p.name == name and name ~= "Custom" then
          dlg:modify{id="bright", value=p.bright}
          dlg:modify{id="dark", value=p.dark}
          dlg:modify{id="steps", value=p.steps}
          updatePreview()
          return
        end
      end
    end
  }

  dlg:slider{
    id="bright",
    label="Bright",
    min=10,
    max=100,
    value=initBright,
    onchange=function()
      detectPreset()
      updatePreview()
    end
  }

  dlg:slider{
    id="dark",
    label="Dark",
    min=5,
    max=95,
    value=initDark,
    onchange=function()
      detectPreset()
      updatePreview()
    end
  }

  dlg:slider{
    id="steps",
    label="Steps",
    min=3,
    max=16,
    value=initSteps,
    onchange=function()
      detectPreset()
      updatePreview()
    end
  }

  dlg:shades{
    id="preview",
    label="Preview",
    mode="pick",
    colors=valuesToGrayColors(currentValues)
  }
  dlg:label{
    id="previewText",
    text=table.concat(currentValues, " ")
  }

  -- --- Actions ---
  dlg:separator{text="ACTIONS"}

  dlg:button{
    id="generate",
    text="Generate palette",
    onclick=function()
      generatePalette(paletteOrder, currentValues)
    end
  }

  dlg:button{
    id="addGroup",
    text="Add group to palette",
    onclick=function()
      if selectedIdx and selectedIdx >= 1 and selectedIdx <= #hueColors then
        addGroup(hueColors[selectedIdx], currentValues)
      elseif #hueColors > 0 then
        addGroup(hueColors[#hueColors], currentValues)
      else
        app.alert("Add at least one color first!")
      end
    end
  }

  -- --- Info ---
  dlg:separator{text="INFO"}
  dlg:label{text="Idx 0=transparent, 1=black, then gray ramp"}
  dlg:label{text="Click strip to select, then Remove"}

  dlg:show{wait=false}
end

showDialog()
