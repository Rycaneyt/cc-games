-- fake_admin.lua (Dual-Output: Terminal + Monitor)
-- Fake "Admin" Easter Egg für Computercraft (Minecraft 1.20.1)
-- Autor: Assistant (angepasst für Fabio)

local USERNAME_DISPLAY = "König Fabio" -- ändere falls gewünscht
local VERSION = "FabIO-AdminOS v1.1 (TotallySecure + DualOutput)"

-- ========= Dual-Output Setup (Terminal + Monitor) =========
local nativeTerm = term.native()
local mon = nil
local ok, found = pcall(function() return peripheral.find("monitor") end)
if ok and found then
  mon = found
  -- Für 8x4 Blöcke: niedrige Textskalierung = hohe Auflösung
  -- Passe bei Bedarf an (z.B. 0.5, 0.75, 1, 2, ...)
  pcall(function() mon.setTextScale(0.5) end)
end

local function makeMultiTerm(t1, t2) -- t1=nativeTerm, t2=monitor (optional)
  local terms = { t1 }
  if t2 then table.insert(terms, t2) end

  local function each(fn)
    for _,t in ipairs(terms) do
      fn(t)
    end
  end

  local api = {}

  function api.getSize()
    local w1,h1 = terms[1].getSize()
    if terms[2] then
      local w2,h2 = terms[2].getSize()
      -- Gleiche Fläche auf beiden Geräten nutzbar machen
      return math.min(w1, w2), math.min(h1, h2)
    end
    return w1,h1
  end

  function api.setCursorPos(x,y) each(function(t) t.setCursorPos(x,y) end) end
  function api.clear()            each(function(t) t.clear() end) end
  function api.clearLine()        each(function(t) t.clearLine() end) end
  function api.setTextColor(c)    each(function(t) t.setTextColor(c) end) end
  function api.setBackgroundColor(c) each(function(t) if t.setBackgroundColor then t.setBackgroundColor(c) end end) end
  function api.write(s)           each(function(t) t.write(s) end) end
  function api.scroll(n)          each(function(t) if t.scroll then t.scroll(n) end end) end
  function api.isColor()          return terms[1].isColor and terms[1].isColor() or true end

  -- Für print() & read() wichtig:
  function api.getCursorPos()
    -- Wir lesen Position vom nativen Terminal und setzen überall gleich
    return terms[1].getCursorPos()
  end

  return api
end

-- Multi-Terminal erstellen und aktivieren
local mterm = makeMultiTerm(nativeTerm, mon)
term.redirect(mterm)

-- ========= Restliches Programm (nutzt jetzt 'term' = mterm) =========

math.randomseed(os.time())
local w,h = term.getSize()

-- speaker detection (optional)
local speaker = nil
local sok, sp = pcall(function() return peripheral.find("speaker") end)
if sok and sp then speaker = sp end

local function safePlayNote(note, instrument, volume)
  if not speaker then return end
  pcall(function()
    if speaker.playNote then
      speaker.playNote(instrument or "harp", note or "C", volume or 1)
    elseif speaker.play then
      speaker.play(note or "C", volume or 1)
    end
  end)
end

-- kleine Hilfsfunktionen
local function centerText(y, text)
  local tw = #text
  local x = math.max(1, math.floor((w - tw) / 2) + 1)
  term.setCursorPos(x, y)
  term.write(text)
end

local function clearAndHeader()
  term.clear()
  term.setCursorPos(1,1)
  term.setTextColor(colors.white)
  centerText(1, VERSION)
  term.setCursorPos(1,2)
  term.setTextColor(colors.gray)
  centerText(2, string.rep("─", math.min(w, #VERSION + 6)))
  term.setTextColor(colors.white)
end

local function loadingDots(x, y, duration)
  duration = duration or 1.2
  local start = os.clock()
  local i = 0
  while os.clock() - start < duration do
    local dots = string.rep(".", (i % 4))
    term.setCursorPos(x,y)
    term.write(dots .. string.rep(" ", 4 - #dots))
    sleep(0.2)
    i = i + 1
  end
end

-- Logs
local logs = {}
local function addLog(line, isFake)
  local t = os.date("[%Y-%m-%d %H:%M:%S]")
  table.insert(logs, 1, (t .. " " .. line))
  if #logs > 200 then
    for i = 201, #logs do table.remove(logs) end
  end
end

-- seed logs
addLog("[INFO] System gestartet. Willkommen, " .. USERNAME_DISPLAY .. "!", false)
addLog("[SEC] Biometrische Authentifizierung nicht gefunden. Fallback: Humor.", true)
addLog("[LOG] Fabio hat 3x laut 'LOL' gelacht während einer Systemwartung.", true)
addLog("[LOG] Backup: Letzte Sicherung vor " .. math.random(1,72) .. " Stunden.", false)
addLog("[CAT] Kuh Lucy hat Zugangsanfrage gestellt. Abgelehnt.", true)
addLog("[INFO] Netzwerkstatus: Verbunden (Lokales Netzwerk).", false)

-- AI Assistent
local function aiSpeak(lines, delay)
  delay = delay or 0.8
  for _,ln in ipairs(lines) do
    term.setTextColor(colors.yellow)
    print("> AI: " .. ln)
    term.setTextColor(colors.white)
    safePlayNote("C", "harp", 0.5)
    sleep(delay)
  end
end

-- Animationen & Aktionen
local function explosionAnimation()
  clearAndHeader()
  centerText(4, "WARNUNG: Selbstzerstörungs-Protokoll wird initialisiert")
  term.setTextColor(colors.red)
  centerText(6, "5")
  safePlayNote("G", "bass", 1)
  sleep(0.6)
  centerText(6, "4")
  safePlayNote("E", "bass", 1)
  sleep(0.6)
  centerText(6, "3")
  safePlayNote("D", "bass", 1)
  sleep(0.6)
  centerText(6, "2")
  safePlayNote("C", "bass", 1)
  sleep(0.6)
  centerText(6, "1")
  safePlayNote("B", "bass", 1)
  sleep(0.5)
  term.setTextColor(colors.magenta)
  centerText(8, "BOOOM! ... oder auch nicht. :)")
  safePlayNote("C", "pling", 1)
  sleep(1.2)
  addLog("[ACTION] Versuch Selbstzerstörung initiiert (Simuliert).", true)
  term.setTextColor(colors.white)
end

local function hackMojangAnimation()
  clearAndHeader()
  centerText(4, "Infiltrieren von Mojang-Netzwerk...")
  local barY = 6
  term.setCursorPos(4, barY)
  term.write("[")
  term.setCursorPos(w-3, barY)
  term.write("]")
  for i = 1, (w - 10) do
    term.setCursorPos(5 + i, barY)
    term.setTextColor((i % 2 == 0) and colors.green or colors.lightBlue)
    term.write("=")
    if i % 4 == 0 then safePlayNote("C", "harp", 0.6) end
    sleep(0.03)
  end
  term.setTextColor(colors.white)
  centerText(8, "Zugriff auf Mojang: ERLAUBT (fake).")
  addLog("[SEC] 'Mojang breach' durchgeführt — Ergebnis: Nur Katzenvideos gefunden.", true)
  sleep(1)
end

local function fabioDance()
  clearAndHeader()
  centerText(4, USERNAME_DISPLAY .. "'s geheime Tanzroutine wird aktiviert...")
  aiSpeak({"Ohhh, fantastisch! Du möchtest die Tanzroutine sehen? Großartige Wahl!", "Aktiviere move_set: FABIO_FUNK_2025..."}, 0.6)
  local frames = {
    [[\o/   .  _   .   \o/]],
    [[ _\o  . ( )  .  _\o_]],
    [[  /|  . / \  .   /| ]],
    [[ \o   .  ∆   .   \o/]]
  }
  for r = 1,6 do
    for i,fr in ipairs(frames) do
      term.setCursorPos(1,10)
      term.clearLine()
      centerText(10, fr .. "   (★)")
      safePlayNote("C", "harp", 0.5 + 0.05 * i)
      sleep(0.25)
    end
  end
  term.setTextColor(colors.cyan)
  centerText(12, "Tanzroutine abgeschlossen. Publikum: 1 (du).")
  addLog("[FUN] Fabio tanzte 17 Sekunden lang. Zustimmung: 100%.", true)
  term.setTextColor(colors.white)
  sleep(1)
end

local function sillyOptions()
  clearAndHeader()
  centerText(4, "Ausgewählte Scherze und Aktionen:")
  local silly = {
    "1) Aktivieren: 'Keks-Regel' (alle keksbasierenden Aktionen verboten).",
    "2) 'Upgrade Ego' (Ego +9000, temporär).",
    "3) 'Deploy Dancefloor' (Lichtshow, unsichtbar).",
    "4) 'Send Fabio a compliment' (automatisch)."
  }
  for i,v in ipairs(silly) do
    term.setCursorPos(4, 6 + i)
    term.write(v)
  end
  addLog("[INFO] Benutzer schaute sich lustige Optionen an.", true)
  print("\nDrücke Enter zum Zurückkehren.")
  read() -- warte
end

local function fakeRestart()
  clearAndHeader()
  centerText(4, "System wird neu gestartet...")
  for i = 1,3 do
    centerText(6, "Neustart in " .. (4 - i) .. "...")
    safePlayNote("C", "bass", 0.8)
    sleep(0.8)
  end
  term.clear()
  centerText(6, "Start erfolgreich. Alles wirklich genau so wie vorher.")
  addLog("[INFO] System 'neustart' ausgeführt (fake).", false)
  sleep(1)
end

local function corruptFiles()
  clearAndHeader()
  centerText(4, "Dateisystem wird gescannt...")
  for i = 1, w-10 do
    term.setCursorPos(5+i, 8)
    term.write(string.char(33 + (i % 60)))
    sleep(0.005)
  end
  centerText(10, "FEHLER: Keine peinlichen Dateien gefunden. Glück gehabt!")
  addLog("[WARN] Scan nach peinlichen Dateien: 0/0 (fehlerhaft).", true)
  sleep(1.2)
end

-- Logs anzeigen, scrollbar
local function showLogs()
  local pos = 1
  while true do
    local W,H = term.getSize() -- dynamisch falls Monitor/Skalierung anders ist
    w,h = W,H
    clearAndHeader()
    centerText(4, "SYSTEM LOGS (neueste oben) - ↑↓ scrollen, Enter = zurück")
    local maxLines = h - 8
    for i = 1, maxLines do
      local idx = pos + i - 1
      term.setCursorPos(2, 6 + i)
      term.clearLine()
      if logs[idx] then
        if string.find(logs[idx], "WARN") or string.find(logs[idx], "FEHLER") then
          term.setTextColor(colors.red)
        elseif string.find(logs[idx], "FUN") or string.find(logs[idx], "CAT") then
          term.setTextColor(colors.magenta)
        else
          term.setTextColor(colors.white)
        end
        local text = logs[idx]
        if #text > w-4 then text = text:sub(1, w-7) .. "..." end
        term.write(text)
      end
    end
    term.setTextColor(colors.gray)
    centerText(h, string.format("Anzeigen: %d-%d von %d", pos, math.min(pos+maxLines-1, #logs), #logs))
    term.setTextColor(colors.white)
    local ev, key = os.pullEvent("key")
    if ev == "key" then
      if key == keys.up then
        pos = math.max(1, pos - 1)
      elseif key == keys.down then
        pos = math.min(math.max(1, #logs - maxLines + 1), pos + 1)
      elseif key == keys.enter then
        return
      end
    end
  end
end

-- Menü & Eingabe
local function mainMenu()
  while true do
    local W,H = term.getSize()
    w,h = W,H
    clearAndHeader()
    centerText(4, "== Super-Geheimes Admin-Interface ==")
    term.setCursorPos(4,6)
    term.write("1) Server Selbstzerstörung aktivieren")
    term.setCursorPos(4,7)
    term.write("2) Hacke das Mojang-Netzwerk")
    term.setCursorPos(4,8)
    term.write("3) Aktiviere " .. USERNAME_DISPLAY .. "'s geheime Tanzroutine")
    term.setCursorPos(4,9)
    term.write("4) Zeige Logs")
    term.setCursorPos(4,10)
    term.write("5) Lustige Optionen anschauen")
    term.setCursorPos(4,11)
    term.write("6) System 'Neustart'")
    term.setCursorPos(4,12)
    term.write("7) Scan nach peinlichen Dateien")
    term.setCursorPos(4,13)
    term.write("0) Beenden")
    term.setCursorPos(4,15)
    term.write("Wähle eine Option (Zahl): ")
    local ch = read()
    addLog("[UI] Auswahl: " .. tostring(ch), false)

    if ch == "1" then
      explosionAnimation()
    elseif ch == "2" then
      hackMojangAnimation()
    elseif ch == "3" then
      fabioDance()
    elseif ch == "4" then
      showLogs()
    elseif ch == "5" then
      sillyOptions()
    elseif ch == "6" then
      fakeRestart()
    elseif ch == "7" then
      corruptFiles()
    elseif ch == "0" then
      addLog("[INFO] Benutzer hat das Programm beendet.", false)
      clearAndHeader()
      centerText(6, "Auf Wiedersehen, " .. USERNAME_DISPLAY .. "! (Oder bis gleich...)")
      safePlayNote("C", "pling", 0.8)
      sleep(1)
      term.clear()
      return
    else
      term.setTextColor(colors.red)
      print("Ungültige Eingabe. Versuch es nochmal, Meister.")
      term.setTextColor(colors.white)
      sleep(0.9)
    end
  end
end

-- Login (immer erfolgreich)
local function login()
  term.clear()
  term.setCursorPos(1,1)
  term.setTextColor(colors.lightBlue)
  centerText(2, "== SECURE ADMIN ACCESS ==")
  term.setTextColor(colors.white)
  centerText(4, "Bitte melden Sie sich an. Nur Admins dürfen fortfahren.")
  term.setCursorPos(4,6)
  term.write("Username: ")
  local user = read()
  term.setCursorPos(4,7)
  term.write("Password: ")
  -- Password (maskiert)
  local pass = ""
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "char" then
      pass = pass .. p1
      term.write("*")
    elseif ev == "key" and p1 == keys.enter then
      break
    end
  end
  -- Dramatische Pause & "immer gewährt"
  loadingDots(4 + 10, 9, 1.4)
  term.setCursorPos(4,9)
  term.setTextColor(colors.green)
  print("Zugriff gewährt. Herzlich willkommen, " .. USERNAME_DISPLAY .. "!")
  term.setTextColor(colors.white)
  addLog("[AUTH] Anmeldung von '" .. tostring(user) .. "' erfolgreich (Auth: Humor).", true)
  aiSpeak({
    "Oh hallo " .. USERNAME_DISPLAY .. "! Wie wunderbar, dich zu sehen!",
    "Ich, dein loyales Assistenzsystem, stehe dir zur Verfügung.",
    "Soll ich mal die Stimmung im Serverraum zählen? (Ja, ich zähle Stimmung.)"
  }, 0.7)
  sleep(0.8)
end

-- Start
local function start()
  term.clear()
  term.setCursorPos(1,1)
  term.setTextColor(colors.white)
  centerText(3, "Willkommen zur Entertainment Station")
  centerText(5, "Starte das geheime Admin-Programm? (Enter)")
  read()
  login()
  mainMenu()
end

-- run
start()
