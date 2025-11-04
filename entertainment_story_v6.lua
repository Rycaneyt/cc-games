-- ===== FIXED: Theme-Menü mit eigenem Zurück-Button (Touch-sicher) =====
local function themeMenu()
  local th = theme()
  local names = {}
  for k,_ in pairs(THEMES) do table.insert(names, k) end
  table.sort(names)

  while true do
    clear(th.bg)
    drawLayout("Theme auswaehlen", "Tippe ein Theme oder < Zurueck", "")

    local x1, y1 = 3, FRAME.titleH + 1
    local x2, y2 = W - 2, H - FRAME.statusH - 1

    -- Bereich für Optionsliste (oberer Teil)
    local listTop    = y1 + 6
    local listBottom = y2 - 4  -- Platz für Zurück-Button lassen
    local backBtn    = { x1 = 3, y1 = y2 - 2, x2 = 18, y2 = y2 }  -- unten links

    -- Vorschau
    drawBox(x1, y1, x2, y1 + 4, th.frame, th.bg)
    writeCentered(y1 + 1, "Vorschau", th.titleFg, th.titleBg)
    writeCentered(y1 + 3, "Aktuell: " .. CONFIG.theme, th.fg, th.bg)

    -- Liste aufbauen/zeichnen
    local opts = {}
    for _, n in ipairs(names) do table.insert(opts, { label = n }) end

    makeButtons(x1, listTop, x2, listBottom, opts)
    drawButtons(th)

    -- Zurück-Button zeichnen
    drawBox(backBtn.x1, backBtn.y1, backBtn.x2, backBtn.y2, th.frame, th.bg)
    term.setCursorPos(backBtn.x1 + 2, backBtn.y1 + 1)
    setc(th.fg, th.bg)
    term.write("< Zurueck")

    -- Eingabe-Loop: prüfe zuerst Touch auf Zurück, dann Optionsliste
    while true do
      local e, a, b, c = os.pullEvent()
      if e == "monitor_touch" then
        local mx, my = b, c

        -- Hit-Test: Zurück
        if mx >= backBtn.x1 and mx <= backBtn.x2 and my >= backBtn.y1 and my <= backBtn.y2 then
          playSound("minecraft:block.note_block.pling", CONFIG.sfx * CONFIG.master)
          return
        end

        -- Hit-Test: Options-Buttons
        for _, bt in ipairs(buttons) do
          local x1b, y1b, x2b, y2b, label = bt[1], bt[2], bt[3], bt[4], bt[5]
          if mx >= x1b and mx <= x2b and my >= y1b and my <= y2b then
            CONFIG.theme = label
            saveConfig()
            th = theme() -- Theme sofort anwenden
            playSound("minecraft:block.note_block.pling", CONFIG.sfx * CONFIG.master)
            -- neu zeichnen mit aktualisiertem Theme
            break
          end
        end

        -- nach Touch neu zeichnen (z. B. wenn Theme geändert wurde)
        break
      elseif e == "key" then
        if a == keys.back then return end
      end
    end
  end
end

-- ===== FIXED: Textgröße-Menü mit eigenem Zurück-Button (Touch-sicher) =====
local function scaleMenu()
  local th = theme()
  local scales = { 0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0 }

  local function applyAutoScale()
    local targetW, targetH = 90, 30
    local bestS, bestDiff = 1.0, 1e9
    for s = 0.5, 3.0, 0.5 do
      mon.setTextScale(s)
      local w, h = term.getSize()
      local d = math.abs(w - targetW) + math.abs(h - targetH)
      if d < bestDiff then bestDiff, bestS = d, s end
    end
    mon.setTextScale(bestS)
    CONFIG.textScale = 0
    saveConfig()
  end

  while true do
    clear(th.bg)
    drawLayout("Textgroesse", "Tippe eine Option oder < Zurueck", "")

    local x1, y1 = 3, FRAME.titleH + 1
    local x2, y2 = W - 2, H - FRAME.statusH - 1

    local listTop    = y1 + 2
    local listBottom = y2 - 4
    local backBtn    = { x1 = 3, y1 = y2 - 2, x2 = 18, y2 = y2 }

    -- Optionen bauen: Auto + feste Stufen
    local opts = { { label = "Auto (empfohlen)" } }
    for i = 2, #scales do
      table.insert(opts, { label = ("Skalierung %.1f"):format(scales[i]) })
    end

    makeButtons(x1, listTop, x2, listBottom, opts)
    drawButtons(th)

    -- Zurück-Button
    drawBox(backBtn.x1, backBtn.y1, backBtn.x2, backBtn.y2, th.frame, th.bg)
    term.setCursorPos(backBtn.x1 + 2, backBtn.y1 + 1)
    setc(th.fg, th.bg)
    term.write("< Zurueck")

    -- Eingabe-Loop
    while true do
      local e, a, b, c = os.pullEvent()
      if e == "monitor_touch" then
        local mx, my = b, c

        -- Zurück
        if mx >= backBtn.x1 and mx <= backBtn.x2 and my >= backBtn.y1 and my <= backBtn.y2 then
          playSound("minecraft:block.note_block.pling", CONFIG.sfx * CONFIG.master)
          return
        end

        -- Options
        for idx, bt in ipairs(buttons) do
          local x1b, y1b, x2b, y2b = bt[1], bt[2], bt[3], bt[4]
          if mx >= x1b and mx <= x2b and my >= y1b and my <= y2b then
            playSound("minecraft:block.note_block.pling", CONFIG.sfx * CONFIG.master)
            if idx == 1 then
              -- Auto
              applyAutoScale()
            else
              -- feste Stufe
              local val = scales[idx]
              if type(val) == "number" then
                CONFIG.textScale = val
                mon.setTextScale(val)
                saveConfig()
              end
            end
            -- Terminalmaße aktualisieren und neu zeichnen
            W, H = term.getSize()
            th = theme()
            break
          end
        end

        break
      elseif e == "key" then
        if a == keys.back then return end
      end
    end
  end
end
