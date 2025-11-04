-- entertainment_v3.lua  (v3.7 – stats back button, keyboard no-overlap, global collision helper, reset settings)
-- CC:Tweaked – Entertainment Station Story Adventure
-- ASCII-safe (keine Umlaute im Code), Touch-first

-------------------- FILES / CONFIG --------------------
local SAVE_PREFIX="ent_v3_save"   -- ent_v3_save1..3
local CONFIG_FILE="ent_v3_config"
local QUOTE_DIR="ent_v3_quotes"

-------------------- PERIPHERALS -----------------------
local function findBiggestMonitor()
  local mons={}
  if peripheral and peripheral.find then
    for _,m in ipairs({peripheral.find("monitor")}) do table.insert(mons,m) end
  end
  if #mons==0 then return nil end
  local best,area=nil,-1
  for _,m in ipairs(mons) do local w,h=m.getSize(); if w*h>area then best,area=m,w*h end end
  return best
end

local mon=findBiggestMonitor()
if not mon then print("Kein Monitor gefunden (advanced monitor anschliessen)."); return end
local oldTerm=term.redirect(mon); term.setCursorBlink(false)

local speaker=peripheral.find and peripheral.find("speaker") or nil
local function sfx_ok() return speaker~=nil end
local function playSound(id,vol,pit)
  if not sfx_ok() then return end
  pcall(function() speaker.playSound(id,{volume=vol or 0.7,pitch=pit or 1.0}) end)
end

-------------------- GLOBAL STATE ----------------------
local DEFAULT_CONFIG={
  theme="Ocean",textScale=0,shader=true,
  music=0.4,sfx=0.8,master=1.0,mute=false,
  touchKeyboardEnabled=true,
  kbScale=1.0
}
local CONFIG={}
for k,v in pairs(DEFAULT_CONFIG) do CONFIG[k]=v end

-- Themes
local THEMES={
  Ocean ={bg=colors.black,fg=colors.white,frame=colors.gray,titleBg=colors.blue,titleFg=colors.white,statusBg=colors.gray,statusFg=colors.white,hlBg=colors.cyan,hlFg=colors.black,btnNum=colors.yellow,accent=colors.lightBlue,good=colors.green,bad=colors.red,neutral=colors.orange},
  Sunset={bg=colors.black,fg=colors.white,frame=colors.orange,titleBg=colors.orange,titleFg=colors.black,statusBg=colors.brown,statusFg=colors.white,hlBg=colors.red,hlFg=colors.white,btnNum=colors.yellow,accent=colors.orange,good=colors.orange,bad=colors.red,neutral=colors.yellow},
  Neon  ={bg=colors.black,fg=colors.white,frame=colors.magenta,titleBg=colors.magenta,titleFg=colors.white,statusBg=colors.magenta,statusFg=colors.white,hlBg=colors.lime,hlFg=colors.black,btnNum=colors.yellow,accent=colors.pink,good=colors.lime,bad=colors.red,neutral=colors.lightBlue},
  Forest={bg=colors.black,fg=colors.white,frame=colors.green,titleBg=colors.green,titleFg=colors.black,statusBg=colors.lime,statusFg=colors.black,hlBg=colors.brown,hlFg=colors.white,btnNum=colors.yellow,accent=colors.lime,good=colors.green,bad=colors.red,neutral=colors.orange},
  Mono  ={bg=colors.black,fg=colors.white,frame=colors.white,titleBg=colors.black,titleFg=colors.white,statusBg=colors.black,statusFg=colors.white,hlBg=colors.white,hlFg=colors.black,btnNum=colors.white,accent=colors.gray,good=colors.white,bad=colors.white,neutral=colors.white},
  Midnight={bg=colors.black,fg=colors.lightBlue,frame=colors.blue,titleBg=colors.blue,titleFg=colors.white,statusBg=colors.gray,statusFg=colors.white,hlBg=colors.lightBlue,hlFg=colors.black,btnNum=colors.yellow,accent=colors.blue,good=colors.lightBlue,bad=colors.red,neutral=colors.gray},
  Retro   ={bg=colors.brown,fg=colors.yellow,frame=colors.orange,titleBg=colors.orange,titleFg=colors.black,statusBg=colors.brown,statusFg=colors.yellow,hlBg=colors.yellow,hlFg=colors.brown,btnNum=colors.yellow,accent=colors.orange,good=colors.yellow,bad=colors.red,neutral=colors.orange},
  Solar   ={bg=colors.yellow,fg=colors.black,frame=colors.orange,titleBg=colors.orange,titleFg=colors.black,statusBg=colors.yellow,statusFg=colors.black,hlBg=colors.white,hlFg=colors.black,btnNum=colors.black,accent=colors.orange,good=colors.green,bad=colors.red,neutral=colors.gray},
  Pastel  ={bg=colors.lightBlue,fg=colors.black,frame=colors.pink,titleBg=colors.pink,titleFg=colors.black,statusBg=colors.lightBlue,statusFg=colors.black,hlBg=colors.lime,hlFg=colors.black,btnNum=colors.black,accent=colors.pink,good=colors.lime,bad=colors.red,neutral=colors.white},
}
local function theme() return THEMES[CONFIG.theme] or THEMES.Ocean end

local state={
  slot=1, playerName="", scene="intro",
  courage=0,wisdom=0,empathy=0, level=1,xp=0,
  flags={}, decisions=0, endings={},
  playTime=0, _playTimerOn=false, _playTimerT0=0,
  playTimerEnabled=true,
  mapLoc="Gate",
  journal={summary={},quests={},loreUnlocked={},notes={}},
  inventory={}, achievements={}, autosave=true, lastRecap="",
  portraitMood="neutral", portraitTick=0,
}

-------------------- PLAYTIME --------------------------
local function _now() return math.floor(os.epoch("utc")/1000) end
local function playTimerStart()
  if not state.playTimerEnabled then return end
  if state._playTimerOn then return end
  state._playTimerOn=true
  state._playTimerT0=_now()
end
local function playTimerStop()
  if not state._playTimerOn then return end
  state.playTime=state.playTime+math.max(0,_now()-state._playTimerT0)
  state._playTimerOn=false
end
local function playTimerReset() playTimerStop(); state.playTime=0 end

-------------------- SAVE / LOAD CONFIG ----------------
local function saveConfig()
  local h=fs.open(CONFIG_FILE,"w"); if not h then return end
  h.write(textutils.serialize(CONFIG)); h.close()
end
local function loadConfig()
  if not fs.exists(CONFIG_FILE) then return end
  local h=fs.open(CONFIG_FILE,"r"); local s=h.readAll(); h.close()
  local ok,t=pcall(textutils.unserialize,s)
  if ok and type(t)=="table" then for k,v in pairs(t) do CONFIG[k]=v end end
end
local function resetConfigToDefaults()
  for k,_ in pairs(CONFIG) do CONFIG[k]=nil end
  for k,v in pairs(DEFAULT_CONFIG) do CONFIG[k]=v end
  saveConfig()
end

loadConfig()

-- TextScale
local function applyAutoScale()
  local targetW,targetH=90,30; local bestS,bestDiff=1.0,1e9
  for s=0.5,3.0,0.5 do mon.setTextScale(s); local w,h=term.getSize(); local d=math.abs(w-targetW)+math.abs(h-targetH); if d<bestDiff then bestDiff,bestS=d,s end end
  mon.setTextScale(bestS); CONFIG.textScale=0
end

if CONFIG.textScale==0 then applyAutoScale() else mon.setTextScale(CONFIG.textScale) end
local W,H=term.getSize()

-------------------- DRAW HELPERS ----------------------
local function setc(fg,bg) if fg then term.setTextColor(fg) end; if bg then term.setBackgroundColor(bg) end end
local function hline(y,x1,x2,ch,fg,bg) setc(fg,bg); term.setCursorPos(x1,y); term.write(string.rep(ch or " ", math.max(0,x2-x1+1))) end
local function clear(bg) setc(nil,bg or theme().bg); term.clear(); term.setCursorPos(1,1) end
local function drawBox(x1,y1,x2,y2,fg,bg)
  for y=y1,y2 do hline(y,x1,x2," ",nil,bg) end
  setc(fg,bg)
  term.setCursorPos(x1,y1); term.write("+"); term.setCursorPos(x2,y1); term.write("+")
  term.setCursorPos(x1,y2); term.write("+"); term.setCursorPos(x2,y2); term.write("+")
  for x=x1+1,x2-1 do term.setCursorPos(x,y1); term.write("-"); term.setCursorPos(x,y2); term.write("-") end
  for y=y1+1,y2-1 do term.setCursorPos(x1,y); term.write("|"); term.setCursorPos(x2,y); term.write("|") end
end
local function cx(text) return math.floor((W-#(text or ""))/2)+1 end
local function writeCentered(y,text,fg,bg) setc(fg,bg); term.setCursorPos(cx(text or ""),y); term.write(text or "") end

local function shaderPass()
  if not CONFIG.shader then return end
  local th=theme()
  for y=4,H-2 do local shade=(y%4==0) and th.statusBg or th.bg; hline(y,2,W-1," ",nil,shade) end
end

-------------------- COLLISION / LAYOUT UTILS ----------
local function rectOverlap(a,b)
  return not (a[3]<b[1] or b[3]<a[1] or a[4]<b[2] or b[4]<a[2])
end

-- Try place rect at preferred, else try candidates; returns chosen rect
local function placeNonOverlapping(preferred, occupied, candidates)
  local function ok(r)
    for _,o in ipairs(occupied) do if rectOverlap(r,o) then return false end end
    return true
  end
  if ok(preferred) then return preferred end
  for _,cand in ipairs(candidates or {}) do if ok(cand) then return cand end end
  return preferred -- worst case
end

-------------------- BUTTONS / TOUCH -------------------
local buttons={}
local function _truncateToWidth(s, w) if #s<=w then return s end if w<=1 then return string.sub(s,1,1) end return string.sub(s,1,math.max(0,w-1)).."…" end
local function makeButtons(x1,y1,x2,y2,options)
  buttons={}
  local height=y2-y1+1
  local per=math.max(1,#options)
  local lineH=math.max(3, math.floor(height/per))
  local y=y1
  for i,opt in ipairs(options) do
    local y2b=math.min(y2,y+lineH-1)
    table.insert(buttons,{x1,y,x2,y2b,opt.label or "",i,opt.hint,opt.id})
    y=y2b+1
  end
end
local function drawButtons(th)
  for _,b in ipairs(buttons) do
    local x1,y1,x2,y2,label,idx=b[1],b[2],b[3],b[4],b[5],b[6]
    drawBox(x1,y1,x2,y2,th.frame,th.bg)
    local mid=math.floor((y1+y2)/2)
    local maxLabel = math.max(1, (x2 - x1) - 6)
    setc(th.btnNum,th.bg); term.setCursorPos(x1+2,mid); term.write(tostring(idx)..") ")
    setc(th.fg,th.bg); term.write(_truncateToWidth(label,maxLabel))
  end
end
local function drawScrollButtons(th, x2, yTop, yBottom)
  local up={x2-4,yTop,x2-1,yTop+2}
  local dn={x2-4,yBottom-2,x2-1,yBottom}
  drawBox(up[1],up[2],up[3],up[4],th.frame,th.bg); term.setCursorPos(up[1]+1,up[2]+1); setc(th.fg,th.bg); term.write("^")
  drawBox(dn[1],dn[2],dn[3],dn[4],th.frame,th.bg); term.setCursorPos(dn[1]+1,dn[2]+1); term.write("v")
  return up,dn
end
local function inRect(mx,my,r) return mx>=r[1] and mx<=r[3] and my>=r[2] and my<=r[4] end

-------------------- LAYOUT ----------------------------
local FRAME={titleH=3,statusH=2}
local function drawLayout(title,left,right)
  local th=theme()
  hline(1,1,W," ",nil,th.titleBg); hline(2,1,W," ",nil,th.titleBg)
  writeCentered(1,title or "ENTERTAINMENT STATION",th.titleFg,th.titleBg)
  drawBox(1,FRAME.titleH,W,H-FRAME.statusH,th.frame,th.bg)
  hline(H-1,1,W," ",nil,th.statusBg); hline(H,1,W," ",nil,th.statusBg)
  setc(th.statusFg,th.statusBg); term.setCursorPos(2,H-1); term.write(left or "")
  if right and #right>0 then term.setCursorPos(W-#right-1,H-1); term.write(right) end
  shaderPass()
end
local function drawBackButton(th,x1,y2,label)
  local bx1,by1=x1,y2-2; local bx2=bx1+14; local by2=y2
  drawBox(bx1,by1,bx2,by2,th.frame,th.bg); term.setCursorPos(bx1+2,by1+1); setc(th.fg,th.bg); term.write(label or "< Zurueck")
  return {bx1,by1,bx2,by2}
end

-------------------- SAVE / LOAD -----------------------
local function savePath(slot) return SAVE_PREFIX..tostring(slot) end
local function save(slot)
  playTimerStop()
  local h=fs.open(savePath(slot),"w"); if not h then return false end
  h.write(textutils.serialize({state=state,config=CONFIG})); h.close()
  return true
end
local function load(slot)
  if not fs.exists(savePath(slot)) then return false end
  local h=fs.open(savePath(slot),"r"); local s=h.readAll(); h.close()
  local ok,t=pcall(textutils.unserialize,s)
  if ok and type(t)=="table" and t.state then
    state=t.state; if t.config then for k,v in pairs(t.config) do CONFIG[k]=v end end
    state.slot=slot; state._playTimerOn=false; state._playTimerT0=0
    return true
  end
  return false
end
local function deleteSave(slot) if fs.exists(savePath(slot)) then fs.delete(savePath(slot)) end end

-------------------- MUSIC TICK ------------------------
local function musicTick() if CONFIG.mute or CONFIG.music<=0 or not sfx_ok() then return end; playSound("minecraft:music.menu",CONFIG.music*CONFIG.master,1.0) end

-------------------- ACHIEVEMENTS ----------------------
local ACH={
  firstChoice={name="First Step",desc="Erste Entscheidung getroffen."},
  lore1={name="Archivist",desc="Erster Lore-Eintrag."},
  endingAny={name="Closure",desc="Ein Ende erreicht."},
  secret={name="Hidden Path",desc="Geheimes Kapitel betreten."},
}
local function unlock(id)
  if state.achievements[id] then return end
  state.achievements[id]=true
  local th=theme(); local boxW=math.min(36,W-4); local x1=W-boxW-1; local y1=H-7; local x2=W-1; local y2=H-2
  drawBox(x1,y1,x2,y2,th.frame,th.bg)
  term.setCursorPos(x1+2,y1+1); setc(th.good,th.bg); term.write("Achievement")
  term.setCursorPos(x1+2,y1+3); setc(th.fg,th.bg); term.write(_truncateToWidth(ACH[id].name, boxW-6))
  term.setCursorPos(x1+2,y1+4); term.write(_truncateToWidth(ACH[id].desc, boxW-6))
  playSound("minecraft:entity.experience_orb.pickup",CONFIG.sfx*CONFIG.master,1.2)
  sleep(1.1)
end

-------------------- JOURNAL / ITEMS -------------------
local function journalAdd(t) table.insert(state.journal.summary,t) end
local function questAdd(id,txt) state.journal.quests[id]={text=txt,done=false} end
local function questDone(id) if state.journal.quests[id] then state.journal.quests[id].done=true end end
local LORE={runeShard={name="Runen-Splitter",text="Ein Bruchstueck, das leise vibriert."}, echoLeaf={name="Echoblatt",text="Adern wie Wellen."}}
local function addItem(k) state.inventory[k]=(state.inventory[k] or 0)+1; state.journal.loreUnlocked[k]=true; unlock("lore1") end

-------------------- MAP -------------------------------
local MAP={nodes={Gate={x=10,y=8,label="Tor"},Court={x=30,y=10,label="Hof"},Hall={x=50,y=8,label="Halle"},Depth={x=70,y=12,label="Tiefe"},Secret={x=40,y=16,label="Geheim"}}, paths={{"Gate","Court"},{"Court","Hall"},{"Hall","Depth"},{"Court","Secret"}}}
local function waitBackOrTouch(backRect) while true do local e,a,b,c=os.pullEvent(); if e=="monitor_touch" then if b>=backRect[1] and b<=backRect[3] and c>=backRect[2] and c<=backRect[4] then return true end elseif e=="key" and (a==keys.back or a==keys.enter) then return true end end end
local function drawMap()
  local th=theme(); clear(th.bg); drawLayout("Weltkarte","Tippe: zurueck","")
  local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
  drawBox(x1,y1,x2,y2,th.frame,th.bg)
  for _,p in ipairs(MAP.paths) do
    local a=MAP.nodes[p[1]]; local b=MAP.nodes[p[2]]
    local ax=x1+a.x; local ay=y1+a.y; local bx=x1+b.x; local by=y1+b.y
    local steps=math.max(1,math.abs(bx-ax))
    for i=0,steps do local xx=ax+math.floor(i*(bx-ax)/steps); local yy=ay+math.floor((by-ay)*i/steps); term.setCursorPos(xx,yy); setc(theme().neutral,theme().bg); term.write("*") end
  end
  for _,n in pairs(MAP.nodes) do term.setCursorPos(x1+n.x,y1+n.y); setc(theme().fg,theme().bg); term.write("O"); term.setCursorPos(x1+n.x+2,y1+n.y); term.write(n.label) end
  local cur=MAP.nodes[state.mapLoc] or MAP.nodes.Gate; term.setCursorPos(x1+cur.x,y1+cur.y); setc(theme().accent,theme().bg); term.write("@")
  local backRect=drawBackButton(theme(),x1,y2,"< Zurueck"); waitBackOrTouch(backRect)
end

-------------------- PORTRAIT --------------------------
local PORTRAIT={neutral={"  /\\ "," (..)","  || "}, happy={"  /\\ "," (^^)","  \\/ "}, sad={"  /\\ "," (..)","  -- "}, brave={" /\\/"," (><)"," /  \\"}}
local function drawPortrait(x,y,mood) local th=theme(); local art=PORTRAIT[mood] or PORTRAIT.neutral; for i=1,#art do term.setCursorPos(x,y+i-1); setc(th.fg,th.bg); term.write(art[i]) end end
local function setMood(m) state.portraitMood=m end

-------------------- GENERIC SCROLL PANELS -------------
local function scrollTextPanel(title, lines)
  local th=theme(); clear(th.bg); drawLayout(title,"Tippe: Scroll ^/v | < Zurueck","")
  local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
  local contentTop=y1+1; local contentBottom=y2-3
  local offset=0
  local maxRows=contentBottom-contentTop+1
  local function redraw()
    drawBox(x1,y1,x2,y2,th.frame,th.bg)
    for row=0,maxRows-1 do
      local idx=offset+row+1
      term.setCursorPos(x1+2,contentTop+row); setc(th.fg,th.bg)
      term.clearLine()
      if lines[idx] then term.setCursorPos(x1+2,contentTop+row); term.write(lines[idx]) end
    end
    drawScrollButtons(th,x2,contentTop,contentBottom)
    -- immer auch Zurueck-Button
    drawBackButton(th,x1,y2,"< Zurueck")
  end
  while true do
    redraw()
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      local up={x2-4,contentTop,x2-1,contentTop+2}
      local dn={x2-4,contentBottom-2,x2-1,contentBottom}
      local backRect={x1,y2-2,x1+14,y2}
      if inRect(mx,my,backRect) then return end
      if inRect(mx,my,up) then if offset>0 then offset=offset-1 end
      elseif inRect(mx,my,dn) then if offset+maxRows<#lines then offset=offset+1 end end
    elseif e=="key" and a==keys.back then return end
  end
end

-------------------- SETTINGS / SUBMENUS ---------------
local function themeMenu()
  local th=theme(); local names={}; for k,_ in pairs(THEMES) do table.insert(names,k) end; table.sort(names)
  local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
  local listTop=y1+6; local listBottom=y2-4
  local offset=0; local visibleRows=math.max(1, math.floor((listBottom-listTop+1)/3))
  while true do
    th=theme(); clear(th.bg); drawLayout("Theme auswaehlen","Tippe Theme | ^/v scroll | < Zurueck","")
    drawBox(x1,y1,x2,y1+4,th.frame,th.bg); writeCentered(y1+1,"Vorschau",th.titleFg,th.titleBg); writeCentered(y1+3,"Aktuell: "..CONFIG.theme,th.fg,th.bg)
    local opts={}
    for i=1,visibleRows do local idx=offset+i; if names[idx] then table.insert(opts,{label=names[idx]}) end end
    makeButtons(x1,listTop,x2-6,listBottom,opts); drawButtons(th)
    local upBtn,downBtn=drawScrollButtons(th,x2,listTop,listBottom)
    local backRect=drawBackButton(th,x1,y2,"< Zurueck")
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if inRect(mx,my,backRect) then return end
      if inRect(mx,my,upBtn)   then if offset>0 then offset=offset-1 end
      elseif inRect(mx,my,downBtn) then if offset+visibleRows<#names then offset=offset+1 end
      else for _,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then CONFIG.theme=bt[5]; saveConfig(); break end end end
    elseif e=="key" and a==keys.back then return end
  end
end

local function scaleMenu()
  local th=theme(); local scales={0.5,1.0,1.5,2.0,2.5,3.0}
  while true do
    clear(th.bg); drawLayout("Textgroesse","Tippe Option | < Zurueck","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Auto (empfohlen)"}}
    for _,s in ipairs(scales) do table.insert(opts,{label=("Skalierung %.1f"):format(s)}) end
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2,"< Zurueck")
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        local mx,my=b,c
        if inRect(mx,my,backRect) then return end
        for idx,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
          if idx==1 then applyAutoScale(); CONFIG.textScale=0; saveConfig()
          else local val=scales[idx-1]; if val then CONFIG.textScale=val; mon.setTextScale(val); saveConfig() end end
          W,H=term.getSize(); break
        end end
        break
      elseif e=="key" and a==keys.back then return end
    end
  end
end

-- Keyboard-Settings (Toggle + Scale)
local function keyboardMenu()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Keyboard-Einstellungen","Touch: Auswahl","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={
      {label="Touch-Keyboard: "..(CONFIG.touchKeyboardEnabled and "An" or "Aus")},
      {label="Keyboard Scale -"},
      {label="Keyboard Scale +"},
    }
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2,"< Zurueck")
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if inRect(mx,my,backRect) then return end
      for idx,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
        if idx==1 then CONFIG.touchKeyboardEnabled=not CONFIG.touchKeyboardEnabled; saveConfig()
        elseif idx==2 then CONFIG.kbScale=math.max(0.6, math.floor((CONFIG.kbScale-0.1)*10)/10); saveConfig()
        elseif idx==3 then CONFIG.kbScale=math.min(1.6, math.floor((CONFIG.kbScale+0.1)*10)/10); saveConfig()
        end
        break
      end end
    elseif e=="key" and a==keys.back then return end
  end
end

-- Reset Settings (keine Saves loeschen)
local function confirmDialog(title,msg)
  local th=theme(); clear(th.bg); drawLayout(title or "Bestaetigen","Tippe Auswahl","")
  local x1,y1=6,math.floor(H/2)-3; local x2=W-6; local y2=y1+6
  drawBox(x1,y1,x2,y2,th.frame,th.bg)
  term.setCursorPos(x1+2,y1+2); setc(th.fg,th.bg); term.write(msg or "Sicher?")
  local opts={{label="Ja"},{label="Nein"}}
  makeButtons(x1+2,y2-3,x2-2,y2-1,opts); drawButtons(th)
  while true do local e,a,b,c=os.pullEvent(); if e=="monitor_touch" then for i,bt in ipairs(buttons) do if b>=bt[1] and b<=bt[3] and c>=bt[2] and c<=bt[4] then return i==1 end end elseif e=="key" and (a==keys.enter or a==keys.y) then return true elseif e=="key" and (a==keys.back or a==keys.n) then return false end end
end

local function timerMenu()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Spielzeit-Timer","Touch: Auswahl","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Timer: "..(state.playTimerEnabled and "An" or "Aus")},{label="Timer zuruecksetzen"}}
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2,"< Zurueck")
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if inRect(mx,my,backRect) then return end
      for idx,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
        if idx==1 then if state.playTimerEnabled then playTimerStop(); state.playTimerEnabled=false else state.playTimerEnabled=true end
        elseif idx==2 then if confirmDialog("Reset Timer","Wirklich Timer auf 0 setzen?") then playTimerReset() end
        end
        break
      end end
    elseif e=="key" and a==keys.back then return end
  end
end

local function settingsMenu()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Einstellungen","Touch: Auswahl","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={
      {label="Theme"},
      {label="Textgroesse"},
      {label="Shader: "..(CONFIG.shader and "An" or "Aus")},
      {label="Audio (Master/Musik/SFX/Mute)"},
      {label="Keyboard-Einstellungen"},
      {label="Spielzeit-Timer"},
      {label="Einstellungen zuruecksetzen"},
      {label="< Zurueck"}
    }
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2,"< Zurueck")
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if inRect(mx,my,backRect) then return end
      for idx,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
        if idx==1 then themeMenu()
        elseif idx==2 then scaleMenu()
        elseif idx==3 then CONFIG.shader=not CONFIG.shader; saveConfig()
        elseif idx==4 then
          -- Audio Menu (inline)
          local function drawStepper(th,x,y,label,value)
            term.setCursorPos(x,y); setc(th.fg,th.bg); term.write(label)
            local minus={x+18,y,x+22,y+2}; local valb={x+24,y,x+34,y+2}; local plus={x+36,y,x+40,y+2}
            drawBox(minus[1],minus[2],minus[3],minus[4],th.frame,th.bg); term.setCursorPos(minus[1]+1,minus[2]+1); term.write("-")
            drawBox(valb[1],valb[2],valb[3],valb[4],th.frame,th.bg); term.setCursorPos(valb[1]+1,valb[2]+1); term.write(string.format("%.1f",value))
            drawBox(plus[1],plus[2],plus[3],plus[4],th.frame,th.bg); term.setCursorPos(plus[1]+1,plus[2]+1); term.write("+")
            return {minus=minus,value=valb,plus=plus}
          end
          while true do
            clear(th.bg); drawLayout("Audio","Minus/Plus, Mute, Zurueck","")
            local ax1,ay1=3,FRAME.titleH+1; local ax2,ay2=W-2,H-FRAME.statusH-1
            drawBox(ax1,ay1,ax2,ay2,th.frame,th.bg)
            local mCtl=drawStepper(th,ax1+2,ay1+2,"Master",CONFIG.master)
            local muCtl=drawStepper(th,ax1+2,ay1+6,"Musik ",CONFIG.music)
            local sCtl=drawStepper(th,ax1+2,ay1+10,"SFX   ",CONFIG.sfx)
            local muteBtn={ax2-18,ay1+2,ax2-4,ay1+4}
            drawBox(muteBtn[1],muteBtn[2],muteBtn[3],muteBtn[4],th.frame,th.bg)
            term.setCursorPos(muteBtn[1]+2, muteBtn[2]+1); term.write("Mute: "..(CONFIG.mute and "Ja" or "Nein"))
            local backRect2=drawBackButton(th,ax1,ay2,"< Zurueck")
            local e2,a2,b2,c2=os.pullEvent()
            if e2=="monitor_touch" then
              local mx,my=b2,c2; playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
              if inRect(mx,my,mCtl.minus) then CONFIG.master=math.max(0,CONFIG.master-0.1); saveConfig()
              elseif inRect(mx,my,mCtl.plus) then CONFIG.master=math.min(1,CONFIG.master+0.1); saveConfig()
              elseif inRect(mx,my,muCtl.minus) then CONFIG.music=math.max(0,CONFIG.music-0.1); saveConfig()
              elseif inRect(mx,my,muCtl.plus) then CONFIG.music=math.min(1,CONFIG.music+0.1); saveConfig()
              elseif inRect(mx,my,sCtl.minus) then CONFIG.sfx=math.max(0,CONFIG.sfx-0.1); saveConfig()
              elseif inRect(mx,my,sCtl.plus) then CONFIG.sfx=math.min(1,CONFIG.sfx+0.1); saveConfig()
              elseif inRect(mx,my,muteBtn) then CONFIG.mute=not CONFIG.mute; saveConfig()
              elseif inRect(mx,my,backRect2) then break end
            elseif e2=="key" and a2==keys.back then break end
          end
        elseif idx==5 then keyboardMenu()
        elseif idx==6 then timerMenu()
        elseif idx==7 then
          if confirmDialog("Reset Einstellungen","Alle Einstellungen auf Standard setzen? Saves bleiben erhalten.") then
            resetConfigToDefaults()
            applyAutoScale(); W,H=term.getSize()
          end
        else return end
        break
      end end
    elseif e=="key" and a==keys.back then return end
  end
end

-------------------- NAME INPUT (Touch-Keyboard) -------
local KB_ROWS={
  {"A","B","C","D","E","F","G","H","I","J"},
  {"K","L","M","N","O","P","Q","R","S","T"},
  {"U","V","W","X","Y","Z","0","1","2","3"},
  {"4","5","6","7","8","9","SPACE","BACK","OK"}
}

-- returns: string on success, nil on cancel
local function touchKeyboard(prompt, initial)
  local th=theme(); local text=initial or ""
  while true do
    clear(th.bg); drawLayout(prompt or "Eingabe","Tippe Tasten | OK | < Zurueck","")
    local x1,y1=4,FRAME.titleH+2; local x2=W-4; local y2=H-FRAME.statusH-1

    -- Anzeigezeile
    local displayRect={x1,y1,x2,y1+2}
    drawBox(displayRect[1],displayRect[2],displayRect[3],displayRect[4],th.frame,th.bg)
    term.setCursorPos(x1+2,y1+1); setc(th.fg,th.bg); term.write(_truncateToWidth(text, x2-x1-4))

    -- Live Scale controls (rechts oben)
    local scaleMinus={x2-16,y1-1,x2-10,y1+1}
    local scalePlus ={x2-8 ,y1-1,x2-2 ,y1+1}
    drawBox(scaleMinus[1],scaleMinus[2],scaleMinus[3],scaleMinus[4],th.frame,th.bg); term.setCursorPos(scaleMinus[1]+2,scaleMinus[2]+1); term.write("Scale-")
    drawBox(scalePlus[1] ,scalePlus[2] ,scalePlus[3] ,scalePlus[4] ,th.frame,th.bg); term.setCursorPos(scalePlus[1]+2 ,scalePlus[2]+1 ); term.write("Scale+")

    -- Dynamische Tasten (Auto-Fit + Scale)
    local spacing=1
    local baseW,baseH=6,3
    local keyW=math.max(3, math.floor(baseW*CONFIG.kbScale))
    local keyH=math.max(3, math.floor(baseH*CONFIG.kbScale))
    local cols=10
    local availW=(x2-x1+1)
    local maxKeyW=math.floor((availW - spacing*(cols-1))/cols)
    keyW=math.max(3, math.min(keyW, maxKeyW))
    local rows=4
    local availH=(y2-(y1+5))
    local maxKeyH=math.floor((availH - spacing*(rows-1))/rows)
    keyH=math.max(3, math.min(keyH, maxKeyH))

    -- keyboard area
    local kbX1, kbY1 = x1, y1+5
    local kbX2, kbY2 = x2, kbY1 + rows*(keyH) + (rows-1)*spacing - 1
    local occupied={displayRect, scaleMinus, scalePlus, {kbX1,kbY1,kbX2,kbY2}}

    -- Vorschlagspositionen fuer Zurueck-Button (keine Kollision)
    local pref={x1, y2-2, x1+14, y2} -- unten links
    local cand={
      {x1, kbY1-3, x1+14, kbY1-1},        -- oberhalb Tastatur
      {x1, FRAME.titleH+1, x1+14, FRAME.titleH+3}, -- unter Titel
      {x2-20, FRAME.titleH+1, x2-6, FRAME.titleH+3}, -- unter Titel rechts
    }
    local backRect=placeNonOverlapping(pref, occupied, cand)

    -- Zeichne Tasten
    local gx=kbX1; local gy=kbY1
    local keys={}
    for r=1,#KB_ROWS do
      local row=KB_ROWS[r]
      gx=kbX1
      for c=1,#row do
        local label=row[c]
        local colsR=#row
        local maxKWRow=math.floor((availW - spacing*(colsR-1))/colsR)
        local kW=math.min(keyW, maxKWRow)
        local kx1,ky1,kx2,ky2=gx,gy,gx+kW-1,gy+keyH-1
        drawBox(kx1,ky1,kx2,ky2,th.frame,th.bg)
        local lab=label; if lab=="SPACE" then lab="Space" elseif lab=="BACK" then lab="Back" end
        term.setCursorPos(kx1+1,ky1+1); term.write(_truncateToWidth(lab, (kW-2)))
        table.insert(keys,{label=label,x1=kx1,y1=ky1,x2=kx2,y2=ky2})
        gx=gx+kW+spacing
      end
      gy=gy+keyH+spacing
    end

    -- Zurueck-Button (jetzt kollisionsfrei)
    drawBox(backRect[1],backRect[2],backRect[3],backRect[4],th.frame,th.bg); term.setCursorPos(backRect[1]+2,backRect[2]+1); term.write("< Zurueck")

    -- Events
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if inRect(mx,my,backRect) then return nil end
      if inRect(mx,my,scaleMinus) then CONFIG.kbScale=math.max(0.6, math.floor((CONFIG.kbScale-0.1)*10)/10); saveConfig()
      elseif inRect(mx,my,scalePlus) then CONFIG.kbScale=math.min(1.6, math.floor((CONFIG.kbScale+0.1)*10)/10); saveConfig()
      else
        for _,k in ipairs(keys) do
          if mx>=k.x1 and mx<=k.x2 and my>=k.y1 and my<=k.y2 then
            if k.label=="SPACE" then text=text.." "
            elseif k.label=="BACK" then text=text:sub(1,math.max(0,#text-1))
            elseif k.label=="OK" then if #text>0 then return text end
            else text=text..k.label end
            break
          end
        end
      end
    elseif e=="key" and a==keys.back then return nil end
  end
end

-- askName: liefert true (gesetzt) / false (abgebrochen)
local function askName()
  if CONFIG.touchKeyboardEnabled then
    local input=touchKeyboard("Wie heisst dein Bote?", state.playerName or "")
    if input and #input>0 then state.playerName=input; return true else return false end
  else
    local th=theme(); clear(th.bg); drawLayout("Name eingeben (Tastatur)","Enter: OK | Back: Zurueck","")
    local x1,y1=10,math.floor(H/2)-2; local x2=x1+40
    drawBox(x1,y1,x2,y1+2,th.frame,th.bg); term.setCursorPos(x1+2,y1+1); setc(th.fg,th.bg)
    state.playerName=""
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="char" then if #state.playerName<20 then state.playerName=state.playerName..a; term.write(a) end
      elseif e=="key" and (a==keys.enter or a==keys.numPadEnter) then if #state.playerName>0 then return true end
      elseif e=="key" and a==keys.back then return false
      elseif e=="key" and a==keys.backspace then if #state.playerName>0 then state.playerName=state.playerName:sub(1,#state.playerName-1); term.setCursorPos(x1+2,y1+1); term.clearLine(); term.write(state.playerName) end
      end
    end
  end
end

-------------------- DIALOG / STORY ENGINE -------------
local function drawSceneFrame(title,subtitle)
  local th=theme(); clear(th.bg); drawLayout(title or "Szene",subtitle or ("Name: "..(state.playerName or "")),"M: Map  P: Pause")
  local px=W-9
  local art={ "  /\\ ", " (..)", "  || " }
  term.setCursorPos(px,FRAME.titleH+1); setc(th.fg,th.bg); term.write(art[1])
  term.setCursorPos(px,FRAME.titleH+2); term.write(art[2])
  term.setCursorPos(px,FRAME.titleH+3); term.write(art[3])
end

-- Optionen, paged + scroll
local function optionMenuPaged(x1,y1,x2,y2,options)
  local th=theme()
  local btnH=3
  local rows=math.max(1,math.floor((y2-y1+1)/btnH))
  local offset=0
  local function render()
    local view={}
    for i=1,rows do local idx=offset+i; if options[idx] then table.insert(view, options[idx]) end end
    makeButtons(x1,y1,x2-6,y2,view); drawButtons(th); drawScrollButtons(th,x2,y1,y2)
  end
  while true do
    render()
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      local up={x2-4,y1,x2-1,y1+2}
      local dn={x2-4,y2-2,x2-1,y2}
      if inRect(mx,my,up) then if offset>0 then offset=offset-1 end
      elseif inRect(mx,my,dn) then if offset+rows < #options then offset=offset+1 end
      else
        for i,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then return offset + i end end
      end
    elseif e=="key" then
      if a>=keys.one and a<=keys.nine then return offset + ((a-keys.one)+1) end
      if a==keys.back then return nil end
    end
  end
end

local function doChoice(prompt,options)
  local th=theme(); local x1,y1=3,FRAME.titleH+1; local x2,y2=W-12,H-FRAME.statusH-1
  drawBox(x1,y1,x2,y2-8,th.frame,th.bg)
  -- Text mit Scroll
  local width=(x2-1)-(x1+1)
  local function wrap(s,w)
    local lines={}; s=tostring(s or "")
    for p in s:gmatch("([^\n]+)\n?") do
      local line=""; for word in p:gmatch("%S+") do
        if #line==0 then if #word<=w then line=word else local i=1; while i<=#word do table.insert(lines,word:sub(i,i+w-1)); i=i+w end end
        else if #line+1+#word<=w then line=line.." "..word else table.insert(lines,line); if #word<=w then line=word else local i=1; while i<=#word do table.insert(lines,word:sub(i,i+w-1)); i=i+w end; line="" end end end
      end; if #line>0 then table.insert(lines,line) end
    end
    if #lines==0 then table.insert(lines,"") end
    return lines
  end
  local textLines=wrap(prompt,width)
  local textTop=y1+1; local textBottom=y2-9; local tOffset=0; local tMaxRows=textBottom-textTop+1
  local function drawText()
    for row=0,tMaxRows-1 do
      local idx=tOffset+row+1
      term.setCursorPos(x1+2,textTop+row); term.clearLine(); setc(th.fg,th.bg)
      if textLines[idx] then term.setCursorPos(x1+2,textTop+row); term.write(textLines[idx]) end
    end
    if #textLines>tMaxRows then drawScrollButtons(th,x2,textTop,textBottom) end
  end
  drawText()
  -- Optionen als Paged-Liste
  local idx = optionMenuPaged(x1,y2-7,x2,y2-1,options)
  if idx then playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master); return idx end
  return 1
end

-------------------- STATS / LEVEL ---------------------
local function addXP(n) state.xp=state.xpn or state.xp; state.xp=state.xp+n; if state.xp>=(state.level*10) then state.level=state.level+1; state.xp=0; journalAdd("Level up! Jetzt Level "..state.level) end end
local function statUp(stat,n) state[stat]=math.max(0,(state[stat] or 0)+(n or 1)) end
local function optionIf(cond,opt) if cond then return opt else return nil end end

-------------------- PUZZLES ---------------------------
local function puzzleLevers()
  drawSceneFrame("Puzzle: Hebel","Finde den richtigen")
  local correct=math.random(1,3)
  local idx=doChoice("Drei Hebel stehen vor dir. Welchen ziehst du?",{{label="Hebel 1"},{label="Hebel 2"},{label="Hebel 3"}})
  if idx==correct then journalAdd("Du hast das Hebelraetsel geloest."); addXP(5); questDone("door1"); return true else journalAdd("Falscher Hebel. Ein Grollen ertoehnt."); addXP(1); return false end
end
local function puzzleRunes()
  drawSceneFrame("Puzzle: Runen","Ordne sie richtig")
  local idx=doChoice("Ordne die Runen: A, B, C. Was ist die Mitte?",{{label="A"},{label="B"},{label="C"}})
  if idx==2 then journalAdd("Die Runen leuchten. Pfad frei."); addXP(5); return true else journalAdd("Die Runen verglimmen."); addXP(1); return false end
end

-------------------- SCENES ----------------------------
local function endingKind()
  if state.empathy>=state.courage and state.empathy>=state.wisdom then return "good"
  elseif state.wisdom>=state.courage then return "neutral"
  else return "bad" end
end

local function introCutscene()
  local th=theme(); clear(th.bg); drawLayout("Intro","Tippe um fortzufahren","")
  for i=1,5 do writeCentered(math.floor(H/2)-3+i,string.rep("*",i*6),th.accent,th.bg); sleep(0.08) end
  musicTick(); while true do local e=os.pullEvent(); if e=="monitor_touch" or e=="key" then break end end
end

local function scene_intro()
  drawSceneFrame("Die Flusternde Ruine","Willkommen, "..(state.playerName or ""))
  state.portraitMood="neutral"
  local idx=doChoice("Du stehst vor einem alten Tor. Die Luft ist kuehl. Was tust du, "..(state.playerName or "").."?",{{label="Mutig eintreten"},{label="Erst den Hof erkunden"},{label="Mit der Steinfigur sprechen"}})
  state.decisions=state.decisions+1; unlock("firstChoice")
  if idx==1 then statUp("courage",1); state.mapLoc="Hall"; journalAdd("Du bist in die Halle eingetreten."); return "hall"
  elseif idx==2 then statUp("wisdom",1); state.mapLoc="Court"; journalAdd("Du untersuchst den Hof der Schatten."); return "courtyard"
  else state.portraitMood="happy"; statUp("empathy",1); journalAdd("Die Figur fluestert: 'Suche die drei Zeichen'."); questAdd("find3","Finde drei Zeichen der Stimme"); addItem("echoLeaf"); return "courtyard" end
end

local function scene_courtyard()
  drawSceneFrame("Hof der Schatten","Kuehler Wind")
  local opts={{label="Inschriften entschluesseln"},{label="Dem Summen zur Halle folgen"}, optionIf(state.empathy>=2,{label="Einem Kind helfen (Nebenfigur)"})}
  local filtered={}; for _,o in ipairs(opts) do if o then table.insert(filtered,o) end end
  local idx=doChoice("Zwischen den Steinen sind Zeichen eingeritzt. Aus der Halle klingt ein Summen.",filtered)
  state.decisions=state.decisions+1
  if idx==1 then statUp("wisdom",1); addItem("runeShard"); state.flags.gotRune=true; journalAdd("Ein Runen-Splitter fuegt sich in deine Tasche."); return "riddle1"
  elseif idx==2 then statUp("courage",1); state.mapLoc="Hall"; return "hall"
  else state.portraitMood="happy"; statUp("empathy",1); journalAdd("Du hilfst dem Kind. Es zeigt dir eine Abkuerzung."); state.flags.shortcut=true; addXP(3); return "hall" end
end

local function scene_hall()
  drawSceneFrame("Halle der Echos","Das Summen wird lauter")
  local opts={{label="Mit der Tuer sprechen"}, optionIf(state.flags.gotRune,{label="Runen einsetzen"}), optionIf(state.courage>=2,{label="Dunklen Gang erforschen"})}
  local filtered={}; for _,o in ipairs(opts) do if o then table.insert(filtered,o) end end
  local idx=doChoice("Eine Tuer mit Symbolen wartet. Das Echo antwortet auf Fragen.",filtered)
  state.decisions=state.decisions+1
  if filtered[idx].label=="Mit der Tuer sprechen" then return "riddle2"
  elseif filtered[idx].label=="Runen einsetzen" then if puzzleRunes() then state.flags.doorOpen=true; return "final" else return "hall" end
  else if puzzleLevers() then state.mapLoc="Depth"; return "depth" else return "hall" end end
end

local function scene_riddle1()
  drawSceneFrame("Erste Frage","Pruefung des Verstandes")
  local idx=doChoice("Welche leise Kraft versetzt Mauern ohne Haende?",{{label="Zeit"},{label="Stille"},{label="Wind"}})
  if idx==1 then statUp("wisdom",1); journalAdd("Du hast die Zeit erkannt.") else journalAdd("Die Antwort gefiel der Ruine nicht.") end
  return "hall"
end

local function scene_riddle2()
  drawSceneFrame("Zweite Frage","Wuerde")
  local idx=doChoice("Was macht einen Boten wuerdig?",{{label="Furchtlosigkeit"},{label="Verstehen"},{label="Mitgefuehl"}})
  if idx==1 then statUp("courage",1) elseif idx==2 then statUp("wisdom",1) else statUp("empathy",1) end
  return "final"
end

local function scene_depth()
  drawSceneFrame("Die Tiefe","Nur schwaches Licht")
  local idx=doChoice("In der Tiefe fuehlst du eine Gegenwart.",{{label="Rufe laut (Mut)"},{label="Horche geduldig (Verstand)"},{label="Sprich sanft (Mitgefuehl)"}})
  if idx==1 then statUp("courage",1); state.portraitMood="brave"
  elseif idx==2 then statUp("wisdom",1); state.portraitMood="neutral"
  else statUp("empathy",1); state.portraitMood="happy" end
  if state.courage>=2 and state.wisdom>=2 and state.empathy>=2 then state.flags.secret=true end
  return "final"
end

local function doEnding(kind)
  local th=theme(); clear(th.bg)
  local title,msgLeft,msgRight
  if kind=="good" then title="Pfad der Heilung"; msgLeft="Du teilst Licht mit anderen."; msgRight="Empathie fuehrt dich."
  elseif kind=="neutral" then title="Pfad des Verstehens"; msgLeft="Wissen lastet, doch weist den Weg."; msgRight="Verstand haelt dich auf Kurs."
  else title="Pfad des Mutes"; msgLeft="Du schreitest voran, trotz Dunkel."; msgRight="Mut traegt dich." end
  drawLayout("ANTWORT DER RUINE",title,"")
  writeCentered(math.floor(H/2)-1,msgLeft,th.neutral)
  writeCentered(math.floor(H/2)+1,msgRight,th.neutral)
  local t0=os.clock(); local cols={th.good,th.neutral,th.accent,th.bad}
  while os.clock()-t0<1.2 do local x=math.random(1,W); local y=math.random(1,H); setc(nil, cols[math.random(#cols)]); term.setCursorPos(x,y); term.write(" ") end
  playSound("minecraft:ui.toast.challenge_complete",CONFIG.sfx*CONFIG.master,1.0)
  state.endings[kind]=true; unlock("endingAny")
  writeCentered(H-3,"Tippen um fortzufahren",th.fg); while true do local e=os.pullEvent(); if e=="monitor_touch" or e=="key" then break end end
end

local function scene_secret()
  drawSceneFrame("Geheimes Kapitel","Der verborgene Hof")
  local idx=doChoice("Ein verborgenes Tor laesst dich passieren. Willst du eintreten?",{{label="Ja"},{label="Nein"}})
  if idx==1 then journalAdd("Du betrittst den geheimen Pfad."); unlock("secret"); addXP(10); return "ending_secret" end
  return "final"
end

local function scene_final()
  if state.flags.secret and (state.courage+state.wisdom+state.empathy)>=6 then return "secret" end
  local k=endingKind(); doEnding(k); return "credits"
end

local function scene_ending_secret()
  doEnding("good")
  drawSceneFrame("Geheimer Schwur","Ein letzter Schritt")
  local _=doChoice("Du findest eine uralte Inschrift. Willst du den Schwur erneuern und die Ruine bewahren?",{{label="Ja, Schwur erneuern"},{label="Nein, weiterziehen"}})
  return "credits"
end

-------------------- HUD PANELS ------------------------
local function formatTime(sec) local m=math.floor(sec/60); local s=sec%60; return string.format("%02d:%02d",m,s) end

-- Klar sichtbarer Stats-Screen mit eigenem Back-Button
local function statsScreen()
  local th=theme(); clear(th.bg); drawLayout("Statistik","Tippe: Scroll ^/v | < Zurueck","")
  local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
  local lines={
    "Name: "..(state.playerName or ""),
    "Level: "..state.level.."  XP: "..state.xp,
    "Mut: "..state.courage.."  Verstand: "..state.wisdom.."  Mitgefuehl: "..state.empathy,
    "Entscheidungen: "..state.decisions,
    "Endings: "..(function() local c=0; for _ in pairs(state.endings) do c=c+1 end; return c end)(),
    "Spielzeit (Story): "..formatTime(state.playTime + (state._playTimerOn and (_now()-state._playTimerT0) or 0)),
    "Timer: "..(state.playTimerEnabled and "An" or "Aus"),
  }
  local contentTop=y1+1; local contentBottom=y2-3
  local offset=0
  local maxRows=(contentBottom-contentTop+1)
  local function redraw()
    drawBox(x1,y1,x2,y2,th.frame,th.bg)
    for row=0,maxRows-1 do
      local idx=offset+row+1
      term.setCursorPos(x1+2,contentTop+row); term.clearLine(); setc(th.fg,th.bg)
      if lines[idx] then term.setCursorPos(x1+2,contentTop+row); term.write(lines[idx]) end
    end
    drawScrollButtons(th,x2,contentTop,contentBottom)
    drawBackButton(th,x1,y2,"< Zurueck")
  end
  while true do
    redraw()
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      local up={x2-4,contentTop,x2-1,contentTop+2}
      local dn={x2-4,contentBottom-2,x2-1,contentBottom}
      if inRect(mx,my,{x1,y2-2,x1+14,y2}) then return end
      if inRect(mx,my,up) then if offset>0 then offset=offset-1 end
      elseif inRect(mx,my,dn) then if offset+maxRows<#lines then offset=offset+1 end end
    elseif e=="key" and a==keys.back then return end
  end
end

local function inventoryScreen()
  local lines={"Gegenstaende:"}
  for k,v in pairs(state.inventory) do table.insert(lines,"  "..(LORE[k] and LORE[k].name or k)..": x"..v) end
  table.insert(lines,""); table.insert(lines,"Lore Eintraege:")
  for k,_ in pairs(state.journal.loreUnlocked) do table.insert(lines,"  "..(LORE[k] and LORE[k].name or k)..": "..(LORE[k] and LORE[k].text or "")) end
  scrollTextPanel("Inventar / Lore", lines)
end

local function journalScreen()
  local lines={"Zusammenfassung:"}
  for _,ln in ipairs(state.journal.summary) do table.insert(lines,"  - "..ln) end
  table.insert(lines,""); table.insert(lines,"Quests:")
  for _,q in pairs(state.journal.quests) do table.insert(lines, (q.done and "  [x] " or "  [ ] ")..q.text) end
  scrollTextPanel("Journal / Quests", lines)
end

-------------------- MAIN MENU -------------------------
local function showStatsSummary(x,y)
  local played=state.playTime + (state._playTimerOn and (_now()-state._playTimerT0) or 0)
  term.setCursorPos(x,y); setc(theme().fg,theme().bg); term.write("Spielzeit: "..string.format("%02d:%02d",math.floor(played/60),played%60))
  term.setCursorPos(x,y+1); term.write("Endings: "..(function() local c=0; for _ in pairs(state.endings) do c=c+1 end; return c end)())
end

local function slotPicker()
  local th=theme(); clear(th.bg); drawLayout("Save Slots","Touch: Slot / Loeschen / Zurueck","")
  local x1,y1=5,FRAME.titleH+4; local x2,y2=W-5,H-FRAME.statusH-1
  local o={{label="Slot 1"},{label="Slot 2"},{label="Slot 3"},{label="Slot loeschen (aktuell)"}}
  makeButtons(x1,y1,x2,y2-4,o); drawButtons(th)
  local backRect=drawBackButton(th,x1,y2,"< Zurueck")
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if inRect(mx,my,backRect) then return end
      for idx,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
        playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
        if idx>=1 and idx<=3 then state.slot=idx; return elseif idx==4 then deleteSave(state.slot); return end
      end end
    elseif e=="key" and a==keys.back then return end
  end
end

local function mainMenu()
  local th=theme()
  playTimerStop()
  clear(th.bg); for i=1,10 do hline(2,1,W," ",nil,th.titleBg); writeCentered(1,"ENTERTAINMENT STATION",th.titleFg,th.titleBg); sleep(0.04) end
  while true do
    clear(th.bg); drawLayout("HAUPTMENUE","Touch: Auswahl","M: Map")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Fortsetzen (Slot "..state.slot..")"},{label="Neues Spiel"},{label="Save Slot wechseln"},{label="Einstellungen"},{label="Statistik"},{label="Zitate/Screenshot export"},{label="Beenden"}}
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local _backRect=drawBackButton(th,x1,y2,"< Zurueck")
    showStatsSummary(6,H-5)
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      for idx,bt in ipairs(buttons) do if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
        playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
        if idx==1 then if fs.exists(savePath(state.slot)) and load(state.slot) then if state.lastRecap and #state.lastRecap>0 then clear(th.bg); drawLayout("Rueckblende",state.lastRecap,""); sleep(1.0) end; return "resume" else return "new" end
        elseif idx==2 then return "new"
        elseif idx==3 then slotPicker()
        elseif idx==4 then settingsMenu()
        elseif idx==5 then statsScreen()
        elseif idx==6 then
          if not fs.exists(QUOTE_DIR) then fs.makeDir(QUOTE_DIR) end
          local path=QUOTE_DIR.."/quote_"..os.epoch("utc")..".txt"
          local h=fs.open(path,"w"); if h then
            h.write("Name: "..(state.playerName or "").."\nScene: "..(state.scene or "").."\n")
            h.write("Stats: C="..state.courage.." W="..state.wisdom.." E="..state.empathy.."\n")
            h.write("Last recap: "..(state.lastRecap or "").."\n"); h.close()
          end
        else return "quit" end
      end end
    elseif e=="key" and a==keys.m then drawMap() end
  end
end

-------------------- AUTOSAVE / RECAP ------------------
local function autosaveRecap()
  if not state.autosave then return end
  save(state.slot)
  local n=#state.journal.summary; local recap=""
  for i=math.max(1,n-1),n do recap=recap..(state.journal.summary[i] or "").."; " end
  state.lastRecap=recap
end

-------------------- GAME LOOP -------------------------
local function game()
  if not state.playerName or #state.playerName==0 then
    local ok=askName()
    if not ok then return "menu" end
    save(state.slot)
  end
  -- Intro
  local th=theme()
  local function introCutsceneLocal() local _=th; end
  introCutscene()
  playTimerStart()
  while true do
    local scenes={
      intro=scene_intro,courtyard=scene_courtyard,hall=scene_hall,
      riddle1=scene_riddle1,riddle2=scene_riddle2,depth=scene_depth,
      final=scene_final,secret=scene_secret,ending_secret=scene_ending_secret,
      credits=function() return "menu" end
    }
    local handler=scenes[state.scene] or scene_intro
    local nextScene=handler()
    autosaveRecap()
    if nextScene=="menu" then playTimerStop(); return
    elseif nextScene=="credits" then playTimerStop(); state.scene="intro"; return
    elseif nextScene then state.scene=nextScene end

    local t=os.startTimer(0.01)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then break
      elseif e=="key" and (a==keys.p) then
        playTimerStop()
        local function pauseMenu()
          local th=theme()
          while true do
            clear(th.bg); drawLayout("Pause","Touch: Auswahl","M: Map  Zurueck")
            local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
            local opts={{label="Weiterspielen"},{label="Journal"},{label="Inventar/Lore"},{label="Einstellungen"},{label="Speichern"},{label="Zur Karte"},{label="< Hauptmenue"}}
            makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
            local backRect=drawBackButton(th,x1,y2,"< Zurueck")
            while true do
              local e2,a2,b2,c2=os.pullEvent()
              if e2=="monitor_touch" then
                local mx,my=b2,c2
                if inRect(mx,my,backRect) then return end
                for idx,bt in ipairs(buttons) do
                  if mx>=bt[1] and mx<=bt[3] and my>=bt[2] and my<=bt[4] then
                    if idx==1 then return
                    elseif idx==2 then journalScreen()
                    elseif idx==3 then inventoryScreen()
                    elseif idx==4 then settingsMenu()
                    elseif idx==5 then save(state.slot)
                    elseif idx==6 then drawMap()
                    else return "quit" end
                    break
                  end
                end
              elseif e2=="key" and a2==keys.back then return end
            end
          end
        end
        local r=pauseMenu(); if r=="quit" then return end; playTimerStart(); break
      elseif e=="key" and (a==keys.m) then drawMap()
      elseif e=="timer" and a==t then break end
    end
  end
end

-------------------- ENTRY -----------------------------
math.randomseed(os.epoch("utc")%2^31)
while true do
  local act=mainMenu()
  if act=="new" then
    state={slot=state.slot,playerName="",scene="intro",courage=0,wisdom=0,empathy=0,level=1,xp=0,flags={},decisions=0,endings={},playTime=0,_playTimerOn=false,_playTimerT0=0,playTimerEnabled=true,mapLoc="Gate",journal={summary={},quests={},loreUnlocked={},notes={}},inventory={},achievements={},autosave=true,lastRecap="",portraitMood="neutral",portraitTick=0}
    save(state.slot)
    local r=game(); if r=="quit" then break end
  elseif act=="resume" then local r=game(); if r=="quit" then break end
  else break end
end

term.redirect(oldTerm); term.setCursorBlink(true)
