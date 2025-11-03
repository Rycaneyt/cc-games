-- entertainment_story.lua  (v2)
-- CC:Tweaked / ComputerCraft – Multi-Monitor Text-Adventure mit Themes, Save/Load/Reset,
-- Touch-Buttons, Animationen, Auto-TextScale und optionalen Soundeffekten (speaker)
--
-- Start: entertainment_story

----------------------------------------------------------------
-- Persistenz / Pfade
----------------------------------------------------------------
local SAVE_FILE   = "entertainment_save"
local CONFIG_FILE = "entertainment_config"

----------------------------------------------------------------
-- Peripherals: Monitor + Speaker
----------------------------------------------------------------
local function findBiggestMonitor()
  local mons = { peripheral.find and peripheral.find("monitor") or nil }
  if #mons == 0 then return nil end
  local best, area = nil, -1
  for _,m in ipairs(mons) do
    local w,h = m.getSize()
    if w*h > area then best, area = m, w*h end
  end
  return best
end

local mon = findBiggestMonitor()
if not mon then
  print("Kein Monitor gefunden! Bitte Advanced-Monitor anschließen.")
  return
end
local oldTerm = term.redirect(mon)
term.setCursorBlink(false)

-- Optionaler Lautsprecher (SFX)
local speaker = peripheral.find and peripheral.find("speaker") or nil
local function sfx_ok() return speaker ~= nil end
local function beep(freq, dur, vol)
  if not sfx_ok() then return end
  pcall(function() speaker.playSound("minecraft:block.note_block.pling",{volume=vol or 0.7, pitch=(freq or 1.0)}) end)
end
local function jingle_success()
  if not sfx_ok() then return end
  local pitches = {1.2, 1.35, 1.5}
  for i=1,#pitches do beep(pitches[i], 0.07, 0.7); sleep(0.07) end
end
local function jingle_click() beep(1.0, 0.03, 0.5) end

----------------------------------------------------------------
-- Themes
----------------------------------------------------------------
local THEMES = {
  Ocean = {
    bg=colors.black, fg=colors.white, frame=colors.gray,
    titleBg=colors.blue, titleFg=colors.white, statusBg=colors.gray, statusFg=colors.white,
    hlBg=colors.cyan, hlFg=colors.black, btnNum=colors.yellow, accent=colors.lightBlue,
    good=colors.green, bad=colors.red, neutral=colors.orange
  },
  Sunset = {
    bg=colors.black, fg=colors.white, frame=colors.gray,
    titleBg=colors.orange, titleFg=colors.black, statusBg=colors.brown, statusFg=colors.white,
    hlBg=colors.red, hlFg=colors.white, btnNum=colors.yellow, accent=colors.magenta,
    good=colors.orange, bad=colors.red, neutral=colors.yellow
  },
  Neon = {
    bg=colors.black, fg=colors.white, frame=colors.magenta,
    titleBg=colors.purple, titleFg=colors.white, statusBg=colors.gray, statusFg=colors.white,
    hlBg=colors.lime, hlFg=colors.black, btnNum=colors.yellow, accent=colors.pink,
    good=colors.lime, bad=colors.red, neutral=colors.lightBlue
  },
  Forest = {
    bg=colors.black, fg=colors.white, frame=colors.green,
    titleBg=colors.green, titleFg=colors.black, statusBg=colors.lime, statusFg=colors.black,
    hlBg=colors.brown, hlFg=colors.white, btnNum=colors.yellow, accent=colors.lime,
    good=colors.green, bad=colors.red, neutral=colors.orange
  },
  Mono = {
    bg=colors.black, fg=colors.white, frame=colors.white,
    titleBg=colors.black, titleFg=colors.white, statusBg=colors.black, statusFg=colors.white,
    hlBg=colors.white, hlFg=colors.black, btnNum=colors.white, accent=colors.gray,
    good=colors.white, bad=colors.white, neutral=colors.white
  },
}

-- aktuelle Config (Theme, Textscale)
local CONFIG = {
  theme = "Ocean",
  textScale = 0,    -- 0 = auto
}

-- Save/Load für CONFIG
local function saveConfig()
  local h = fs.open(CONFIG_FILE,"w"); h.write(textutils.serialize(CONFIG)); h.close()
end
local function loadConfig()
  if not fs.exists(CONFIG_FILE) then return false end
  local h = fs.open(CONFIG_FILE,"r"); local s=h.readAll(); h.close()
  local ok,t = pcall(textutils.unserialize, s)
  if ok and type(t)=="table" then
    for k,v in pairs(t) do CONFIG[k]=v end
    return true
  end
  return false
end
loadConfig()

----------------------------------------------------------------
-- Term/Draw Helpers
----------------------------------------------------------------
local function setc(fg,bg) if fg then term.setTextColor(fg) end; if bg then term.setBackgroundColor(bg) end end
local function clear(bg) setc(nil, bg); term.clear(); term.setCursorPos(1,1) end

-- Auto-TextScale: skaliert so, dass ~ 90×30 Zeichen grob reinpassen, aber klemmt zwischen 0.5 und 3.0
local function autoTextScale()
  local function setScaleTry(s) mon.setTextScale(s); return term.getSize() end
  local targetW, targetH = 90, 30
  local bestS, bestDiff = 1.0, 1e9
  for s=0.5,3.0,0.5 do
    local w,h = setScaleTry(s)
    local d = math.abs(w-targetW)+math.abs(h-targetH)
    if d < bestDiff then bestDiff, bestS = d, s end
  end
  mon.setTextScale(bestS)
end

if CONFIG.textScale == 0 then autoTextScale() else mon.setTextScale(CONFIG.textScale) end
local W,H = term.getSize()

local function hline(y,x1,x2,ch,fg,bg)
  setc(fg, bg); term.setCursorPos(x1,y); term.write(string.rep(ch or " ", math.max(0,x2-x1+1)))
end
local function drawBox(x1,y1,x2,y2, fg, bg)
  for y=y1,y2 do hline(y,x1,x2," ",nil,bg) end
  setc(fg,bg)
  term.setCursorPos(x1,y1); term.write("+"); term.setCursorPos(x2,y1); term.write("+")
  term.setCursorPos(x1,y2); term.write("+"); term.setCursorPos(x2,y2); term.write("+")
  for x=x1+1,x2-1 do term.setCursorPos(x,y1); term.write("-"); term.setCursorPos(x,y2); term.write("-") end
  for y=y1+1,y2-1 do term.setCursorPos(x1,y); term.write("|"); term.setCursorPos(x2,y); term.write("|") end
end
local function cx(text) return math.floor((W-#text)/2)+1 end
local function writeCentered(y,text,fg,bg) setc(fg,bg) term.setCursorPos(cx(text),y) term.write(text) end
local function wrapText(s,width)
  local lines={}
  s=tostring(s or "")
  for paragraph in s:gmatch("([^\n]+)\n?") do
    local line=""
    for word in paragraph:gmatch("%S+") do
      if #line==0 then
        if #word<=width then line=word else local i=1; while i<=#word do table.insert(lines, word:sub(i,i+width-1)); i=i+width end end
      else
        if #line + 1 + #word <= width then line=line.." "..word
        else table.insert(lines,line); if #word<=width then line=word else local i=1; while i<=#word do table.insert(lines, word:sub(i,i+width-1)); i=i+width end; line="" end end
      end
    end
    if #line>0 then table.insert(lines,line) end
  end
  if #lines==0 then table.insert(lines,"") end
  return lines
end

----------------------------------------------------------------
-- Animationen
----------------------------------------------------------------
local function wipe(theme, delay)
  delay = delay or 0.005
  for x=1,W do
    for y=1,H do term.setCursorPos(x,y); setc(nil, theme.accent); term.write(" ") end
    sleep(delay)
  end
end

local function typewriter(theme, text, x1,y1,x2,y2, speed)
  local width=x2-x1+1; local lines=wrapText(text,width)
  local y=y1; speed=speed or 0.005
  setc(theme.fg, theme.bg)
  for _,ln in ipairs(lines) do
    if y>y2 then break end
    term.setCursorPos(x1,y)
    for i=1,#ln do term.write(ln:sub(i,i)); sleep(speed) end
    y=y+1
  end
end

local function confetti(theme, duration)
  local t0=os.clock()
  local cols={theme.good, theme.neutral, theme.accent, theme.bad}
  while os.clock()-t0<duration do
    local x=math.random(1,W); local y=math.random(1,H)
    setc(nil, cols[math.random(#cols)]); term.setCursorPos(x,y); term.write(" ")
    sleep(0.002)
  end
end

----------------------------------------------------------------
-- Buttons / Eingabe
----------------------------------------------------------------
local buttons = {} -- {x1,y1,x2,y2,label,idx}
local function makeButtons(x1,y1,x2,y2, options)
  buttons={}
  local height=y2-y1+1; local per=#options; if per<1 then return end
  local lineH=math.max(3, math.floor(height/per))
  local y=y1
  for i,opt in ipairs(options) do
    local bY2=math.min(y2, y+lineH-1)
    table.insert(buttons, {x1,y,bY2 and x2 or x2,y,bY2,opt.label,i,opt.hint})
    y=bY2+1
  end
end
local function drawButtons(theme)
  for _,b in ipairs(buttons) do
    drawBox(b[1],b[2],b[3],b[4], theme.frame, theme.bg)
    local label = tostring(b[6])..") "..(b[5] or "")
    local midY = math.floor((b[2]+b[4])/2)
    setc(theme.btnNum, theme.bg); term.setCursorPos(cx(label), midY); term.write(tostring(b[6]))
    setc(theme.fg, theme.bg);    term.setCursorPos(cx(label)+2, midY); term.write(") "..(b[5] or ""))
  end
end
local function waitChoice()
  while true do
    local e,a,b,c = os.pullEvent()
    if e=="monitor_touch" then
      jingle_click()
      local mx,my=b,c
      for _,bt in ipairs(buttons) do
        if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then return bt[6] end
      end
    elseif e=="key" then
      if a>=keys.one and a<=keys.nine then return (a-keys.one)+1 end
      if a==keys.enter or a==keys.numPadEnter then return 1 end
    end
  end
end

----------------------------------------------------------------
-- Layout
----------------------------------------------------------------
local FRAME = { titleH=3, statusH=2 }
local function drawLayout(theme, title, left, right)
  hline(1,1,W," ", nil, theme.titleBg); hline(2,1,W," ", nil, theme.titleBg)
  writeCentered(1, title, theme.titleFg, theme.titleBg)
  drawBox(1, FRAME.titleH, W, H-FRAME.statusH, theme.frame, theme.bg)
  hline(H-1,1,W," ", nil, theme.statusBg); hline(H,1,W," ", nil, theme.statusBg)
  setc(theme.statusFg, theme.statusBg); term.setCursorPos(2,H-1); term.write(left or "")
  if right and #right>0 then term.setCursorPos(W-#right-1, H-1); term.write(right) end
end

----------------------------------------------------------------
-- Savegame
----------------------------------------------------------------
local state = { courage=0, wisdom=0, empathy=0, scene="intro" }

local function saveGame()
  local h=fs.open(SAVE_FILE,"w")
  h.write(textutils.serialize({state=state, config=CONFIG}))
  h.close()
end

local function loadGame()
  if not fs.exists(SAVE_FILE) then return false end
  local h=fs.open(SAVE_FILE,"r"); local s=h.readAll(); h.close()
  local ok,t = pcall(textutils.unserialize, s)
  if ok and type(t)=="table" and type(t.state)=="table" then
    state = t.state
    if type(t.config)=="table" then for k,v in pairs(t.config) do CONFIG[k]=v end end
    return true
  end
  return false
end

local function deleteSave()
  if fs.exists(SAVE_FILE) then fs.delete(SAVE_FILE) end
end

----------------------------------------------------------------
-- Story / Szenen
----------------------------------------------------------------
local function theme() return THEMES[CONFIG.theme] or THEMES.Ocean end

local scenes = {
  intro = {
    title="Die Flüsternde Ruine",
    text ="Du stehst vor den Toren einer uralten Ruine. Legenden erzählen von einer Stimme, die nur denjenigen antwortet, die wahrhaft fragen.",
    options={
      {label="Mutig eintreten",        effect=function() state.courage=state.courage+1 end, next="hall"},
      {label="Erst das Gelände prüfen", effect=function() state.wisdom=state.wisdom+1 end, next="courtyard"},
    }
  },
  courtyard = {
    title="Hof der Schatten",
    text ="Im Hof findest du Inschriften, halb überwuchert. Eine Markierung zeigt nach Osten. Leise hörst du ein Summen aus der Tiefe.",
    options={
      {label="Inschriften entziffern", effect=function() state.wisdom=state.wisdom+1 end, next="riddle1"},
      {label="Dem Summen folgen",      effect=function() state.courage=state.courage+1 end, next="hall"},
    }
  },
  hall = {
    title="Halle der Echos",
    text ="Deine Schritte hallen. In der Ferne glimmt blaues Licht. Eine steinerne Tür fragt: „Was suchst du?“",
    options={
      {label="Macht",        effect=function() end, next="riddle2"},
      {label="Wissen",       effect=function() state.wisdom=state.wisdom+1 end, next="riddle2"},
      {label="Heilung für andere", effect=function() state.empathy=state.empathy+1 end, next="riddle2"},
    }
  },
  riddle1 = {
    title="Erste Frage",
    text ="„Was ist die leise Kraft, die Mauern ohne Hände versetzt?“",
    options={
      {label="Zeit",   effect=function() state.wisdom=state.wisdom+1 end, next="hall"},
      {label="Stille", effect=function() end, next="hall"},
      {label="Wind",   effect=function() end, next="hall"},
    }
  },
  riddle2 = {
    title="Zweite Frage",
    text ="„Was macht einen Boten würdig?“",
    options={
      {label="Furchtlosigkeit", effect=function() state.courage=state.courage+1 end, next="final"},
      {label="Verstehen",       effect=function() state.wisdom=state.wisdom+1 end,   next="final"},
      {label="Mitgefühl",       effect=function() state.empathy=state.empathy+1 end, next="final"},
    }
  },
  final = {
    title="Entscheidung der Ruine",
    text = function() return ("Werte – Mut:%d  Verstand:%d  Mitgefühl:%d"):format(state.courage,state.wisdom,state.empathy) end,
    options={ {label="Antworte der Ruine …", next="ending"} }
  },
}

local function endingKind()
  if state.empathy >= state.courage and state.empathy >= state.wisdom then return "good"
  elseif state.wisdom >= state.courage then return "neutral" else return "bad" end
end

----------------------------------------------------------------
-- Szenen-Renderer
----------------------------------------------------------------
local function showScene(id)
  local th = theme()
  local sc = scenes[id]; if not sc then return end
  state.scene = id

  clear(th.bg)
  drawLayout(th, "ENTERTAINMENT STATION", ("Mut:%d  Verstand:%d  Mitgefühl:%d"):format(state.courage,state.wisdom,state.empathy), "Touch: Auswahl | 1..9")

  local x1,y1 = 3, FRAME.titleH+1
  local x2,y2 = W-2, H-FRAME.statusH-1
  local optH = math.min(12, y2-y1-3)
  local textBottom = y2 - optH - 1

  local title = type(sc.title)=="function" and sc.title() or sc.title
  writeCentered(y1, title, th.titleFg, th.titleBg)
  drawBox(x1, y1+1, x2, textBottom, th.frame, th.bg)
  typewriter(th, type(sc.text)=="function" and sc.text() or sc.text, x1+2, y1+2, x2-1, textBottom-1, 0.002)

  local opts = sc.options or {}
  makeButtons(x1, textBottom+2, x2, y2, opts); drawButtons(th)

  local idx = waitChoice(); idx = math.max(1, math.min(idx, #opts))
  local choice = opts[idx]
  if choice and choice.effect then pcall(choice.effect) end

  saveGame()
  wipe(th, 0.002)

  if choice and choice.next then
    if choice.next == "ending" then
      local k = endingKind()
      clear(th.bg)
      if k=="good" then
        drawLayout(th, "ANTWORT DER RUINE", "Pfad der Heilung", "")
        writeCentered(math.floor(H/2)-2, "Die Ruine öffnet ein Tor aus Licht.", th.good)
        writeCentered(math.floor(H/2),   "„Wer für andere bittet, ist willkommen.“", th.good)
        confetti(th, 2.2); jingle_success()
      elseif k=="neutral" then
        drawLayout(th, "ANTWORT DER RUINE", "Pfad des Verstehens", "")
        writeCentered(math.floor(H/2)-2, "Die Steine erzählen dir die Geschichte.", th.neutral)
        writeCentered(math.floor(H/2),   "Wissen wiegt schwer – trage es weise.", th.neutral)
        confetti(th, 1.2)
      else
        drawLayout(th, "ANTWORT DER RUINE", "Pfad des Mutes", "")
        writeCentered(math.floor(H/2)-2, "Die Tür weicht, doch die Tiefe prüft dich.", th.bad)
        writeCentered(math.floor(H/2),   "Mut ohne Ziel ist nur Lärm im Dunkeln.", th.bad)
        confetti(th, 1.6)
      end
      writeCentered(H-3, "Tippe, um erneut zu spielen", th.fg)
      saveGame()
      while true do local e=os.pullEvent(); if e=="monitor_touch" or e=="key" then break end end
      state = { courage=0, wisdom=0, empathy=0, scene="intro" }
      saveGame()
      wipe(th, 0.002)
      return showScene("intro")
    else
      return showScene(choice.next)
    end
  end
end

----------------------------------------------------------------
-- Theme-Menü
----------------------------------------------------------------
local function themeMenu()
  local names = {}
  for k,_ in pairs(THEMES) do table.insert(names, k) end
  table.sort(names)
  local th = theme()
  while true do
    clear(th.bg)
    drawLayout(th, "THEME AUSWÄHLEN", "Touch/1..9 zum Wechseln", "Zurück: [Q]")
    local x1,y1 = 3, FRAME.titleH+1
    local x2,y2 = W-2, H-FRAME.statusH-1
    local opt = {}
    for i,n in ipairs(names) do table.insert(opt, {label=n}) end
    makeButtons(x1,y1+6, x2, y2, opt); drawButtons(th)

    -- Vorschau-Balken
    drawBox(x1, y1, x2, y1+4, th.frame, th.bg)
    writeCentered(y1+1, "Vorschau", th.titleFg, th.titleBg)
    writeCentered(y1+3, "Aktuell: "..CONFIG.theme, th.fg, th.bg)

    local choice = waitChoice()
    local pick = names[choice]; if not pick then return end
    CONFIG.theme = pick; saveConfig(); th = theme(); jingle_click()
  end
end

----------------------------------------------------------------
-- Einstellungen: Textgröße (optional)
----------------------------------------------------------------
local function scaleMenu()
  local th = theme()
  local scales = {0.5,1.0,1.5,2.0,2.5,3.0}
  while true do
    clear(th.bg)
    drawLayout(th, "TEXTGRÖSSE", "Wähle Skalierung (0=Auto)", "Zurück: [Q]")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opt={}
    table.insert(opt,{label="Auto (empfohlen)"})
    for _,s in ipairs(scales) do table.insert(opt,{label=("Skalierung %.1f"):format(s)}) end
    makeButtons(x1,y1+2,x2,y2,opt); drawButtons(th)
    local c = waitChoice()
    if c==1 then CONFIG.textScale=0; saveConfig(); autoTextScale(); W,H=term.getSize(); return
    else
      local idx=c-1; if scales[idx] then CONFIG.textScale=scales[idx]; saveConfig(); mon.setTextScale(scales[idx]); W,H=term.getSize(); return end
    end
  end
end

----------------------------------------------------------------
-- Hauptmenü
----------------------------------------------------------------
local function splash(th)
  clear(th.bg)
  hline(1,1,W," ", nil, th.titleBg); hline(2,1,W," ", nil, th.titleBg)
  writeCentered(1, "ENTERTAINMENT STATION", th.titleFg, th.titleBg)
  writeCentered(math.floor(H/2)-1, "Die Flüsternde Ruine", th.accent)
  writeCentered(math.floor(H/2)+1, "Tippe um zu beginnen", th.fg)
  while true do local e=os.pullEvent(); if e=="monitor_touch" or e=="key" then break end end
end

local function mainMenu()
  local th = theme()
  splash(th)
  while true do
    th = theme()
    clear(th.bg)
    drawLayout(th, "HAUPTMENÜ", "Wähle eine Option", "")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1

    local hasSave = fs.exists(SAVE_FILE)
    local opts = {}
    if hasSave then table.insert(opts,{label="Fortsetzen"}) end
    table.insert(opts,{label="Neues Spiel"})
    table.insert(opts,{label="Theme auswählen"})
    table.insert(opts,{label="Textgröße"})
    if hasSave then table.insert(opts,{label="Spielstand löschen"}) end
    table.insert(opts,{label="Beenden"})

    makeButtons(x1,y1+2,x2,y2,opts); drawButtons(th)
    local c = waitChoice()
    local idx=1

    if hasSave then
      if c==idx then
        if loadGame() then jingle_click(); wipe(th,0.002); return showScene(state.scene or "intro")
        else jingle_click(); wipe(th,0.002); return showScene("intro") end
      end
      idx=idx+1
    end

    -- Neues Spiel
    if c==idx then
      state = {courage=0,wisdom=0,empathy=0,scene="intro"}
      saveGame(); jingle_click(); wipe(th,0.002); return showScene("intro")
    end
    idx=idx+1

    -- Theme
    if c==idx then jingle_click(); themeMenu(); th=theme(); end
    idx=idx+1

    -- Textgröße
    if c==idx then jingle_click(); scaleMenu(); th=theme(); end
    idx=idx+1

    -- Reset Save
    if hasSave and c==idx then
      jingle_click()
      clear(th.bg); drawLayout(th,"BESTÄTIGUNG","Spielstand löschen?","1=Ja  2=Nein")
      makeButtons(3,FRAME.titleH+4,W-2,H-FRAME.statusH-1,{{label="Ja, löschen"},{label="Nein, zurück"}}); drawButtons(th)
      local cc=waitChoice()
      if cc==1 then deleteSave(); jingle_click(); writeCentered(math.floor(H/2), "Gelöscht.", th.bad); sleep(0.6) end
    elseif (not hasSave and c==idx) or (hasSave and c==idx+1) then
      -- Beenden
      break
    end
  end
end

----------------------------------------------------------------
-- Run
----------------------------------------------------------------
math.randomseed(os.epoch("utc") % 2^31)
local ok,err = pcall(mainMenu)
if not ok then
  term.redirect(oldTerm); term.setCursorBlink(true)
  print("Fehler:", tostring(err))
else
  term.redirect(oldTerm); term.setCursorBlink(true)
end
