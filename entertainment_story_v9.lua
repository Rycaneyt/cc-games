-- entertainment_v3.lua  (v3.2.1 – Back-Fixes, Audio ±, Themes)
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
local CONFIG={theme="Ocean",textScale=0,shader=true,music=0.4,sfx=0.8,master=1.0,mute=false}

local THEMES={
  Ocean ={bg=colors.black,fg=colors.white,frame=colors.gray,titleBg=colors.blue,titleFg=colors.white,statusBg=colors.gray,statusFg=colors.white,hlBg=colors.cyan,hlFg=colors.black,btnNum=colors.yellow,accent=colors.lightBlue,good=colors.green,bad=colors.red,neutral=colors.orange},
  Sunset={bg=colors.black,fg=colors.white,frame=colors.orange,titleBg=colors.orange,titleFg=colors.black,statusBg=colors.brown,statusFg=colors.white,hlBg=colors.red,hlFg=colors.white,btnNum=colors.yellow,accent=colors.orange,good=colors.orange,bad=colors.red,neutral=colors.yellow},
  Neon  ={bg=colors.black,fg=colors.white,frame=colors.magenta,titleBg=colors.purple,titleFg=colors.white,statusBg=colors.gray,statusFg=colors.white,hlBg=colors.lime,hlFg=colors.black,btnNum=colors.yellow,accent=colors.pink,good=colors.lime,bad=colors.red,neutral=colors.lightBlue},
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
  timeStart=os.epoch("utc"), playTime=0, mapLoc="Gate",
  journal={summary={},quests={},loreUnlocked={},notes={}},
  inventory={}, achievements={}, autosave=true, lastRecap="",
  portraitMood="neutral", portraitTick=0,
}

-------------------- LOAD / SAVE CONFIG ----------------
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
loadConfig()

-- TextScale
if CONFIG.textScale==0 then
  local targetW,targetH=90,30; local bestS,bestDiff=1.0,1e9
  for s=0.5,3.0,0.5 do mon.setTextScale(s); local w,h=term.getSize()
    local d=math.abs(w-targetW)+math.abs(h-targetH)
    if d<bestDiff then bestDiff,bestS=d,s end
  end
  mon.setTextScale(bestS)
else mon.setTextScale(CONFIG.textScale) end
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

local function particles()
  local th=theme()
  for _=1, math.min(60, math.floor(W*H/80)) do
    local x=math.random(2,W-2); local y=math.random(4,H-2)
    setc(nil, ({th.accent,th.good,th.neutral,th.bad})[math.random(4)])
    term.setCursorPos(x,y); term.write(" ")
  end
end

local function confetti(th,duration)
  local t0=os.clock(); local cols={th.good,th.neutral,th.accent,th.bad}
  while os.clock()-t0<duration do
    local x=math.random(1,W); local y=math.random(1,H)
    setc(nil, cols[math.random(#cols)]); term.setCursorPos(x,y); term.write(" ")
    sleep(0.002)
  end
end

-------------------- BUTTONS / TOUCH -------------------
local buttons={}
local function makeButtons(x1,y1,x2,y2,options)
  buttons={}
  local height=y2-y1+1; local per=#options; if per<1 then return end
  local lineH=math.max(3, math.floor(height/per)); local y=y1
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
    setc(th.btnNum,th.bg); term.setCursorPos(cx("x"),mid); term.write(tostring(idx))
    setc(th.fg,th.bg); term.setCursorPos(cx("x")+2,mid); term.write(") "..label)
  end
end
local function waitChoice()
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      for _,bt in ipairs(buttons) do local x1,y1,x2,y2,_,idx=bt[1],bt[2],bt[3],bt[4],bt[5],bt[6]
        if mx>=x1 and mx<=x2 and my>=y1 and my<=y2 then playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master); return idx end
      end
    elseif e=="key" then
      if a>=keys.one and a<=keys.nine then return (a-keys.one)+1
      elseif a==keys.enter or a==keys.numPadEnter then return 1 end
    end
  end
end

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

-------------------- SAVE / LOAD -----------------------
local function savePath(slot) return SAVE_PREFIX..tostring(slot) end
local function save(slot)
  state.playTime=state.playTime+math.floor((os.epoch("utc")-state.timeStart)/1000)
  state.timeStart=os.epoch("utc")
  local h=fs.open(savePath(slot),"w"); if not h then return false end
  h.write(textutils.serialize({state=state,config=CONFIG})); h.close(); return true
end
local function load(slot)
  if not fs.exists(savePath(slot)) then return false end
  local h=fs.open(savePath(slot),"r"); local s=h.readAll(); h.close()
  local ok,t=pcall(textutils.unserialize,s)
  if ok and type(t)=="table" and t.state then
    state=t.state; if t.config then for k,v in pairs(t.config) do CONFIG[k]=v end end
    state.slot=slot; state.timeStart=os.epoch("utc"); return true
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
  term.setCursorPos(x1+2,y1+3); setc(th.fg,th.bg); term.write(ACH[id].name)
  term.setCursorPos(x1+2,y1+4); term.write(ACH[id].desc)
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
local function drawBackButton(th,x1,y2) local bx1,by1=x1,y2-2; local bx2=bx1+14; local by2=y2; drawBox(bx1,by1,bx2,by2,th.frame,th.bg); term.setCursorPos(bx1+2,by1+1); setc(th.fg,th.bg); term.write("< Zurueck"); return {bx1,by1,bx2,by2} end
local function waitBackOrTouch(backRect) while true do local e,a,b,c=os.pullEvent(); if e=="monitor_touch" then if b>=backRect[1] and b<=backRect[3] and c>=backRect[2] and c<=backRect[4] then return true end elseif e=="key" and (a==keys.back or a==keys.enter) then return true end end end
local function drawMap()
  local th=theme(); clear(th.bg); drawLayout("Weltkarte","Tippe: zurueck","")
  local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
  drawBox(x1,y1,x2,y2,th.frame,th.bg)
  for _,p in ipairs(MAP.paths) do local a=MAP.nodes[p[1]]; local b=MAP.nodes[p[2]]; local ax=x1+a.x; local ay=y1+a.y; local bx=x1+b.x; local by=y1+b.y; local dx=bx-ax; local steps=math.max(1,math.abs(dx)); for i=0,steps do local xx=ax+math.floor(i*dx/steps); local yy=ay+math.floor((by-ay)*i/steps); term.setCursorPos(xx,yy); setc(th.neutral,th.bg); term.write("*") end end
  for _,n in pairs(MAP.nodes) do term.setCursorPos(x1+n.x,y1+n.y); setc(th.fg,th.bg); term.write("O"); term.setCursorPos(x1+n.x+2,y1+n.y); term.write(n.label) end
  local cur=MAP.nodes[state.mapLoc] or MAP.nodes.Gate; term.setCursorPos(x1+cur.x,y1+cur.y); setc(th.accent,th.bg); term.write("@")
  local backRect=drawBackButton(th,x1,y2); waitBackOrTouch(backRect)
end

-------------------- PORTRAIT --------------------------
local PORTRAIT={neutral={"  /\\ "," (..)","  || "}, happy={"  /\\ "," (^^)","  \\/ "}, sad={"  /\\ "," (..)","  -- "}, brave={" /\\/"," (><)"," /  \\"}}
local function drawPortrait(x,y,mood) local th=theme(); local art=PORTRAIT[mood] or PORTRAIT.neutral; for i=1,#art do term.setCursorPos(x,y+i-1); setc(th.fg,th.bg); term.write(art[i]) end end
local function setMood(m) state.portraitMood=m end

-------------------- THEME / SCALE MENUS ---------------
local function themeMenu()
  local th=theme(); local names={}; for k,_ in pairs(THEMES) do table.insert(names,k) end; table.sort(names)
  while true do
    clear(th.bg); drawLayout("Theme auswaehlen","Tippe Theme oder < Zurueck","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local listTop=y1+6; local listBottom=y2-4
    drawBox(x1,y1,x2,y1+4,th.frame,th.bg); writeCentered(y1+1,"Vorschau",th.titleFg,th.titleBg); writeCentered(y1+3,"Aktuell: "..CONFIG.theme,th.fg,th.bg)
    local opts={}; for _,n in ipairs(names) do table.insert(opts,{label=n}) end
    makeButtons(x1,listTop,x2,listBottom,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        local mx,my=b,c
        if mx>=backRect[1] and mx<=backRect[3] and my>=backRect[2] and my<=backRect[4] then playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master); return end
        for _,bt in ipairs(buttons) do local x1b,y1b,x2b,y2b,label=bt[1],bt[2],bt[3],bt[4],bt[5]
          if mx>=x1b and mx<=x2b and my>=y1b and my<=y2b then CONFIG.theme=label; saveConfig(); th=theme(); playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master); break end
        end
        break
      elseif e=="key" and a==keys.back then return end
    end
  end
end

local function applyAutoScale()
  local targetW,targetH=90,30; local bestS,bestDiff=1.0,1e9
  for s=0.5,3.0,0.5 do mon.setTextScale(s); local w,h=term.getSize(); local d=math.abs(w-targetW)+math.abs(h-targetH); if d<bestDiff then bestDiff,bestS=d,s end end
  mon.setTextScale(bestS); CONFIG.textScale=0; saveConfig()
end

local function scaleMenu()
  local th=theme(); local scales={0.5,1.0,1.5,2.0,2.5,3.0}
  while true do
    clear(th.bg); drawLayout("Textgroesse","Tippe Option oder < Zurueck","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Auto (empfohlen)"}}
    for _,s in ipairs(scales) do table.insert(opts,{label=("Skalierung %.1f"):format(s)}) end
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        local mx,my=b,c
        if mx>=backRect[1] and mx<=backRect[3] and my>=backRect[2] and my<=backRect[4] then playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master); return end
        for idx,bt in ipairs(buttons) do local x1b,y1b,x2b,y2b=bt[1],bt[2],bt[3],bt[4]
          if mx>=x1b and mx<=x2b and my>=y1b and my<=y2b then
            playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
            if idx==1 then applyAutoScale() else local val=scales[idx-1]; if val then CONFIG.textScale=val; mon.setTextScale(val); saveConfig() end end
            W,H=term.getSize(); th=theme(); break
          end
        end
        break
      elseif e=="key" and a==keys.back then return end
    end
  end
end

-------------------- AUDIO MENU ------------------------
local function inRect(mx,my,r) return mx>=r[1] and mx<=r[3] and my>=r[2] and my<=r[4] end
local function drawStepper(th,x,y,label,value)
  term.setCursorPos(x,y); setc(th.fg,th.bg); term.write(label)
  local minus={x+18,y,x+22,y+2}; local valb={x+24,y,x+34,y+2}; local plus={x+36,y,x+40,y+2}
  drawBox(minus[1],minus[2],minus[3],minus[4],th.frame,th.bg); term.setCursorPos(minus[1]+1,minus[2]+1); term.write("-")
  drawBox(valb[1],valb[2],valb[3],valb[4],th.frame,th.bg); term.setCursorPos(valb[1]+1,valb[2]+1); term.write(string.format("%.1f",value))
  drawBox(plus[1],plus[2],plus[3],plus[4],th.frame,th.bg); term.setCursorPos(plus[1]+1,plus[2]+1); term.write("+")
  return {minus=minus,value=valb,plus=plus}
end

local function audioMenu()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Audio","Minus/Plus, Mute, Zurueck","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    drawBox(x1,y1,x2,y2,th.frame,th.bg)
    local mCtl=drawStepper(th,x1+2,y1+2,"Master",CONFIG.master)
    local muCtl=drawStepper(th,x1+2,y1+6,"Musik ",CONFIG.music)
    local sCtl=drawStepper(th,x1+2,y1+10,"SFX   ",CONFIG.sfx)
    local muteBtn={x2-18,y1+2,x2-4,y1+4}
    drawBox(muteBtn[1],muteBtn[2],muteBtn[3],muteBtn[4],th.frame,th.bg); term.setCursorPos(muteBtn[1]+2,muteBtn[2]+1); term.write("Mute: "..(CONFIG.mute and "Ja" or "Nein"))
    local backRect=drawBackButton(th,x1,y2)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        local mx,my=b,c; playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
        if inRect(mx,my,mCtl.minus) then CONFIG.master=math.max(0,CONFIG.master-0.1); saveConfig()
        elseif inRect(mx,my,mCtl.plus) then CONFIG.master=math.min(1,CONFIG.master+0.1); saveConfig()
        elseif inRect(mx,my,muCtl.minus) then CONFIG.music=math.max(0,CONFIG.music-0.1); saveConfig()
        elseif inRect(mx,my,muCtl.plus) then CONFIG.music=math.min(1,CONFIG.music+0.1); saveConfig()
        elseif inRect(mx,my,sCtl.minus) then CONFIG.sfx=math.max(0,CONFIG.sfx-0.1); saveConfig()
        elseif inRect(mx,my,sCtl.plus) then CONFIG.sfx=math.min(1,CONFIG.sfx+0.1); saveConfig()
        elseif inRect(mx,my,muteBtn) then CONFIG.mute=not CONFIG.mute; saveConfig()
        elseif inRect(mx,my,backRect) then return end
        break
      elseif e=="key" and a==keys.back then return end
    end
  end
end

-------------------- SETTINGS / PAUSE / INFO -----------
local function settingsMenu()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Einstellungen","Touch: Auswahl","")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Theme"},{label="Textgroesse"},{label="Shader: "..(CONFIG.shader and "An" or "Aus")},{label="Audio (Master/Musik/SFX/Mute)"},{label="< Zurueck"}}
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        local mx,my=b,c
        if mx>=backRect[1] and mx<=backRect[3] and my>=backRect[2] and my<=backRect[4] then return end
        for idx,bt in ipairs(buttons) do local x1b,y1b,x2b,y2b=bt[1],bt[2],bt[3],bt[4]
          if mx>=x1b and mx<=x2b and my>=y1b and my<=y2b then
            playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
            if idx==1 then themeMenu()
            elseif idx==2 then scaleMenu()
            elseif idx==3 then CONFIG.shader=not CONFIG.shader; saveConfig()
            elseif idx==4 then audioMenu()
            else return
            end
            break
          end
        end
        break
      elseif e=="key" and a==keys.back then return end
    end
  end
end

local function formatTime(sec) local m=math.floor(sec/60); local s=sec%60; return string.format("%02d:%02d",m,s) end
local function statsScreen()
  local th=theme(); clear(th.bg); drawLayout("Statistik","Tippe: zurueck","")
  local played=state.playTime+math.floor((os.epoch("utc")-state.timeStart)/1000)
  local lines={"Name: "..(state.playerName or ""), "Level: "..state.level.."  XP: "..state.xp, "Mut: "..state.courage.."  Verstand: "..state.wisdom.."  Mitgefuehl: "..state.empathy, "Entscheidungen: "..state.decisions, "Endings: "..(function() local c=0; for _ in pairs(state.endings) do c=c+1 end; return c end)(), "Spielzeit: "..formatTime(played)}
  local y=FRAME.titleH+2; for _,ln in ipairs(lines) do term.setCursorPos(4,y); setc(theme().fg,theme().bg); term.write(ln); y=y+2 end
  local backRect=drawBackButton(theme(),4,H-1); waitBackOrTouch(backRect)
end

local function inventoryScreen()
  local th=theme(); clear(th.bg); drawLayout("Inventar / Lore","Tippe: zurueck","")
  local y=FRAME.titleH+2; term.setCursorPos(4,y); term.write("Gegenstaende:")
  for k,v in pairs(state.inventory) do y=y+1; term.setCursorPos(6,y); term.write((LORE[k] and LORE[k].name or k)..": x"..v) end
  y=y+2; term.setCursorPos(4,y); term.write("Lore Eintraege:")
  for k,_ in pairs(state.journal.loreUnlocked) do y=y+1; term.setCursorPos(6,y); term.write((LORE[k] and LORE[k].name or k)..": "..(LORE[k] and LORE[k].text or "")) end
  local backRect=drawBackButton(theme(),4,H-1); waitBackOrTouch(backRect)
end

local function journalScreen()
  local th=theme(); clear(th.bg); drawLayout("Journal / Quests","Tippe: zurueck","")
  local y=FRAME.titleH+2; term.setCursorPos(4,y); term.write("Zusammenfassung:")
  for _,ln in ipairs(state.journal.summary) do y=y+1; term.setCursorPos(6,y); term.write("- "..ln) end
  y=y+2; term.setCursorPos(4,y); term.write("Quests:")
  for _,q in pairs(state.journal.quests) do y=y+1; term.setCursorPos(6,y); term.write((q.done and "[x] " or "[ ] ")..q.text) end
  local backRect=drawBackButton(theme(),4,H-1); waitBackOrTouch(backRect)
end

local function pauseMenu()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Pause","Touch: Auswahl","M: Map  P: Pause")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Weiterspielen"},{label="Journal"},{label="Inventar/Lore"},{label="Einstellungen"},{label="Speichern"},{label="Zur Karte"},{label="< Hauptmenue"}}
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        local mx,my=b,c
        if mx>=backRect[1] and mx<=backRect[3] and my>=backRect[2] and my<=backRect[4] then return end
        for idx,bt in ipairs(buttons) do local x1b,y1b,x2b,y2b=bt[1],bt[2],bt[3],bt[4]
          if mx>=x1b and mx<=x2b and my>=y1b and my<=y2b then
            playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
            if idx==1 then return
            elseif idx==2 then journalScreen()
            elseif idx==3 then inventoryScreen()
            elseif idx==4 then settingsMenu()
            elseif idx==5 then save(state.slot)
            elseif idx==6 then drawMap()
            else return "quit"
            end
            break
          end
        end
        break
      elseif e=="key" and a==keys.back then return end
    end
  end
end

-------------------- NAME INPUT ------------------------
local function askName()
  local th=theme()
  while true do
    clear(th.bg); drawLayout("Wie heisst dein Bote?","Tippe Feld, OK, Zurueck","Enter = OK")
    local x1,y1=10,math.floor(H/2)-2; local x2=x1+40
    drawBox(x1,y1,x2,y1+2,th.frame,th.bg); term.setCursorPos(x1+2,y1+1); setc(th.fg,th.bg); term.write(state.playerName or "")
    local okBtn={x2+2,y1,x2+16,y1+2}; drawBox(okBtn[1],okBtn[2],okBtn[3],okBtn[4],th.frame,th.bg); term.setCursorPos(okBtn[1]+2,okBtn[2]+1); term.write("OK")
    local backRect={x1,y1+4,x1+14,y1+6}; drawBox(backRect[1],backRect[2],backRect[3],backRect[4],th.frame,th.bg); term.setCursorPos(backRect[1]+2,backRect[2]+1); term.write("< Zurueck")
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then
        if b>=x1 and b<=x2 and c>=y1 and c<=y1+2 then
          term.setCursorPos(x1+2,y1+1); term.clearLine(); state.playerName=""
          while true do local e2,k=os.pullEvent("char"); if #state.playerName<20 then state.playerName=state.playerName..k; term.write(k) end; if #state.playerName>=1 then break end end
        elseif b>=okBtn[1] and b<=okBtn[3] and c>=okBtn[2] and c<=okBtn[4] then if #state.playerName>0 then return end
        elseif b>=backRect[1] and b<=backRect[3] and c>=backRect[2] and c<=backRect[4] then return end
      elseif e=="key" and (a==keys.enter or a==keys.numPadEnter) then if #state.playerName>0 then return end
      elseif e=="key" and a==keys.back then return end
    end
  end
end

-------------------- DIALOG / STORY ENGINE -------------
local function drawSceneFrame(title,subtitle)
  local th=theme(); clear(th.bg); drawLayout(title or "Szene",subtitle or ("Name: "..(state.playerName or "")),"M: Map  P: Pause"); drawPortrait(W-9,FRAME.titleH+1,state.portraitMood)
end

local function doChoice(prompt,options)
  local th=theme(); local x1,y1=3,FRAME.titleH+1; local x2,y2=W-12,H-FRAME.statusH-1
  drawBox(x1,y1,x2,y2-8,th.frame,th.bg)
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
  local y=y1+1; setc(th.fg,th.bg)
  for _,ln in ipairs(wrap(prompt,width)) do if y>=y2-9 then break end; term.setCursorPos(x1+2,y); term.write(ln); y=y+1; sleep(0.01) end
  makeButtons(x1,y2-7,x2,y2-1,options); drawButtons(th)
  state.portraitTick=(state.portraitTick+1)%3; if state.portraitTick==0 then drawPortrait(W-9,FRAME.titleH+1,state.portraitMood) end
  return waitChoice()
end

-------------------- STATS / LEVEL ---------------------
local function addXP(n) state.xp=state.xp+n; if state.xp>=(state.level*10) then state.level=state.level+1; state.xp=0; journalAdd("Level up! Jetzt Level "..state.level) end end
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
  for i=1,5 do writeCentered(math.floor(H/2)-3+i,string.rep("*",i*6),th.accent,th.bg); sleep(0.1) end
  particles(); musicTick(); while true do local e=os.pullEvent(); if e=="monitor_touch" or e=="key" then break end end
end

local function scene_intro()
  drawSceneFrame("Die Flusternde Ruine","Willkommen, "..(state.playerName or ""))
  setMood("neutral")
  local idx=doChoice("Du stehst vor einem alten Tor. Die Luft ist kuehl. Was tust du, "..(state.playerName or "").."?",{{label="Mutig eintreten"},{label="Erst den Hof erkunden"},{label="Mit der Steinfigur sprechen"}})
  state.decisions=state.decisions+1; unlock("firstChoice")
  if idx==1 then statUp("courage",1); state.mapLoc="Hall"; journalAdd("Du bist in die Halle eingetreten."); return "hall"
  elseif idx==2 then statUp("wisdom",1); state.mapLoc="Court"; journalAdd("Du untersuchst den Hof der Schatten."); return "courtyard"
  else setMood("happy"); statUp("empathy",1); journalAdd("Die Figur fluestert: 'Suche die drei Zeichen'."); questAdd("find3","Finde drei Zeichen der Stimme"); addItem("echoLeaf"); return "courtyard" end
end

local function scene_courtyard()
  drawSceneFrame("Hof der Schatten","Kuehler Wind")
  local opts={{label="Inschriften entschluesseln"},{label="Dem Summen zur Halle folgen"}, optionIf(state.empathy>=2,{label="Einem Kind helfen (Nebenfigur)"})}
  local filtered={}; for _,o in ipairs(opts) do if o then table.insert(filtered,o) end end
  local idx=doChoice("Zwischen den Steinen sind Zeichen eingeritzt. Aus der Halle klingt ein Summen.",filtered)
  state.decisions=state.decisions+1
  if idx==1 then statUp("wisdom",1); addItem("runeShard"); state.flags.gotRune=true; journalAdd("Ein Runen-Splitter fuegt sich in deine Tasche."); return "riddle1"
  elseif idx==2 then statUp("courage",1); state.mapLoc="Hall"; return "hall"
  else setMood("happy"); statUp("empathy",1); journalAdd("Du hilfst dem Kind. Es zeigt dir eine Abkuerzung."); state.flags.shortcut=true; addXP(3); return "hall" end
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
  if idx==1 then statUp("courage",1); setMood("brave")
  elseif idx==2 then statUp("wisdom",1); setMood("neutral")
  else statUp("empathy",1); setMood("happy") end
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
  confetti(th,1.6); playSound("minecraft:ui.toast.challenge_complete",CONFIG.sfx*CONFIG.master,1.0)
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

local function credits()
  local th=theme(); clear(th.bg); drawLayout("Credits","Danke fuers Spielen!","")
  for i=H-3,FRAME.titleH+2,-1 do term.setCursorPos(cx("Made with CC:Tweaked"),i); setc(th.fg,th.bg); term.write("Made with CC:Tweaked"); sleep(0.05) end
  writeCentered(H-3,"Tippe, um zum Hauptmenue zu gehen",th.fg); while true do local e=os.pullEvent(); if e=="monitor_touch" or e=="key" then break end end
  return "menu"
end

local scenes={intro=scene_intro,courtyard=scene_courtyard,hall=scene_hall,riddle1=scene_riddle1,riddle2=scene_riddle2,depth=scene_depth,final=scene_final,secret=scene_secret,ending_secret=scene_ending_secret,credits=credits}

-------------------- AUTOSAVE / RECAP ------------------
local function autosaveRecap()
  if not state.autosave then return end
  save(state.slot)
  local n=#state.journal.summary; local recap=""
  for i=math.max(1,n-1),n do recap=recap..(state.journal.summary[i] or "").."; " end
  state.lastRecap=recap
end

-------------------- QUOTE EXPORT ----------------------
local function quoteExport()
  if not fs.exists(QUOTE_DIR) then fs.makeDir(QUOTE_DIR) end
  local path=QUOTE_DIR.."/quote_"..os.epoch("utc")..".txt"
  local h=fs.open(path,"w"); if not h then return end
  h.write("Name: "..(state.playerName or "").."\n"); h.write("Scene: "..(state.scene or "").."\n")
  h.write("Stats: C="..state.courage.." W="..state.wisdom.." E="..state.empathy.."\n")
  h.write("Last recap: "..(state.lastRecap or "").."\n"); h.close()
end

-------------------- MAIN MENU -------------------------
local function showStatsSummary(x,y)
  local th=theme(); local played=state.playTime+math.floor((os.epoch("utc")-state.timeStart)/1000)
  term.setCursorPos(x,y); setc(th.fg,th.bg); term.write("Spielzeit: "..string.format("%02d:%02d",math.floor(played/60),played%60))
  term.setCursorPos(x,y+1); term.write("Endings: "..(function() local c=0; for _ in pairs(state.endings) do c=c+1 end; return c end)())
end

local function slotPicker()
  local th=theme(); clear(th.bg); drawLayout("Save Slots","Touch: Slot / Loeschen / Zurueck","")
  local x1,y1=5,FRAME.titleH+4; local x2,y2=W-5,H-FRAME.statusH-1
  local o={{label="Slot 1"},{label="Slot 2"},{label="Slot 3"},{label="Slot loeschen (aktuell)"}}
  makeButtons(x1,y1,x2,y2-4,o); drawButtons(th)
  local backRect=drawBackButton(th,x1,y2)
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      if mx>=backRect[1] and mx<=backRect[3] and my>=backRect[2] and my<=backRect[4] then return end
      for idx,bt in ipairs(buttons) do local x1b,y1b,x2b,y2b=bt[1],bt[2],bt[3],bt[4]
        if mx>=x1b and mx<=x2b and my>=y1b and my<=y2b then
          playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
          if idx>=1 and idx<=3 then state.slot=idx; return elseif idx==4 then deleteSave(state.slot); return end
        end
      end
    elseif e=="key" and a==keys.back then return end
  end
end

local function mainMenu()
  local th=theme()
  clear(th.bg); for i=1,10 do hline(2,1,W," ",nil,th.titleBg); writeCentered(1,"ENTERTAINMENT STATION",th.titleFg,th.titleBg); sleep(0.05) end
  while true do
    clear(th.bg); drawLayout("HAUPTMENUE","Touch: Auswahl","M: Map")
    local x1,y1=3,FRAME.titleH+1; local x2,y2=W-2,H-FRAME.statusH-1
    local opts={{label="Fortsetzen (Slot "..state.slot..")"},{label="Neues Spiel"},{label="Save Slot wechseln"},{label="Einstellungen"},{label="Statistik"},{label="Zitate/Screenshot export"},{label="Beenden"}}
    makeButtons(x1,y1+2,x2,y2-4,opts); drawButtons(th)
    local backRect=drawBackButton(th,x1,y2) -- no-op (nur Konsistenz)
    showStatsSummary(6,H-5)
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" then
      local mx,my=b,c
      for idx,bt in ipairs(buttons) do local x1b,y1b,x2b,y2b=bt[1],bt[2],bt[3],bt[4]
        if mx>=x1b and mx<=x2b and my>=y1b and my<=y2b then
          playSound("minecraft:block.note_block.pling",CONFIG.sfx*CONFIG.master)
          if idx==1 then if fs.exists(savePath(state.slot)) and load(state.slot) then if state.lastRecap and #state.lastRecap>0 then clear(th.bg); drawLayout("Rueckblende",state.lastRecap,""); sleep(1.2) end; return "resume" else return "new" end
          elseif idx==2 then return "new"
          elseif idx==3 then slotPicker()
          elseif idx==4 then settingsMenu()
          elseif idx==5 then statsScreen()
          elseif idx==6 then quoteExport()
          else return "quit" end
        end
      end
    elseif e=="key" and a==keys.m then drawMap() end
  end
end

-------------------- GAME LOOP -------------------------
local function game()
  if not state.playerName or #state.playerName==0 then askName(); save(state.slot) end
  introCutscene()
  while true do
    local handler=scenes[state.scene] or scenes.intro
    local nextScene=handler()
    autosaveRecap()
    if nextScene=="menu" then return
    elseif nextScene=="credits" then state.scene="intro"; return
    elseif nextScene=="secret" then state.scene="secret"
    elseif nextScene then state.scene=nextScene end
    local t=os.startTimer(0.01)
    while true do
      local e,a,b,c=os.pullEvent()
      if e=="monitor_touch" then break
      elseif e=="key" and (a==keys.p) then local r=pauseMenu(); if r=="quit" then return end; break
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
    state={slot=state.slot,playerName="",scene="intro",courage=0,wisdom=0,empathy=0,level=1,xp=0,flags={},decisions=0,endings={},timeStart=os.epoch("utc"),playTime=0,mapLoc="Gate",journal={summary={},quests={},loreUnlocked={},notes={}},inventory={},achievements={},autosave=true,lastRecap="",portraitMood="neutral",portraitTick=0}
    save(state.slot)
    local r=game(); if r=="quit" then break end
  elseif act=="resume" then local r=game(); if r=="quit" then break end
  else break end
end

term.redirect(oldTerm); term.setCursorBlink(true)
