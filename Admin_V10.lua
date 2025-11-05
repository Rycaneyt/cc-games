-- Admin v3.0  (FabIO-AdminOS)
-- Dual Output (Terminal + Monitor), Touch-UI, On-Screen-Keyboard, Skala +/-,
-- Logs mit Zurueck-Button, Dienstprogramme mit Aktionen, Dateisystem-Scan,
-- Selbstzerstoerungs-(Spass)modus, seriöser Ton mit kleinen Gags.
-- CC:Tweaked / MC 1.20.x  |  ASCII-only

-------------------- Konfiguration --------------------
local USERNAME_DISPLAY   = "Koenig Fabio"
local VERSION            = "FabIO-AdminOS v3.0"
-- Monitor-Startskalierung (Terminal bleibt nativ)
local INITIAL_SCALE      = 1.5
local MIN_SCALE, MAX_SCALE = 0.5, 5.0
local SCALE_STEP         = 0.5

-- Login-Timing
local LOGIN_STATUS_AUTOSECONDS = 5
local LOGIN_STEP_DELAY   = 0.7
local POST_LOGIN_DWELL   = 2.8

-- (kleiner Easter: Sonderbegriffe für besondere Begrüßung)
local HONORIFY = {
  ["fabio"] = "Seine Exzellenz, Meister der Knöpfe",
  ["admin"] = "Hüter der Systeme",
  ["root"]  = "Allmaechtiger Root (mit Verantwortung)"
}

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

local function makeMultiTerm(t1, t2)
  local terms = { t1 }; if t2 then terms[2] = t2 end
  local function each(fn) for _,t in ipairs(terms) do fn(t) end end
  local api = {}

  -- Kern-API
  function api.write(s)              each(function(t) t.write(s) end) end
  function api.blit(t,f,b)           each(function(x) if x.blit then x.blit(t,f,b) else x.write(t) end end) end
  function api.clear()               each(function(t) t.clear() end) end
  function api.clearLine()           each(function(t) t.clearLine() end) end
  function api.getCursorPos()        return terms[1].getCursorPos() end
  function api.setCursorPos(x,y)     each(function(t) t.setCursorPos(x,y) end) end
  function api.getCursorBlink()      return terms[1].getCursorBlink and terms[1].getCursorBlink() or false end
  function api.setCursorBlink(b)     each(function(t) if t.setCursorBlink then t.setCursorBlink(b) end end) end
  function api.getSize()
    local w1,h1=terms[1].getSize()
    if terms[2] then local w2,h2=terms[2].getSize(); return math.min(w1,w2), math.min(h1,h2) end
    return w1,h1
  end
  function api.scroll(n)             each(function(t) if t.scroll then t.scroll(n) end end) end

  -- Farben (US)
  function api.setTextColor(c)       each(function(t) t.setTextColor(c) end) end
  function api.getTextColor()        return terms[1].getTextColor and terms[1].getTextColor() or colors.white end
  function api.setBackgroundColor(c) each(function(t) if t.setBackgroundColor then t.setBackgroundColor(c) end end) end
  function api.getBackgroundColor()  return terms[1].getBackgroundColor and terms[1].getBackgroundColor() or colors.black end
  function api.isColor()             return terms[1].isColor and terms[1].isColor() or true end
  function api.isColour()            if terms[1].isColour then return terms[1].isColour() elseif terms[1].isColor then return terms[1].isColor() else return true end end

  -- Farben (UK) – Aliase fuer BIOS/alte APIs
  function api.setTextColour(c)       api.setTextColor(c) end
  function api.getTextColour()        return api.getTextColor() end
  function api.setBackgroundColour(c) api.setBackgroundColor(c) end
  function api.getBackgroundColour()  return api.getBackgroundColor() end

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

-------------------- Zeichen/Screen-Utils --------------------
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
  resizeCache(); os.queueEvent("term_resize")
end
local function changeScale(delta)
  local ns = math.max(MIN_SCALE, math.min(MAX_SCALE, currentScale + delta))
  if math.abs(ns - currentScale) > 1e-6 then currentScale = ns; applyScale() end
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
  local x = w - #SCALE_LABEL + 1
  term.setCursorPos(x,1); term.write(SCALE_LABEL)
  local minusIdx = SCALE_LABEL:find("%-"); local plusIdx = SCALE_LABEL:find("%+")
  if minusIdx then local mx=x+minusIdx-1; addTouchArea(mx-1,1,mx+1,1,"font_minus",function() changeScale(-SCALE_STEP) end) end
  if plusIdx then  local px=x+plusIdx-1;  addTouchArea(px-1,1,px+1,1,"font_plus", function() changeScale( SCALE_STEP) end) end
end

local function clearAndHeader(showButtons)
  term.clear(); term.setCursorPos(1,1)
  term.setTextColor(colors.white); centerText(1, VERSION)
  term.setTextColor(colors.gray);  line(2)
  term.setTextColor(colors.white); if showButtons then drawScaleLabelAndButtons() end
end

-------------------- Logs --------------------
local logs = {}
local function addLog(line)
  local t = os.date("[%Y-%m-%d %H:%M:%S]")
  table.insert(logs, 1, t.." "..line)
  if #logs > 300 then for i=301,#logs do logs[i]=nil end end
end
addLog("[INFO] System start abgeschlossen.")
addLog("[INFO] Audit-Stream aktiv.")
addLog("[INFO] Netzwerkstatus: verbunden (lokal).")

-------------------- Systemmeldungen (dezent) --------------------
local function aiSpeak(lines, delay)
  delay = delay or 0.7
  for _,ln in ipairs(lines) do
    term.setTextColor(colors.yellow); print("> System: "..ln)
    term.setTextColor(colors.white); safePlayNote("C","harp",0.4); sleep(delay)
  end
end

-------------------- Events --------------------
local function waitKeyOrTouch()
  while true do
    local ev,p1,p2,p3 = os.pullEvent()
    if ev=="char" or ev=="key" then return ev,p1 end
    if ev=="monitor_touch" and mon and p1==peripheral.getName(mon) then return ev,p2,p3 end
    if ev=="term_resize" then resizeCache(); return ev end
  end
end

-------------------- On-Screen-Keyboard --------------------
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
local function clearKeyboardArea(yStart)
  for r=0,3 do term.setCursorPos(1, yStart+r); term.clearLine() end
  clearTouchAreas() -- Keyboard-Hitboxen weg; Header/Buttons danach neu zeichnen
end
local function keyboardHitToChar(x,y,yStart)
  local xStart=3
  for r,row in ipairs(KB_ROWS) do
    local yy=yStart+r-1; local xx=xStart
    for i=1,#row do
      local ch=row:sub(i,i); local disp=(ch=="<" and "[Bksp]") or (ch==">" and "[Enter]") or ch
      local x1,x2=xx,xx+(#disp-1)
      if y==yy and x>=x1 and x<=x2 then
        if ch=="<" then return "BKSP"
        elseif ch==">" then return "ENTER"
        elseif ch==" " then return "SPACE"
        else return ch end
      end
      xx=xx+#disp+1
    end
  end
  return nil
end
local function readLineTouch(promptX,promptY,masked)
  masked = masked or false
  local buf=""; term.setCursorPos(promptX,promptY); term.setCursorBlink(true)
  local kbY = promptY+2; drawKeyboard(kbY); drawScaleLabelAndButtons()
  while true do
    term.setCursorPos(promptX,promptY); term.clearLine()
    term.write(masked and string.rep("*",#buf) or buf)
    local ev,a,b = waitKeyOrTouch()
    if ev=="char" then
      if a=="+" then changeScale(SCALE_STEP)
      elseif a=="-" then changeScale(-SCALE_STEP)
      else buf = buf .. a end
    elseif ev=="key" then
      if a==keys.enter then term.setCursorBlink(false); return buf, kbY
      elseif a==keys.backspace then buf = buf:sub(1,#buf-1)
      elseif a==keys.space then buf = buf.." "
      elseif a==keys.minus or a==keys.numPadSubtract then changeScale(-SCALE_STEP)
      elseif a==keys.equals or a==keys.numPadAdd then changeScale(SCALE_STEP) end
    elseif ev=="monitor_touch" then
      local id=handleTouch(a,b)
      if id~="font_minus" and id~="font_plus" then
        local key = keyboardHitToChar(a,b,kbY)
        if key=="BKSP" then buf=buf:sub(1,#buf-1)
        elseif key=="ENTER" then term.setCursorBlink(false); return buf, kbY
        elseif key=="SPACE" then buf=buf.." "
        elseif key then buf=buf..key end
      end
    elseif ev=="term_resize" then
      clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
      term.setCursorPos(1,promptY-2); print(""); drawKeyboard(kbY); drawScaleLabelAndButtons()
    end
  end
end

-------------------- Mini-Utils --------------------
local function loadingDots(x,y,dur)
  dur=dur or 1.2; local s=os.clock(); local i=0
  while os.clock()-s<dur do
    local dots=string.rep(".", (i%4))
    term.setCursorPos(x,y); term.write(dots..string.rep(" ",4-#dots))
    sleep(0.2); i=i+1
  end
end
local function boolMark(ok) return ok and "OK " or "FAIL" end

-------------------- Login-Status-Panel --------------------
local function drawLoginStatusPanel(topY)
  local col1=4; local col2=math.floor(w/2)+2
  local computerID=os.getComputerID(); local label=os.getComputerLabel() or "(kein Label)"
  local modem=peripheral.find("modem")~=nil
  local gx,gy,gz=nil,nil,nil; pcall(function() gx,gy,gz=gps.locate(0.5) end)
  local ip=string.format("10.%d.%d.%d", math.random(0,255), math.random(0,255), math.random(1,254))
  local timeStr=textutils and textutils.formatTime and textutils.formatTime(os.time(), true) or tostring(os.clock())

  term.setCursorPos(col1,topY+0); term.write("== System ==")
  term.setCursorPos(col1,topY+1); term.write("Computer-ID: "..tostring(computerID))
  term.setCursorPos(col1,topY+2); term.write("Label:       "..label)
  term.setCursorPos(col1,topY+3); term.write("Uhrzeit:     "..timeStr)
  term.setCursorPos(col1,topY+4); term.write("Speaker:     "..boolMark(speaker~=nil))

  term.setCursorPos(col2,topY+0); term.write("== Netzwerk ==")
  term.setCursorPos(col2,topY+1); term.write("Modem:       "..boolMark(modem))
  term.setCursorPos(col2,topY+2); term.write("GPS:         "..(gx and ("X="..gx.." Y="..gy.." Z="..gz) or "nicht verfuegbar"))
  term.setCursorPos(col2,topY+3); term.write("IP:          "..ip)
  term.setCursorPos(col2,topY+4); term.write("Ping:        "..(math.random(1,10)<=8 and "12ms" or "timeout"))
  term.setCursorPos(col2,topY+5); term.write("Threat Lvl:  "..({"gruen","gelb","orange","rot"})[math.random(1,4)])

  term.setCursorPos(col1,topY+6); term.write("== Scanner ==")
  term.setCursorPos(col1,topY+7); term.write("Assets:      "..math.random(120,980))
  term.setCursorPos(col1,topY+8); term.write("ACL-Cache:   warm")
  term.setCursorPos(col1,topY+9); term.write("Audit:       aktiv")
end

-------------------- Dialog-Helfer --------------------
local function pressToContinueRobust(y)
  local label="[ OK ]"
  centerText(y, label)
  local x = math.floor((w - #label)/2)+1
  addTouchArea(x, y, x + #label - 1, y, "dlg_ok", function() end)
  while true do
    local ev,p1,p2,p3 = os.pullEvent()
    if ev=="key" and p1==keys.enter then return end
    if ev=="monitor_touch" then
      local id = handleTouch(p2,p3)
      if id=="dlg_ok" then return end
    end
  end
end

local function confirmDialog(title, message)
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, title)
  term.setCursorPos(3,6); print(message)
  local okLabel    = "[ OK ]"
  local cancelLabel= "[ Abbrechen ]"
  local okX        = math.floor(w/2) - #okLabel - 2
  local cancelX    = math.floor(w/2) + 2
  local y          = h-3
  term.setCursorPos(okX, y);     term.write(okLabel)
  term.setCursorPos(cancelX, y); term.write(cancelLabel)
  addTouchArea(okX, y, okX+#okLabel-1, y, "dlg_ok", function() end)
  addTouchArea(cancelX, y, cancelX+#cancelLabel-1, y, "dlg_cancel", function() end)
  while true do
    local ev,p1,p2,p3 = os.pullEvent()
    if ev=="key" and p1==keys.enter then return true end
    if ev=="key" and (p1==keys.backspace or p1==keys.escape) then return false end
    if ev=="monitor_touch" then
      local id = handleTouch(p2,p3)
      if id=="dlg_ok" then return true end
      if id=="dlg_cancel" then return false end
    end
  end
end

-------------------- Aktionen --------------------
local function selfDestructMode()
  local ok = confirmDialog("Sicherheitsprotokoll 7B", "Kritischen Vorgang vorbereiten?")
  if not ok then return end
  ok = confirmDialog("Bestaetigung erforderlich", "Bitte bestaetigen: Vorbereitungen fortsetzen.")
  if not ok then return end

  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Sicherheitsprotokoll 7B: Aktiv")
  term.setCursorPos(3,6); print("- Sperre Schreibrechte ... OK")
  term.setCursorPos(3,7); print("- Synchronisiere Audit-Stream ... OK")
  term.setCursorPos(3,8); print("- Arbitriere Quorumschluessel ... OK")
  term.setCursorPos(3,9); print("- Starte Countdown")
  for i=5,1,-1 do centerText(11, ("T-"..i)); safePlayNote("C","bass",1); sleep(0.75) end
  term.setCursorPos(3,13); print("- Archiv markiert ..."); loadingDots(25,13,0.7)
  term.setCursorPos(3,14); print("- Systeme in ReadOnly ... OK")
  term.setCursorPos(3,15); print("- Endpunkt erreichbar ... OK")
  sleep(0.6)
  term.setTextColor(colors.magenta); centerText(17, "Richtlinie greift: Ausfuehrung blockiert."); term.setTextColor(colors.white)
  addLog("[ACTION] Selbstzerstoerung angefragt; durch Richtlinie blockiert.")
  sleep(1.0); centerText(19, "Anmerkung: Kaffeemaschine wurde vorsorglich beruhigt.")
  pressToContinueRobust(h-2)
end

local function hackMojangAnimation()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Initialisiere Remote-Diagnose ...")
  local y=6; term.setCursorPos(4,y); term.write("["); term.setCursorPos(w-3,y); term.write("]")
  for i=1,(w-10) do
    term.setCursorPos(5+i,y)
    term.setTextColor((i%2==0) and colors.green or colors.lightBlue)
    term.write("="); if i%4==0 then safePlayNote("C","harp",0.4) end; sleep(0.03)
  end
  term.setTextColor(colors.white); centerText(8, "Remote-Zugriff limitiert. Diagnosedaten aktualisiert.")
  addLog("[SEC] Externe Diagnose ausgefuehrt (anonymisiert).")
  sleep(1.0); centerText(10, "Zusatz: Kein Creeper-Verkehr festgestellt."); sleep(0.9)
end

local function interaktiveTanzroutine()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Lade interaktives Modul ...")
  aiSpeak({"Modul initialisiert.","Animationstest vorgesehen."}, 0.6)
  local frames={"\\o/  _  \\o/","_\\o ( ) o/_"," /|  / \\  |\\","\\o/  ^  \\o/"}
  for r=1,6 do for i,fr in ipairs(frames) do
    term.setCursorPos(1,10); term.clearLine(); centerText(10, fr)
    safePlayNote("C","harp",0.4+0.04*i); sleep(0.25)
  end end
  term.setTextColor(colors.cyan); centerText(12, "Modultest beendet.")
  term.setTextColor(colors.white); addLog("[INFO] Interaktives Modultest-Pattern gespielt."); sleep(1.0)
  centerText(14, "Notiz: Publikum zaehlbar auf einer Hand."); sleep(0.8)
end

local function fileSystemScan()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4, "Dateisystem-Scan")
  term.setCursorPos(3,6); print("- Indiziere Verzeichnisse ..."); loadingDots(34,6,0.8)

  local scanned, flagged, total = 0, 0, 0
  local function walk(path, depth)
    depth = depth or 0
    local ok, list = pcall(fs.list, path)
    if not ok or not list then return end
    for _,name in ipairs(list) do
      local p = (path=="/" and "" or path.."/")..name
      total = total + 1
      if fs.isDir(p) then
        if depth < 3 then walk(p, depth+1) end
      else
        scanned = scanned + 1
        if (scanned % 17) == 0 then flagged = flagged + 1 end
        if (scanned % 25) == 0 then sleep(0) end
      end
      if (total % 20) == 0 then
        term.setCursorPos(3,7); term.clearLine()
        term.write(string.format("- Fortschritt: %d Dateien, %d markiert", scanned, flagged))
      end
    end
  end
  pcall(function() walk("/") end)

  term.setCursorPos(3,8); print("- Integritaet pruefen ..."); loadingDots(34,8,0.9)
  term.setCursorPos(3,9); print("- ACL Quercheck ... OK")
  term.setCursorPos(3,10); print("- Audit Sync ... OK")
  addLog(string.format("[FS] Scan abgeschlossen: %d Dateien, %d Hinweise.", scanned, flagged))
  term.setCursorPos(3,12)
  if flagged > 0 then
    print(string.format("Ergebnis: %d Hinweis(e) ohne Relevanz. Kein Eingriff erforderlich.", flagged))
  else
    print("Ergebnis: Keine Auffaelligkeiten.")
  end
  term.setCursorPos(3,14); print("Nachtrag: Falls ein Keks im Laufwerk gefunden wird, bitte melden.")
  pressToContinueRobust(h-2)
end

-------------------- Dienstprogramme --------------------
local function toolCookieRule()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4,"Richtlinie 'Keks-Regel'")
  term.setCursorPos(3,6); print("- Lesen lokaler Keks-Bestaende ..."); loadingDots(32,6,0.9)
  term.setCursorPos(3,7); print("- Evaluierung NAEHRWERT ... OK")
  term.setCursorPos(3,8); print("- Durchsetzung: Moderat")
  addLog("[POLICY] Keks-Regel ueberprueft.")
  term.setCursorPos(3,10); print("Ergebnis: Keksverbrauch unter Kontrolle. Keine Massnahmen noetig.")
  term.setCursorPos(3,12); print("Hinweis: Krue-mel im Luefter ignoriert.")
  pressToContinueRobust(14)
end

local function toolEgoCalibration()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4,"Ego-Telemetrie Kalibrierung")
  term.setCursorPos(3,6); print("- Ausgangspegel erfassen ..."); loadingDots(32,6,0.9)
  term.setCursorPos(3,7); print("- Offset berechnen ... OK")
  term.setCursorPos(3,8); print("- Zielwert setzen ... OK")
  addLog("[CAL] Ego-Telemetrie kalibriert.")
  term.setCursorPos(3,10); print("Kalibrierung abgeschlossen: Selbstbewusstsein stabil.")
  term.setCursorPos(3,12); print("Anmerkung: Spiegel nickt zustimmend.")
  pressToContinueRobust(14)
end

local function toolDancefloor()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4,"Visual Test: Dancefloor")
  term.setCursorPos(3,6); print("- Initialisiere Muster ..."); loadingDots(32,6,0.8)
  for row=8,12 do
    term.setCursorPos(3,row)
    for col=1,math.min(w-6,48) do term.write(((row+col)%2==0) and "#" or ".") end
    sleep(0.05)
  end
  addLog("[VIS] Dancefloor-Muster dargestellt.")
  term.setCursorPos(3,13); print("Hinweis: Sichtbar nur fuer Eingeweihte.")
  pressToContinueRobust(15)
end

local function toolAutoFeedback()
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(4,"Automatisches Feedback")
  term.setCursorPos(3,6); print("- Sammle Telemetrie ..."); loadingDots(32,6,0.9)
  term.setCursorPos(3,7); print("- Generiere Zusammenfassung ... OK")
  term.setCursorPos(3,8); print("- Sende Bericht ... OK")
  addLog("[FEED] Automatisches Feedback gesendet.")
  term.setCursorPos(3,10); print("Bericht versandt. Inhalt: Alles bestens, weiter so.")
  term.setCursorPos(3,12); print("PS: System wuenscht sich Cookies.")
  pressToContinueRobust(14)
end

local function utilitiesMenu()
  while true do
    clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
    centerText(4,"Werkzeuge und Dienstprogramme")
    local baseY=6
    local items={
      "Richtlinie 'Keks-Regel' anzeigen",
      "Ego-Telemetrie kalibrieren",
      "Visual Test: Dancefloor",
      "Automatisches Feedback senden",
      "Zurueck"
    }
    for i,v in ipairs(items) do
      term.setCursorPos(4, baseY + i - 1); term.write(i..") "..v)
      addTouchArea(1, baseY + i - 1, w, baseY + i - 1, "util_"..i, function() end)
    end
    term.setCursorPos(4, baseY + #items + 2); term.write("Zahl oder tippen. [+/-] Schriftgroesse")

    local ev,p1,p2,p3 = os.pullEvent()
    local sel=nil
    if ev=="char" and p1>='1' and p1<='5' then sel=tonumber(p1)
    elseif ev=="key" and p1==keys.enter then sel=5
    elseif ev=="monitor_touch" then
      local id=handleTouch(p2,p3)
      if id and id:match("^util_") then sel=tonumber(id:match("util_(%d+)")) end
      if id=="font_minus" then changeScale(-SCALE_STEP) elseif id=="font_plus" then changeScale(SCALE_STEP) end
    elseif ev=="char" and (p1=="+" or p1=="-") then changeScale(p1=="+" and SCALE_STEP or -SCALE_STEP)
    end

    if sel==1 then toolCookieRule()
    elseif sel==2 then toolEgoCalibration()
    elseif sel==3 then toolDancefloor()
    elseif sel==4 then toolAutoFeedback()
    elseif sel==5 then return end
  end
end

-------------------- Logs Ansicht (mit Zurueck-Button) --------------------
local function showLogs()
  local pos=1
  while true do
    clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
    local backLabel="[ Zurueck ]"
    term.setCursorPos(2,1); term.write(backLabel)
    addTouchArea(2,1,2+#backLabel-1,1,"logs_back",function() end)

    centerText(4,"SYSTEM LOGS (neueste oben)")
    local maxLines=h-10; local baseY=6
    for i=1,maxLines do
      local idx=pos+i-1
      term.setCursorPos(2, baseY + i - 1); term.clearLine()
      if logs[idx] then
        term.setTextColor(colors.white)
        local text=logs[idx]; if #text>w-4 then text=text:sub(1,w-7).."..." end
        term.write(text)
      end
    end
    term.setTextColor(colors.gray)
    term.setCursorPos(2, baseY + maxLines + 1); term.write("Pfeile scrollen, Enter/Zurueck-Button = zurueck, +/- Schriftgroesse")
    term.setTextColor(colors.white)
    addTouchArea(1, baseY, w, baseY, "scroll_up", function() pos = math.max(1, pos-1) end)
    addTouchArea(1, baseY + maxLines, w, baseY + maxLines, "scroll_down", function() pos = math.min(math.max(1, #logs - maxLines + 1), pos+1) end)

    local ev,p1,p2,p3 = os.pullEvent()
    if ev=="key" then
      if p1==keys.up then pos=math.max(1,pos-1)
      elseif p1==keys.down then pos=math.min(math.max(1,#logs-maxLines+1),pos+1)
      elseif p1==keys.enter then return
      elseif p1==keys.minus or p1==keys.numPadSubtract then changeScale(-SCALE_STEP)
      elseif p1==keys.equals or p1==keys.numPadAdd then changeScale(SCALE_STEP) end
    elseif ev=="char" then
      if p1=="+" then changeScale(SCALE_STEP) elseif p1=="-" then changeScale(-SCALE_STEP) end
    elseif ev=="monitor_touch" then
      local id=handleTouch(p2,p3)
      if id=="logs_back" then return end
    end
  end
end

-------------------- Hauptmenue --------------------
local function menuSelect(yFirst,count)
  while true do
    local ev,a,b=waitKeyOrTouch()
    if ev=="char" then
      if a>='0' and a<='9' then return a end
      if a=="+" then changeScale(SCALE_STEP) elseif a=="-" then changeScale(-SCALE_STEP) end
    elseif ev=="key" then
      if a==keys.enter then return "\n" end
      if a==keys.equals or a==keys.numPadAdd then changeScale(SCALE_STEP)
      elseif a==keys.minus or a==keys.numPadSubtract then changeScale(-SCALE_STEP) end
    elseif ev=="monitor_touch" then
      local id=handleTouch(a,b)
      if id~="font_minus" and id~="font_plus" then
        for i=1,count do if b==yFirst+(i-1) then return tostring(i) end end
      end
    end
  end
end

local function mainMenu()
  while true do
    resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
    centerText(4, "Administrative Werkzeuge")
    local baseY=6
    local entries={
      "Sicherheitsprotokoll 7B (Vorbereitung)", -- Selbstzerstoerungs-Spaß, seriös formuliert
      "Remote-Diagnose",
      "Interaktives Modul (Test)",
      "Logs anzeigen",
      "Dienstprogramme",
      "Geplanter Neustart",
      "Dateisystem-Scan",
      "Beenden"
    }
    for i,v in ipairs(entries) do
      term.setCursorPos(4, baseY + i - 1); term.write(i%8==0 and "0) "..v or (i..") "..v))
      addTouchArea(1, baseY + i - 1, w, baseY + i - 1, "menu_"..i, function() end)
    end
    term.setCursorPos(4, baseY + #entries + 2); term.write("Zahl eingeben oder tippen. [+/-] Schriftgroesse")

    local sel = menuSelect(baseY, #entries)
    addLog("[UI] Auswahl: " .. tostring(sel))
    if sel=="1" then selfDestructMode()
    elseif sel=="2" then hackMojangAnimation()
    elseif sel=="3" then interaktiveTanzroutine()
    elseif sel=="4" then showLogs()
    elseif sel=="5" then utilitiesMenu()
    elseif sel=="6" then
      clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
      centerText(4,"System wird neu gestartet ...")
      for i=1,3 do centerText(6,"Neustart in "..(4-i).." ..."); safePlayNote("C","bass",0.7); sleep(0.9) end
      term.clear(); centerText(6,"Start abgeschlossen."); addLog("[INFO] Geplanter Neustart simuliert."); sleep(1.2)
      centerText(8,"Hinweis: Kaffee bleibt heiss."); sleep(0.9)
    elseif sel=="7" then fileSystemScan()
    elseif sel=="8" or sel=="0" then
      addLog("[INFO] Sitzung beendet.")
      clearAndHeader(true); drawScaleLabelAndButtons()
      centerText(6,"Abmeldung ..."); safePlayNote("C","pling",0.7); sleep(1.2); term.clear(); return
    end
  end
end

-------------------- Login --------------------
local function banner(y)
  term.setCursorPos(3,y);   term.write("Zugriff nur fuer autorisierte Administratoren.")
  term.setCursorPos(3,y+1); term.write("Alle Aktionen werden protokolliert.")
end

local function loginIntro()
  resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  term.setTextColor(colors.lightBlue); centerText(3,"== AUTHENTICATION REQUIRED =="); term.setTextColor(colors.white)
  banner(4); drawLoginStatusPanel(8)

  local label="[ Weiter ]"
  local btnX = math.floor((w - #label)/2)+1
  local btnY = h-2
  term.setCursorPos(btnX,btnY); term.write(label)
  addTouchArea(btnX,btnY,btnX+#label-1,btnY,"login_next",function() end)

  local hint = "Enter oder Tippen, automatisch in "..tostring(LOGIN_STATUS_AUTOSECONDS).." s ..."
  centerText(h-1, hint)

  local timerId = os.startTimer(LOGIN_STATUS_AUTOSECONDS)
  while true do
    local ev,p1,p2,p3 = os.pullEvent()
    if ev=="key" and p1==keys.enter then break end
    if ev=="char" then if p1=="+" then changeScale(SCALE_STEP) elseif p1=="-" then changeScale(-SCALE_STEP) end end
    if ev=="monitor_touch" then
      local side,x,y = p1,p2,p3
      if mon and side==peripheral.getName(mon) then
        local id=handleTouch(x,y); if id=="login_next" then break end
      end
    elseif ev=="timer" and p1==timerId then break
    elseif ev=="term_resize" then
      resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
      term.setTextColor(colors.lightBlue); centerText(3,"== AUTHENTICATION REQUIRED =="); term.setTextColor(colors.white)
      banner(4); drawLoginStatusPanel(8)
      btnX = math.floor((w - #label)/2)+1; btnY = h-2
      term.setCursorPos(btnX,btnY); term.write(label)
      addTouchArea(btnX,btnY,btnX+#label-1,btnY,"login_next",function() end)
      centerText(h-1, hint)
    end
  end
end

local function loginForm()
  resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  term.setTextColor(colors.lightBlue); centerText(3,"== AUTHENTICATION =="); term.setTextColor(colors.white)
  local yForm = 7
  term.setCursorPos(4,yForm);   term.write("Name:     ")
  local user, kbY1 = readLineTouch(15,yForm,false)

  -- kleine Ehrenbezeichnung, wenn bekannte Namen erkannt werden (subtil)
  local uLower = tostring(user):lower()
  local honor = HONORIFY[uLower]
  if honor then addLog("[AUTH] Identitaetshinweis: "..honor) end

  clearKeyboardArea(kbY1); drawScaleLabelAndButtons()
  term.setCursorPos(4,yForm+1); term.write("Passwort: ")
  local pass, kbY2 = readLineTouch(15,yForm+1,true)

  -- Bildschirm leeren vor Validierung
  clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()

  local checkY=5
  term.setCursorPos(4,checkY+0); term.write("Pruefe Zeitsynchronisation"); loadingDots(32,checkY+0,LOGIN_STEP_DELAY); sleep(0.2)
  term.setCursorPos(4,checkY+1); term.write("Lade ACL");                  loadingDots(32,checkY+1,LOGIN_STEP_DELAY); sleep(0.2)
  term.setCursorPos(4,checkY+2); term.write("Validiere Token");           loadingDots(32,checkY+2,LOGIN_STEP_DELAY); sleep(0.2)
  term.setCursorPos(4,checkY+3); term.write("Initialisiere Audit-Stream");loadingDots(32,checkY+3,LOGIN_STEP_DELAY); sleep(0.2)
  term.setCursorPos(4,checkY+4); term.write("Kerberos-Skew: 0."..math.random(1,9).."s"); sleep(LOGIN_STEP_DELAY)

  term.setCursorPos(4,checkY+6); term.setTextColor(colors.green)
  local greet = honor and (honor..", willkommen.") or ("Willkommen, "..USERNAME_DISPLAY..".")
  print("Zugriff gewaehrt. "..greet)
  term.setTextColor(colors.white)
  addLog("[AUTH] Anmeldung von '"..tostring(user).."' erfolgreich.")
  sleep(POST_LOGIN_DWELL)
end

local function login()
  loginIntro()
  loginForm()
end

-------------------- Start --------------------
local function start()
  resizeCache(); clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
  centerText(3,"Systemkonsole")
  centerText(5,"Weiter mit Enter oder durch Tippen")
  while true do
    local ev,a,b=waitKeyOrTouch()
    if ev=="key" and a==keys.enter then break end
    if ev=="monitor_touch" then local id=handleTouch(a,b); if id~="font_minus" and id~="font_plus" then break end end
    if ev=="char" then if a=="+" then changeScale(SCALE_STEP) elseif a=="-" then changeScale(-SCALE_STEP) else break end end
    if ev=="term_resize" then
      clearTouchAreas(); clearAndHeader(true); drawScaleLabelAndButtons()
      centerText(3,"Systemkonsole"); centerText(5,"Weiter mit Enter oder durch Tippen")
    end
  end
  login()
  mainMenu()
end

-------------------- Run --------------------
start()
