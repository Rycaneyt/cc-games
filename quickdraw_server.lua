-- quickdraw_server.lua — QuickDraw Duel (2 Spieler)
-- Features: Sound (Speaker), Namenseingabe, Latenz, Best-of-X, Match-Code

---------------------- Konfiguration ----------------------
local MATCH_CODE = "QD123"   -- beide Clients müssen denselben Code senden
local BEST_OF    = 5         -- Runden bis Match-Sieg (3,5,7,...)
-----------------------------------------------------------

-- Peripherals
local modem = peripheral.find("modem"); assert(modem, "Kein Modem!")
rednet.open(peripheral.getName(modem))
local mon = peripheral.find("monitor"); assert(mon, "Kein Monitor!")
mon.setTextScale(0.5); mon.setBackgroundColor(colors.black); mon.setTextColor(colors.white); mon.clear()
local spk = peripheral.find("speaker") -- optional, aber empfohlen

-- Helpers (Anzeige)
local function W() local w,_=mon.getSize() return w end
local function H() local _,h=mon.getSize() return h end
local function center(y, txt, fg, bg)
  if bg then mon.setBackgroundColor(bg) end
  mon.setTextColor(fg or colors.white)
  local x = math.floor((W()-#txt)/2)+1
  mon.setCursorPos(x, y); mon.write(txt)
  mon.setBackgroundColor(colors.black); mon.setTextColor(colors.white)
end
local function clear() mon.setBackgroundColor(colors.black); mon.setTextColor(colors.white); mon.clear() end

-- Helpers (Sound)
local function s_note(name, vol, pitch) if spk then spk.playNote(name or "bit", vol or 1.0, pitch or 12) end end
local function s_readyTick() s_note("hat", 0.8, 12) end
local function s_go()        s_note("chime", 1.0, 18) end
local function s_tooEarly()  if spk then spk.playSound("minecraft:block.note_block.bass") end end
local function s_victory()   s_note("bell", 1.0, 15); sleep(0.05); s_note("bell", 1.0, 18) end

-- Spieler & Score
local players = {}   -- { {id=rednetID, name="...", score=0, last_ms=0}, { ... } }
local need = math.floor(BEST_OF/2)+1

local function uniqName(name)
  local n, dup= name, 0
  for _,p in ipairs(players) do if p.name==n then dup=dup+1 end end
  if dup>0 then n = n.." ("..(dup+1)..")" end
  return n
end

local function drawLobby(status)
  clear()
  center(2, "QUICKDRAW DUEL", colors.yellow)
  center(3, ("Match-Code: %s"):format(MATCH_CODE), colors.lightGray)
  if status then center(5, status, colors.cyan) end
  for i=1,2 do
    local line = players[i] and (("P%d: %s (#%d)"):format(i, players[i].name, players[i].id)) or ("P"..i..": -- frei --")
    center(7+i, line, players[i] and colors.lime or colors.gray)
  end
end

local function drawScoreboard(msg)
  clear()
  center(1, "QUICKDRAW DUEL", colors.yellow)
  center(2, ("Best-of-%d  (Ziel: %d Siege)"):format(BEST_OF, need), colors.lightBlue)
  for i=1,2 do
    local p = players[i]
    local line = ("%s   Score: %d   %s"):format(p.name, p.score, p.last_ms>0 and (p.last_ms.." ms") or "")
    center(4+i, line, colors.white)
  end
  if msg then center(8, msg, colors.orange) end
  center(H()-1, "Warte...", colors.gray)
end

-- Lobby: 2 Spieler verbinden
local function waitPlayers()
  players = {}
  drawLobby("Warten auf 2 Spieler...")
  while #players < 2 do
    local id, msg, prot = rednet.receive("qd_join")
    if type(msg)=="table" and msg.code==MATCH_CODE and msg.name then
      local name = uniqName(msg.name)
      table.insert(players, {id=id, name=name, score=0, last_ms=0})
      rednet.send(id, {ok=true, idx=#players, name=name}, "qd_ack")
      drawLobby(("Beigetreten: %s"):format(name))
    else
      rednet.send(id, {ok=false, reason="Falscher Code/Format"}, "qd_ack")
    end
  end
  sleep(1)
end

-- Runde: Countdown -> GO -> wertung
local function playRound()
  -- Reset round info
  for _,p in ipairs(players) do p.last_ms = 0 end
  drawScoreboard("Bereit machen...")
  s_readyTick(); sleep(0.8); s_readyTick()
  center(6, "Nicht drücken!", colors.red)
  -- Zufallswartezeit
  local wait = math.random(18,42) / 10  -- 1.8 .. 4.2s
  local goSent = false
  local goTime = 0

  -- kündige GO nach Wartezeit an
  local timer = os.startTimer(wait)

  -- Sammelstatus
  local early = {}           -- id => true
  local winner = nil         -- id
  local winner_ms = nil

  -- Eventloop bis Ergebnis
  while true do
    local e,a,b,c = os.pullEvent()
    if e=="timer" and a==timer and not goSent then
      -- GO!
      goSent = true
      goTime = os.epoch("utc")
      center(6, "JETZT!!!", colors.lime); s_go()
      -- Signal an Clients inkl. Serverzeit
      for _,p in ipairs(players) do rednet.send(p.id, {type="go", t0=goTime}, "qd_evt") end
    elseif e=="rednet_message" then
      local id, msg, prot = a,b,c
      if prot=="qd_click" and type(msg)=="table" and msg.code==MATCH_CODE then
        if msg.action=="early" and not goSent then
          early[id] = true; s_tooEarly()
        elseif msg.action=="press" and goSent and not winner then
          -- Latenz (inkl. Funk/Rednet-Verzögerung, aber fair für beide)
          local now = os.epoch("utc")
          local ms = math.max(0, now - goTime)
          winner = id; winner_ms = ms
        end
      end
    end

    -- Auswertung
    if winner or (goSent and (early[players[1].id] and early[players[2].id])) then
      break
    end
    -- Falls jemand zu früh war und der andere noch vor GO nicht gedrückt hat: warten bis GO, dann der andere kann gewinnen.
    -- (Kein weiterer Spezialfall nötig.)
  end

  -- Ergebnis verarbeiten
  local msg = nil
  if winner then
    local idx = (winner==players[1].id) and 1 or 2
    players[idx].score = players[idx].score + 1
    players[idx].last_ms = winner_ms
    msg = ("%s gewinnt!  (%d ms)"):format(players[idx].name, winner_ms)
    s_victory()
  elseif early[players[1].id] and early[players[2].id] then
    msg = "Beide zu früh!"
    s_tooEarly()
  end

  drawScoreboard(msg)
  -- Matchende?
  for i=1,2 do
    if players[i].score >= need then
      center(10, ("MATCH ENDE: %s gewinnt!"):format(players[i].name), colors.lime)
      for _,p in ipairs(players) do rednet.send(p.id, {type="end", winner=players[i].name}, "qd_evt") end
      sleep(3)
      return true
    end
  end

  -- nächste Runde nach kurzer Pause
  sleep(2)
  return false
end

-- Main
math.randomseed(os.epoch and os.epoch("utc") or os.time())
while true do
  waitPlayers()
  drawScoreboard("Spiel startet...")
  for _,p in ipairs(players) do rednet.send(p.id, {type="ready", best=BEST_OF}, "qd_evt") end
  -- Runden bis Match-Sieg
  while true do
    local done = playRound()
    if done then break end
  end
  -- Scores zurücksetzen für next match
  sleep(2)
end
