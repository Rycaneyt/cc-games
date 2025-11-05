-- fake_admin.lua
-- Dual Output (Terminal + Monitor), Touch in allen Menues, On-Screen-Keyboard, Font +/-.
-- ASCII-only. Klar beschriftete Skalierungs-Buttons. Redraw nach Scale-Wechsel.
-- CC:Tweaked / Minecraft 1.20.x

-------------------- Konfiguration --------------------
local USERNAME_DISPLAY = "Koenig Fabio"
local VERSION = "FabIO-AdminOS v2.2"
-- Start-Skalierung NUR fuer Monitor (Terminal bleibt nativ)
-- etwas kleiner als zuvor, damit rechts nichts zu gross wird:
local INITIAL_SCALE = 1.5
local MIN_SCALE, MAX_SCALE = 0.5, 5.0
local SCALE_STEP = 0.5
-------------------------------------------------------

math.randomseed(os.time())

-------------------- Dual-Output: Terminal + Monitor --------------------
local native = term.native()
local mon = nil
local ok, found = pcall(function() return peripheral.find("monitor") end)
if ok and found then
  mon = found
  pcall(function() mon.setTextScale(INITIAL_SCALE) end)
end

-- Multi-Terminal (vollstaendig, inkl. isColour)
local function makeMultiTerm(t1, t2)
  local terms = { t1 }
  if t2 then terms[2] = t2 end
  local function each(fn) for _,t in ipairs(terms) do fn(t) end end
  local api = {}
  function api.write(s)              each(function(t) t.write(s) end) end
  function api.blit(t,f,b)           each(function(x) if x.blit then x.blit(t,f,b) else x.write(t) end end) end
  function api.clear()               each(function(t) t.clear() end) end
  function api.clearLine()           each(function(t) t.clearLine() end) end
  function api.getCursorPos()        return terms[1].getCursorPos() end
  function api.setCursorPos(x,y)     each(function(t) t.setCursorPos(x,y) end) end
  function api.getCursorBlink()      return terms[1].getCursorBlink and terms[1].getCursorBlink() or false end
  function api.setCursorBlink(b)     each(function(t) if t.setCursorBlink then t.setCursorBlink(b) end end) end
  function api.getSize()
    local w1,h1 = terms[1].getSize()
    if terms[2] then
      local w2,h2 = terms[2].getSize()
      return math.min(w1,w2), math.min(h1,h2)
    end
    return w1,h1
  end
  function api.scroll(n)             each(function(t) if t.scroll then t.scroll(n) end end) end
  function api.setTextColor(c)       each(function(t) t.setTextColor(c) end) end
  function api.getTextColor()        return terms[1].getTextColor and terms[1].getTextColor() or colors.white end
  function api.setBackgroundColor(c) each(function(t) if t.setBackgroundColor then t.setBackgroundColor(c) end end) end
  function api.getBackgroundColor()  return terms[1].getBackgroundColor and terms[1].getBackgroundColor() or colors.black end
  function api.isColor()             return terms[1].isColor and terms[1].isColor() or true end
  function api.isColour()            if terms[1].isColour then return terms[1].isColour() elseif terms[1].isColor then return terms[1].isColor() else return true end end
  return api
end

local mterm = makeMultiTerm(native, mon)
term.redirect(mterm)

-------------------- Speaker (optional) --------------------
local speaker = nil
local sok, sp = pcall(function() return peripheral.find("speaker") end)
if sok and sp then speaker = sp end
local function safePlayNote(note, instrument, volume)
  if not speaker then return end
  pcall(function()
    if speaker.playNote then speaker.playNote(instrument or "harp", note or "C", volume or 1)
    elseif speaker.play then speaker.play(note or "C", volume or 1) end
  end)
end

-------------------- Zeichen-Utilities --------------------
local w,h = term.getSize()
local function resizeCache() w,h = term.getSize() end
local function centerText(y, text)
  local tw = #text
  local x = math.max(1, math.floor((w - tw) / 2) + 1)
  term.setCursorPos(x, y); term.write(text)
end
local function line(y) term.setCursorPos(1,y); term.write(string.rep("-", w)) end

-------------------- Font Scale Management --------------------
local currentScale = INITIAL_SCALE
local function applyScale()
  if mon then pcall(function() mon.setTextScale(currentScale) end) end
  resizeCache()
  -- signalisiere allen Screens, dass neu gezeichnet werden soll
  os.queueEvent("term_resize")
end
local function changeScale(delta)
  local newScale = math.max(MIN_SCALE, math.min(MAX_SCALE, currentScale + delta))
  if math.abs(newScale - currentScale) > 1e-6 then
    currentScale = newScale
    applyScale()
  end
end

-------------------- Touch areas (+ Buttons) --------------------
local touchAreas = {}
local function clearTouchAreas() touchAreas = {} end
local function addTouchArea(x1,y1,x2,y2,id,handler) table.insert(touchAreas,{x1=x1,y1=y1,x2=x2,y2=y2,id=id,handler=handler}) end
local function handleTouch(x,y)
  for _,a in ipairs(touchAreas) do
    if x>=a.x1 and x<=a.x2 and y>=a.y1 and y<=a.y2 then
      if a.handler then a.handler(a.id) end
      return a.id
    end
  end
  return nil
end

local SCALE_LABEL = "Displaygroesse einstellen: [ - ] [ + ]"
local function drawScaleLabelAndButtons()
  -- rechtsbuendig
  local x = w - #SCALE_LABEL + 1
  term.setCursorPos(x,1); term.write(SCALE_LABEL)

  -- finde Positionen von '-' und '+'
  local minusIdx = SCALE_LABEL:find("%-")   -- Index im String (1-basiert)
  local plusIdx  = SCALE_LABEL:find("%+")   -- "
  if minusIdx then
    local mx = x + minusIdx - 1
    addTouchArea(mx-1, 1, mx+1, 1, "font_minus", function() changeScale(-SCALE_STEP) end)
  end
  if plusIdx then
    local px = x + plusIdx - 1
    addTouchArea(px-1, 1, px+1, 1, "font_plus",  function() changeScale(SCALE_STEP)  end)
  end
end

local function clearAndHeader(showButtons)
  term.clear(); term.setCursorPos(1,1)
  term.setTextColor(colors.white); centerText(1, VERSION)
  term.setTextColor(colors.gray);  line(2)
  term.setTextColor(colors.white)
  if showButtons then drawScaleLabelAndButtons() end
end

-------------------- Logs --------------------
local logs = {}
local function addLog(line)
  local t = os.date("[%Y-%m-%d %H:%M:%S]")
  table.insert(logs, 1, t .. " " .. line)
  if #logs > 300 then for i=301,#logs do logs[i]=nil end end
end

-- Seed
addLog("[INFO] System gestartet. Willkommen, " .. USERNAME_DISPLAY .. "!")
addLog("[SEC] Biometrische Auth nicht gefunden. Fallback: Humor.")
addLog("[LOG] Fabio lachte 3x laut waehrend einer Systemwartung.")
addLog("[LOG] Backup: letzte Sicherung vor " .. math.random(1,72) .. " Stunden.")
addLog("[INFO] Netzwerkstatus: Verbunden (lokal).")

-------------------- AI Assistent --------------------
local function aiSpeak(lines, delay)
  delay = delay or 0.7
  for _,ln in ipairs(lines) do
    term.setTextColor(colors.yellow); print("> AI: " .. ln)
    term.setTextColor(colors.white);  safePlayNote("C","harp",0.5); sleep(delay)
  end
end

-------------------- Event-Helper --------------------
local function waitKeyOrTouch()
  while true do
    local ev,p1,p2,p3 = os.pullEvent()
    if ev == "char" or ev == "key" then return ev,p1 end
    if ev == "monitor_touch" and mon and p1 == peripheral.getName(mon) then return ev,p2,p3 end
    if ev == "term_resize" then
      resizeCache()
      -- gib das Event an den Aufrufer zurueck, damit er neu zeichnen kann
      return ev
    end
  end
end

-------------------- Keyboard + Eingabe --------------------
local KB_ROWS = { "1234567890","qwertzuiop","asdfghjkl","< yxcvbnm  >" }
local function drawKeyboard(yStart)
  local xStart = 3
  for r,row in ipairs(KB_ROWS) do
    term.setCursorPos(xStart, yStart + r - 1)
    term.setTextColor(colors.lightGray)
    local x = xStart
    for i=1,#row do
      local ch = row:sub(i,i)
      local disp = (ch=="<" and "[Bksp]") or (ch==">" and "[Enter]") or ch
      term.setCursorPos(x, yStart + r - 1); term.write(disp)
      addTouchArea(x, yStart + r - 1, x + (#disp-1), yStart + r - 1, "kb_"..r.."_"..i, function() end)
      x = x + #disp + 1
    end
  end
  term.setTextColor(colors.white)
end
local function keyboardHitToChar(x,y, yStart)
  local xStart = 3
  for r,row in ipairs(KB_ROWS) do
    local yy = yStart + r - 1
    local xx = xStart
    for i=1,#row do
      local ch = row:sub(i,i)
      local disp = (ch=="<" and "[Bksp]") or (ch==">" and "[Enter]") or ch
      local x1,x2 = xx, xx + (#disp-1)
      if y == yy and x >= x1 and x <= x2 then
        if ch == "<" then return "BKSP"
        elseif ch == ">" then return "ENTER"
        elseif ch == " " then return "SPACE"
        else return ch end
      end
      xx = xx + #disp + 1
    end
  end
  return nil
end

local function readLineTouch(promptX, promptY, masked)
  masked = masked or false
  local buf = ""
  term.setCursorPos(promptX, promptY); term.setCursorBlink(true)
  local kbY = promptY + 2
  drawKeyboard(kbY); drawScaleLabelAndButtons()
  while true do
    term.setCursorPos(promptX, promptY); term.clearLine()
    term.write(masked and string.rep("*", #buf) or buf)
    local ev,a,b = waitKeyOrTouch()
    if ev == "char" then
      if a == "+" then changeScale(SCALE_STEP)
      elseif a == "-" then changeScale(-SCALE_STEP)
      else buf = buf .. a end
    elseif ev == "key" then
      if a == keys.enter then term.setCursorBlink(false); return buf
      elseif a == keys.backspace then buf = buf:sub(1,#buf-1)
      elseif a == keys.space then buf = buf .. " "
      elseif a == keys.minus or a == keys.numPadSubtract then changeScale(-SCALE_STEP)
      elseif a == keys.equals or a == keys.numPadAdd then changeScale(SCALE_STEP) end
    elseif ev == "monitor_touch" then
      local id = handleTouch(a,b)
      if id ~= "font_minus" and id ~= "font_plus" then
        local key = keyboardHitToChar(a,b,kbY)
        if key == "BKSP" then buf = buf:sub(1,#buf-1)
        elseif key == "ENTER" then term.setCursorBlink(false); return buf
        elseif key == "SPACE" then buf = buf .. " "
        elseif key then buf = buf .. key end
      end
    elseif ev == "term_resize" then
      -- Bildschirm neu zeichnen nach Scale-Wechsel
      clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
      term.setCursorPos(1, promptY-2); print("")
      drawKeyboard(kbY); drawScaleLabelAndButtons()
    end
  end
end

-------------------- Mini-Utils --------------------
local function loadingDots(x, y, duration)
  duration = duration or 1.2
  local start = os.clock(); local i = 0
  while os.clock() - start < duration do
    local dots = string.rep(".", (i % 4))
    term.setCursorPos(x,y); term.write(dots .. string.rep(" ", 4 - #dots))
    sleep(0.2); i = i + 1
  end
end
local function boolMark(ok) return ok and "OK " or "FAIL" end

-------------------- Login-Status-Panel --------------------
local function drawLoginStatusPanel(topY)
  local col1 = 4
  local col2 = math.floor(w/2) + 2
  local computerID = os.getComputerID()
  local label = os.getComputerLabel() or "(kein Label)"
  local modem = peripheral.find("modem") ~= nil
  local gpsX,gpsY,gpsZ = nil,nil,nil
  pcall(function() gpsX,gpsY,gpsZ = gps.locate(0.5) end)
  local fakeIP = string.format("10.%d.%d.%d", math.random(0,255), math.random(0,255), math.random(1,254))
  local timeStr = textutils and textutils.formatTime and textutils.formatTime(os.time(), true) or tostring(os.clock())

  term.setCursorPos(col1, topY+0); term.write("== System ==")
  term.setCursorPos(col1, topY+1); term.write("Computer-ID: " .. tostring(computerID))
  term.setCursorPos(col1, topY+2); term.write("Label:       " .. label)
  term.setCursorPos(col1, topY+3); term.write("Uhrzeit:     " .. timeStr)
  term.setCursorPos(col1, topY+4); term.write("Speaker:     " .. boolMark(speaker ~= nil))

  term.setCursorPos(col2, topY+0); term.write("== Netzwerk ==")
  term.setCursorPos(col2, topY+1); term.write("Modem:       " .. boolMark(modem))
  term.setCursorPos(col2, topY+2); term.write("GPS:         " .. (gpsX and ("X="..gpsX.." Y="..gpsY.." Z="..gpsZ) or "nicht verfuegbar"))
  term.setCursorPos(col2, topY+3); term.write("Fake-IP:     " .. fakeIP)
  term.setCursorPos(col2, topY+4); term.write("Ping Mojang: " .. (math.random(1,10) <= 8 and "12ms" or "timeout"))
  term.setCursorPos(col2, topY+5); term.write("Threat Lvl:  " .. ({"gruen","gelb","orange","rot"})[math.random(1,4)])

  term.setCursorPos(col1, topY+6); term.write("== Scanner ==")
  term.setCursorPos(col1, topY+7); term.write("Memes gefunden: " .. math.random(3,99))
  term.setCursorPos(col1, topY+8); term.write("Ego-Level:      " .. math.random(5000,9000))
  term.setCursorPos(col1, topY+9); term.write("Kuh Lucy Status: freundlich")

  term.setCursorPos(col2, topY+6); term.write("== Sicherheit ==")
  term.setCursorPos(col2, topY+7); term.write("Firewall:        " .. boolMark(true))
  term.setCursorPos(col2, topY+8); term.write("Passwortstaerke: ueberschaetzt")
  term.setCursorPos(col2, topY+9); term.write("Admin-Charisma:  kritisch niedrig")
end

-------------------- Aktionen (gleich wie zuvor, leicht gekuerzt) --------------------
local function explosionAnimation()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "WARNUNG: Selbstzerstoerungs-Protokoll wird initialisiert")
  term.setTextColor(colors.red)
  for _,note in ipairs({"5","4","3","2","1"}) do
    centerText(6, note); safePlayNote("C","bass",1); sleep(0.6)
  end
  term.setTextColor(colors.magenta); centerText(8, "BOOOM! ... oder auch nicht. :)")
  safePlayNote("C","pling",1); sleep(1.2); term.setTextColor(colors.white)
  addLog("[ACTION] Versuch Selbstzerstoerung (Simuliert).")
end

local function hackMojangAnimation()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Infiltriere Mojang-Netzwerk ...")
  local barY = 6; term.setCursorPos(4,barY); term.write("["); term.setCursorPos(w-3,barY); term.write("]")
  for i=1,(w-10) do
    term.setCursorPos(5+i, barY); term.setTextColor((i%2==0) and colors.green or colors.lightBlue)
    term.write("="); if i%4==0 then safePlayNote("C","harp",0.6) end; sleep(0.03)
  end
  term.setTextColor(colors.white); centerText(8, "Zugriff: ERLAUBT (fake).")
  addLog("[SEC] Mojang breach: nur Katzenvideos.")
  sleep(1)
end

local function fabioDance()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, USERNAME_DISPLAY .. " geheime Tanzroutine wird aktiviert ...")
  aiSpeak({"Grossartige Wahl! Lade move_set: FABIO_FUNK_2025 ..."}, 0.6)
  local frames = { "\\o/  _  \\o/", "_\\o ( ) o/_", " /|  / \\  |\\", "\\o/  ^  \\o/" }
  for r=1,6 do for i,fr in ipairs(frames) do
    term.setCursorPos(1,10); term.clearLine(); centerText(10, fr .. "  (star)")
    safePlayNote("C","harp",0.5 + 0.05*i); sleep(0.25) end end
  term.setTextColor(colors.cyan); centerText(12, "Tanzroutine abgeschlossen. Publikum: 1 (du).")
  addLog("[FUN] Fabio tanzte 17 Sekunden. Zustimmung 100%.")
  term.setTextColor(colors.white); sleep(1)
end

local function sillyOptions()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Ausgewaehlte Scherze und Aktionen:")
  local baseY = 6
  local items = {
    "Aktivieren: Keks-Regel (alle keksbasierenden Aktionen verboten).",
    "Upgrade Ego (Ego +9000, temporaer).",
    "Deploy Dancefloor (Lichtshow, unsichtbar).",
    "Send Fabio a compliment (automatisch).",
  }
  for i,v in ipairs(items) do
    term.setCursorPos(4, baseY + i - 1); term.write(i .. ") " .. v)
    addTouchArea(1, baseY + i - 1, w, baseY + i - 1, "silly_"..i, function() end)
  end
  addLog("[INFO] Benutzer schaute sich lustige Optionen an.")
  term.setCursorPos(2, baseY + #items + 2); term.write("Tippe/Enter zum Zurueckkehren.")
  while true do
    local ev,a,b = waitKeyOrTouch()
    if ev == "key" and a == keys.enter then return end
    if ev == "monitor_touch" then local id = handleTouch(a,b); if id then return end end
    if ev == "char" and (a == '+' or a == '-') then changeScale(a=='+' and SCALE_STEP or -SCALE_STEP) end
    if ev == "term_resize" then clearTouchAreas(); return sillyOptions() end
  end
end

local function fakeRestart()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "System wird neu gestartet ...")
  for i=1,3 do centerText(6, "Neustart in " .. (4 - i) .. " ..."); safePlayNote("C","bass",0.8); sleep(0.8) end
  term.clear(); centerText(6, "Start erfolgreich. Alles wie vorher.")
  addLog("[INFO] System Neustart (fake)."); sleep(1)
end

local function corruptFiles()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Dateisystem-Scan ...")
  for i=1,w-10 do term.setCursorPos(5+i, 8); term.write(string.char(33 + (i % 60))); sleep(0.005) end
  centerText(10, "FEHLER: Keine peinlichen Dateien gefunden. Glueck gehabt!")
  addLog("[WARN] Scan peinliche Dateien: 0/0 (fehlerhaft)."); sleep(1.2)
end

-------------------- Logs --------------------
local function showLogs()
  local pos = 1
  while true do
    clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
    centerText(4, "SYSTEM LOGS (neueste oben)")
    local maxLines = h - 9
    local baseY = 6
    for i=1,maxLines do
      local idx = pos + i - 1
      term.setCursorPos(2, baseY + i - 1); term.clearLine()
      if logs[idx] then
        term.setTextColor(colors.white)
        local text = logs[idx]; if #text > w-4 then text = text:sub(1, w-7).."..." end
        term.write(text)
      end
    end
    term.setTextColor(colors.gray)
    term.setCursorPos(2, baseY + maxLines + 1); term.write("Pfeile scrollen, Enter zurueck, +/- Schriftgroesse")
    term.setTextColor(colors.white)
    addTouchArea(1, baseY, w, baseY, "scroll_up", function() pos = math.max(1, pos-1) end)
    addTouchArea(1, baseY + maxLines, w, baseY + maxLines, "scroll_down", function()
      pos = math.min(math.max(1, #logs - maxLines + 1), pos+1)
    end)

    local ev,a,b = waitKeyOrTouch()
    if ev == "key" then
      if a == keys.up then pos = math.max(1, pos-1)
      elseif a == keys.down then pos = math.min(math.max(1, #logs - maxLines + 1), pos+1)
      elseif a == keys.enter then return
      elseif a == keys.minus or a == keys.numPadSubtract then changeScale(-SCALE_STEP)
      elseif a == keys.equals or a == keys.numPadAdd then changeScale(SCALE_STEP) end
    elseif ev == "char" then
      if a == '+' then changeScale(SCALE_STEP) elseif a == '-' then changeScale(-SCALE_STEP) end
    elseif ev == "monitor_touch" then
      handleTouch(a,b)
    elseif ev == "term_resize" then
      -- einfach neu zeichnen
    end
  end
end

-------------------- Menue --------------------
local function menuSelect(yFirst, count)
  while true do
    local ev,a,b = waitKeyOrTouch()
    if ev == "char" then
      if a >= '0' and a <= '9' then return a end
      if a == '+' then changeScale(SCALE_STEP)
      elseif a == '-' then changeScale(-SCALE_STEP) end
    elseif ev == "key" then
      if a == keys.enter then return "\n" end
      if a == keys.equals or a == keys.numPadAdd then changeScale(SCALE_STEP)
      elseif a == keys.minus or a == keys.numPadSubtract then changeScale(-SCALE_STEP) end
    elseif ev == "monitor_touch" then
      local id = handleTouch(a,b)
      if id ~= "font_minus" and id ~= "font_plus" then
        for i=1,count do if b == yFirst + (i-1) then return tostring(i) end end
      end
    elseif ev == "term_resize" then
      -- redraw durch aussenliegende Schleife
    end
  end
end

local function mainMenu()
  while true do
    resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
    centerText(4, "== Super-Geheimes Admin-Interface ==")
    local baseY = 6
    local entries = {
      "Server Selbstzerstoerung aktivieren",
      "Hacke das Mojang-Netzwerk",
      "Aktiviere " .. USERNAME_DISPLAY .. " geheime Tanzroutine",
      "Zeige Logs",
      "Lustige Optionen anschauen",
      "System Neustart",
      "Scan nach peinlichen Dateien",
      "Beenden"
    }
    for i,v in ipairs(entries) do
      term.setCursorPos(4, baseY + i - 1); term.write(i%8==0 and "0) "..v or (i..") "..v))
      addTouchArea(1, baseY + i - 1, w, baseY + i - 1, "menu_"..i, function() end)
    end
    term.setCursorPos(4, baseY + #entries + 2)
    term.write("Zahl eingeben oder tippen. [+/-] Schriftgroesse")

    local sel = menuSelect(baseY, #entries)
    addLog("[UI] Auswahl: " .. tostring(sel))
    if sel == "1" then explosionAnimation()
    elseif sel == "2" then hackMojangAnimation()
    elseif sel == "3" then fabioDance()
    elseif sel == "4" then showLogs()
    elseif sel == "5" then sillyOptions()
    elseif sel == "6" then fakeRestart()
    elseif sel == "7" then corruptFiles()
    elseif sel == "8" or sel == "0" then
      addLog("[INFO] Programm beendet.")
      clearAndHeader(true); drawScaleLabelAndButtons()
      centerText(6, "Auf Wiedersehen, " .. USERNAME_DISPLAY .. "!")
      safePlayNote("C","pling",0.8); sleep(1); term.clear(); return
    end
  end
end

-------------------- Login (Status-Panel + klare Felder) --------------------
local function drawLoginStatusPanel(topY)  -- (Definiert oben schon; hier nur Doppeldeklaration verhindern)
end
-- (redefiniere sauber: oben war die echte Implementierung)

local function realDrawLoginStatusPanel(topY) -- Alias
  -- benutze die oben definierte Implementierung
  _G._loginStatusImpl(topY)
end
_G._loginStatusImpl = nil

-- setze Alias korrekt:
_G._loginStatusImpl = function(topY)
  -- call the real implementation we defined earlier
  -- (Lua closure already captured it)
end

-- Wir nutzen direkt die oben definierte Funktion (keine Alias-Spielchen noetig in dieser Version)
-- Ich belasse die vorige Implementierung aktiv.

local function login()
  resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  term.setTextColor(colors.lightBlue); centerText(3, "== SECURE ADMIN ACCESS ==")
  term.setTextColor(colors.white)
  centerText(4, "Nur Admins duerfen fortfahren. (Oder alle, pssst)")

  drawLoginStatusPanel(6)

  local yForm = 17
  if yForm + 7 > h then yForm = h - 7 end
  term.setCursorPos(4, yForm);     term.write("Name:     ")
  local user = readLineTouch(15, yForm, false)
  term.setCursorPos(4, yForm+1);   term.write("Passwort: ")
  local pass = readLineTouch(15, yForm+1, true)

  loadingDots(4 + 18, yForm+3, 1.4)
  term.setCursorPos(4, yForm+3); term.setTextColor(colors.green)
  print("Zugriff gewaehrt. Willkommen, " .. USERNAME_DISPLAY .. "!")
  term.setTextColor(colors.white)
  addLog("[AUTH] Anmeldung von '" .. tostring(user) .. "' erfolgreich (Auth: Humor).")
  aiSpeak({
    "Hallo " .. USERNAME_DISPLAY .. "! Alles bereit.",
    "Ich bin dein freundlicher aber voellig ernster Admin-Assistent.",
    "Hinweis: Admin-Charisma noch immer niedrig. Bitte laecheln."
  }, 0.7)
  sleep(0.6)
end

-------------------- Start --------------------
local function start()
  resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(3, "Willkommen zur Entertainment Station")
  centerText(5, "Starte das geheime Admin-Programm? (Enter oder Tippen)")

  while true do
    local ev,a,b = waitKeyOrTouch()
    if ev == "key" and a == keys.enter then break end
    if ev == "monitor_touch" then local id = handleTouch(a,b); if id ~= "font_minus" and id ~= "font_plus" then break end end
    if ev == "char" then if a == '+' then changeScale(SCALE_STEP) elseif a == '-' then changeScale(-SCALE_STEP) else break end end
    if ev == "term_resize" then -- redraw
      clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
      centerText(3, "Willkommen zur Entertainment Station")
      centerText(5, "Starte das geheime Admin-Programm? (Enter oder Tippen)")
    end
  end

  login()
  mainMenu()
end

-------------------- Run --------------------
start()
