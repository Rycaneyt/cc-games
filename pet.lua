-- pet.lua — Virtual Pet (Touch-first)
-- Neu: Inventar (kaufen & später benutzen), Shop/Quests/Inventar komplett per Touch bedienbar

-------------------- Peripherals & Basics --------------------
local mon = peripheral.find and peripheral.find("monitor") or nil
local spk = peripheral.find and peripheral.find("speaker") or nil
local termNative = term.native()
if mon then pcall(mon.setTextScale, 0.5); term.redirect(mon) end

local function W() local w,_=term.getSize() return w end
local function H() local _,h=term.getSize() return h end
local function setFG(c) term.setTextColor(c or colors.white) end
local function setBG(c) term.setBackgroundColor(c or colors.black) end
local function clr() setFG(colors.white); setBG(colors.black); term.clear(); term.setCursorPos(1,1) end
local function center(y, txt, fg, bg)
  txt = tostring(txt or "")
  if bg then setBG(bg) end; if fg then setFG(fg) end
  term.setCursorPos(math.floor((W()-#txt)/2)+1, y); term.write(txt)
  setBG(colors.black); setFG(colors.white)
end
local function beep(ok) if not spk then return end
  if ok then spk.playNote("chime",1.0,16) else spk.playSound("minecraft:block.note_block.bass") end
end

-------------------- Save/Load --------------------
local SAVE = "pet_save.json"
local function load()
  if not fs.exists(SAVE) then return nil end
  local h=fs.open(SAVE,"r"); if not h then return nil end
  local txt=h.readAll(); h.close()
  local ok,data=pcall(textutils.unserializeJSON, txt)
  if ok and type(data)=="table" then return data end
end
local function save(state)
  local h=fs.open(SAVE,"w"); if not h then return end
  h.write(textutils.serializeJSON(state,{compact=true})); h.close()
end

-------------------- State --------------------
local state = load() or {
  name = "Mochi",
  hunger = 25, mood = 75, dirt = 20, energy = 70, health = 90,
  age = 0, coins = 25,
  quests = nil,
  questSeed = os.epoch and os.epoch("utc") or os.time(),
  inventory = { Ball=0, Snack=0, Badeset=0, EnergyDrink=0 }, -- NEU
}

-------------------- Helpers --------------------
local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function healthRecalc()
  local p=0
  p=p+math.max(0,state.hunger-40)*0.10
  p=p+math.max(0,state.dirt-40)*0.08
  p=p+math.max(0,40-state.energy)*0.08
  state.health = clamp(100-p,0,100)
end
local function moodRecalc()
  local m=50+(state.energy-50)*0.2+(50-state.hunger)*0.2+(50-state.dirt)*0.15+(state.health-50)*0.25
  state.mood=clamp(m,0,100)
end
local function face()
  if state.health<30 then return "(x_x)"
  elseif state.mood>=70 then return "^_^"
  elseif state.mood>=40 then return "-_-"
  else return "T_T" end
end
local function bar(x,y,w,val,goodHigh)
  local pct=clamp(val,0,100)/100
  local filled=math.floor(w*pct+0.5)
  local good=goodHigh and colors.lime or colors.orange
  local bad =goodHigh and colors.red  or colors.cyan
  local col =(pct>=0.6) and good or ((pct>=0.3) and colors.yellow or bad)
  setBG(colors.gray); term.setCursorPos(x,y); term.write((" "):rep(w))
  setBG(col); term.setCursorPos(x,y); term.write((" "):rep(filled))
  setBG(colors.black)
end

-------------------- Buttons & Layout --------------------
local btns = {
  {label="Füttern",    id="feed"},
  {label="Spielen",    id="play"},
  {label="Waschen",    id="clean"},
  {label="Schlafen",   id="sleep"},
  {label="Streicheln", id="pet"},
  {label="Shop",       id="shop"},
  {label="Quests",     id="quests"},
  {label="Inventar",   id="inv"},   -- NEU
  {label="Name",       id="name"},
  {label="Beenden",    id="quit"},
}
local function layoutButtons()
  local x, y = 2, H()-4
  local maxW=W()-2
  for i,b in ipairs(btns) do
    b.w = #b.label + 4
    if x + b.w > maxW then x=2; y=y+1 end
    b.x, b.y = x, y
    x = x + b.w + 1
  end
end
local function drawButtons()
  layoutButtons()
  for _,b in ipairs(btns) do
    setBG(colors.gray); setFG(colors.black)
    term.setCursorPos(b.x,b.y); term.write(" "..b.label.." ")
    setBG(colors.black); setFG(colors.white)
  end
end
local function btnAt(x,y)
  for _,b in ipairs(btns) do
    if y==b.y and x>=b.x and x<b.x+b.w then return b end
  end
end

-------------------- Items (Shop & Inventar) --------------------
local function use_Ball()
  state.mood=clamp(state.mood+20,0,100); beep(true)
end
local function use_Snack()
  state.hunger=clamp(state.hunger-25,0,100); state.energy=clamp(state.energy+5,0,100); beep(true)
end
local function use_Badeset()
  state.dirt=clamp(state.dirt-40,0,100); beep(true)
end
local function use_EnergyDrink()
  state.energy=clamp(state.energy+30,0,100); state.hunger=clamp(state.hunger+10,0,100); beep(true)
end

local itemDefs = {
  {key="Ball",        price=10, desc="+ Laune",                 use=use_Ball},
  {key="Snack",       price=12, desc="Hunger ↓, Energie ↑",     use=use_Snack},
  {key="Badeset",     price=15, desc="Schmutz ↓↓",              use=use_Badeset},
  {key="EnergyDrink", price=18, desc="Energie ↑, etwas Hunger", use=use_EnergyDrink},
}

-------------------- Shop (Touch-first) --------------------
local function drawSoftbar(left, mid, right)
  local y=H()
  setBG(colors.black); setFG(colors.lightGray)
  local lw=""; if left then lw="[ "..left.." ] " end
  local mw=""; if mid then mw="[ "..mid.." ] " end
  local rw=""; if right then rw="[ "..right.." ]" end
  local line=lw..mw..rw
  center(y, line, colors.lightGray)
  -- Buttons-Hitboxen grob merken (einfach via Textspalte suchen)
end

local function drawShop(sel)
  clr()
  center(1,"SHOP",colors.yellow)
  center(2,"Coins: "..state.coins,colors.cyan)
  center(3,"Tippe [▲]/[▼] oder den Artikel. [Kaufen]/[Zurück] unten.",colors.lightGray)
  for i,it in ipairs(itemDefs) do
    local y=4+i
    local line=string.format("%d) %-12s  %3d  - %s", i, it.key, it.price, it.desc)
    if sel==i then setBG(colors.gray); setFG(colors.black) end
    center(y,line)
    if sel==i then setBG(colors.black); setFG(colors.white) end
  end
  drawSoftbar("▲", "Kaufen", "▼")
  -- extra zurück button oben rechts
  local tx=W()-10; local ty=1; term.setCursorPos(tx,ty); setFG(colors.black); setBG(colors.orange); term.write(" Zurück "); setBG(colors.black); setFG(colors.white)
  return {back={x=tx,y=ty,w=8,h=1}}
end

local function inBox(x,y,box) return box and y==box.y and x>=box.x and x<box.x+box.w end

local function shopLoop()
  local sel=1
  local ui=drawShop(sel)
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="mouse_click" or e=="monitor_touch" then
      local x,y=(e=="mouse_click") and b or b, (e=="mouse_click") and c or c
      if inBox(x,y,ui.back) then return end
      -- Klick auf Liste?
      local idx=y-4
      if idx>=1 and idx<=#itemDefs then sel=idx; ui=drawShop(sel) goto cont end
      -- Softbar: Wir werten grob die horizontale Position aus
      if y==H() then
        if x < W()/3 then sel=math.max(1,sel-1); ui=drawShop(sel)
        elseif x > 2*W()/3 then sel=math.min(#itemDefs,sel+1); ui=drawShop(sel)
        else
          local it=itemDefs[sel]
          if state.coins>=it.price then
            state.coins=state.coins-it.price
            state.inventory[it.key]=(state.inventory[it.key] or 0)+1  -- NEU: ins Inventar
            healthRecalc(); moodRecalc(); save(state); ui=drawShop(sel); beep(true)
          else beep(false) end
        end
      end
    elseif e=="key" then
      if a==keys.escape then return end
      if a==keys.up then sel=math.max(1,sel-1); ui=drawShop(sel)
      elseif a==keys.down then sel=math.min(#itemDefs,sel+1); ui=drawShop(sel)
      elseif a==keys.enter then
        local it=itemDefs[sel]
        if state.coins>=it.price then
          state.coins=state.coins-it.price
          state.inventory[it.key]=(state.inventory[it.key] or 0)+1
          healthRecalc(); moodRecalc(); save(state); ui=drawShop(sel); beep(true)
        else beep(false) end
      end
    end
    ::cont::
  end
end

-------------------- Inventar (Touch-first) --------------------
local function drawInv(sel)
  clr()
  center(1,"INVENTAR",colors.yellow)
  center(2,"Tippe Item zum Auswählen. Unten: [Benutzen]/[Zurück]",colors.lightGray)
  local y=4
  for i,it in ipairs(itemDefs) do
    local cnt=state.inventory[it.key] or 0
    local line=string.format("%d) %-12s  x%2d  - %s", i, it.key, cnt, it.desc)
    if sel==i then setBG(colors.gray); setFG(colors.black) end
    center(y,line)
    if sel==i then setBG(colors.black); setFG(colors.white) end
    y=y+1
  end
  drawSoftbar(nil, "Benutzen", "Zurück")
end

local function invLoop()
  local sel=1
  drawInv(sel)
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="mouse_click" or e=="monitor_touch" then
      local x,y=(e=="mouse_click") and b or b, (e=="mouse_click") and c or c
      -- Auswahl
      local idx=y-3
      if idx>=1 and idx<=#itemDefs then sel=idx; drawInv(sel) goto cont end
      if y==H() then
        -- Mitte: Benutzen
        if x >= W()/3 and x <= 2*W()/3 then
          local it=itemDefs[sel]
          if (state.inventory[it.key] or 0) > 0 then
            state.inventory[it.key]=state.inventory[it.key]-1
            it.use(); healthRecalc(); moodRecalc(); save(state)
            drawInv(sel)
          else beep(false) end
        else
          -- Rechte Seite ~ Zurück
          if x > 2*W()/3 then return end
        end
      end
    elseif e=="key" then
      if a==keys.escape then return end
      if a==keys.up then sel=math.max(1,sel-1); drawInv(sel)
      elseif a==keys.down then sel=math.min(#itemDefs,sel+1); drawInv(sel)
      elseif a==keys.enter then
        local it=itemDefs[sel]
        if (state.inventory[it.key] or 0) > 0 then
          state.inventory[it.key]=state.inventory[it.key]-1
          it.use(); healthRecalc(); moodRecalc(); save(state)
          drawInv(sel)
        else beep(false) end
      end
    end
    ::cont::
  end
end

-------------------- Quests --------------------
local function newQuests(seed)
  math.randomseed(seed or (os.epoch and os.epoch("utc") or os.time()))
  local pool = {
    {id="mood80",   text="Laune >= 80 erreichen",   done=function() return state.mood>=80 end,   reward=15},
    {id="clean20",  text="Schmutz <= 20 halten",    done=function() return state.dirt<=20 end,   reward=12},
    {id="feed2",    text="2x Füttern",              counter=0, need=2, onAct="feed",  reward=10},
    {id="play3",    text="3x Spielen",              counter=0, need=3, onAct="play",  reward=12},
    {id="sleep1",   text="1x Schlafen",             counter=0, need=1, onAct="sleep", reward=8},
  }
  local picks={}
  while #picks<3 and #pool>0 do
    local i=math.random(#pool); table.insert(picks, pool[i]); table.remove(pool,i)
  end
  return picks
end
if not state.quests then state.quests = newQuests(state.questSeed) end

local function questProgress(actId)
  for _,q in ipairs(state.quests) do
    if q.onAct and q.onAct==actId then q.counter=(q.counter or 0)+1 end
  end
end
local function questCheckRewards()
  local changed=false
  for _,q in ipairs(state.quests) do
    if not q.doneFlag then
      local ok=false
      if q.onAct then ok = (q.counter or 0) >= (q.need or 1)
      else ok = q.done() end
      if ok then
        q.doneFlag=true; state.coins=state.coins+(q.reward or 5); changed=true; beep(true)
      end
    end
  end
  if changed then save(state) end
end

local function drawQuests()
  clr()
  center(1,"QUESTS",colors.yellow)
  center(2,"Coins: "..state.coins,colors.cyan)
  for i,q in ipairs(state.quests) do
    local y=3+i
    local status = q.doneFlag and "(Erledigt +"..q.reward..")" or
                   (q.onAct and string.format("(%d/%d, +%d)", q.counter or 0, q.need or 1, q.reward) or "(+"..q.reward..")")
    center(y, string.format("%d) %s  %s", i, q.text, status), q.doneFlag and colors.lime or colors.white)
  end
  drawSoftbar("Zurück", "Neu würfeln (-5c)")
end
local function questsLoop()
  drawQuests()
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="mouse_click" or e=="monitor_touch" then
      local x,y=(e=="mouse_click") and b or b, (e=="mouse_click") and c or c
      if y==H() then
        if x < W()/3 then return end                -- Zurück
        -- Mitte ~ Neu würfeln
        if x >= W()/3 and x <= 2*W()/3 then
          if state.coins>=5 then
            state.coins=state.coins-5
            state.questSeed=(state.questSeed+137)%100000
            state.quests=newQuests(state.questSeed); save(state)
            drawQuests(); beep(true)
          else beep(false) end
        end
      else
        return
      end
    elseif e=="key" then
      if a==keys.escape then return end
      if a==keys.r then
        if state.coins>=5 then
          state.coins=state.coins-5
          state.questSeed=(state.questSeed+137)%100000
          state.quests=newQuests(state.questSeed); save(state)
          drawQuests(); beep(true)
        else beep(false) end
      end
    end
  end
end

-------------------- Name Change --------------------
local function changeName()
  clr()
  center(2,"NAMEN ÄNDERN",colors.yellow)
  center(4,"Gib neuen Namen ein und drücke Enter.",colors.lightGray)
  term.setCursorPos(3,6); setFG(colors.cyan); term.write("> ")
  setFG(colors.white)
  local new = read()
  if new and new~="" then
    state.name=new; pcall(os.setComputerLabel,new); save(state); beep(true)
  else
    beep(false)
  end
end

-------------------- Actions --------------------
local function act_feed()  state.hunger=clamp(state.hunger-35,0,100); state.energy=clamp(state.energy+5,0,100); questProgress("feed");  beep(true) end
local function act_play()  state.mood=clamp(state.mood+18,0,100);   state.energy=clamp(state.energy-10,0,100); state.hunger=clamp(state.hunger+8,0,100); questProgress("play");  beep(true) end
local function act_clean() state.dirt=clamp(state.dirt-40,0,100);   beep(true) end
local function act_sleep() state.energy=clamp(state.energy+35,0,100); state.hunger=clamp(state.hunger+10,0,100); questProgress("sleep"); beep(true) end
local function act_pet()   state.mood=clamp(state.mood+12,0,100);   beep(true) end
local actions = {feed=act_feed, play=act_play, clean=act_clean, sleep=act_sleep, pet=act_pet}

-------------------- Main Draw --------------------
local function draw()
  clr()
  center(1,"VIRTUAL PET",colors.yellow)
  center(2, state.name.."  "..face(), colors.cyan)
  center(3, "Coins: "..state.coins, colors.lightBlue)

  local x0=4; local w=W()-8
  term.setCursorPos(x0,5);  term.write("Gesundheit"); bar(x0,6,w,state.health,true)
  term.setCursorPos(x0,8);  term.write("Laune");     bar(x0,9,w,state.mood,true)
  term.setCursorPos(x0,11); term.write("Hunger");    bar(x0,12,w,state.hunger,false)
  term.setCursorPos(x0,14); term.write("Schmutz");   bar(x0,15,w,state.dirt,false)
  term.setCursorPos(x0,17); term.write("Energie");   bar(x0,18,w,state.energy,true)

  drawButtons()
  center(H(), ("Alter: %d min  |  Autosave an"):format(state.age), colors.lightGray)
end

-------------------- Loop --------------------
local tickSec,autosaveSec=2,60
local tTick=os.startTimer(tickSec)
local tSave=os.startTimer(autosaveSec)
draw()

while true do
  local e,a,b,c=os.pullEvent()
  if e=="timer" and a==tTick then
    state.hunger=clamp(state.hunger+3,0,100)
    state.dirt  =clamp(state.dirt+2,0,100)
    state.energy=clamp(state.energy-2,0,100)
    healthRecalc(); moodRecalc(); questCheckRewards(); draw()
    tTick=os.startTimer(tickSec)
  elseif e=="timer" and a==tSave then
    state.age=state.age+1; save(state); tSave=os.startTimer(autosaveSec)
  elseif e=="monitor_touch" or e=="mouse_click" then
    local x,y = b,c
    local btn=btnAt(x,y)
    if btn then
      if btn.id=="quit" then save(state); break
      elseif btn.id=="shop" then shopLoop(); draw()
      elseif btn.id=="quests" then questsLoop(); draw()
      elseif btn.id=="inv" then invLoop(); draw()                 -- NEU
      elseif btn.id=="name" then changeName(); draw()
      else local f=actions[btn.id]; if f then f(); healthRecalc(); moodRecalc(); questCheckRewards(); draw() end
      end
    end
  elseif e=="key" then
    if a==keys.q then save(state); break
    elseif a==keys.s then shopLoop(); draw()
    elseif a==keys.j then questsLoop(); draw()
    elseif a==keys.n then changeName(); draw()
    elseif a==keys.i then invLoop(); draw()
    else
      -- optional: Tastatur-Shortcuts (nicht nötig für Touch)
      if a==keys.one  then actions.feed();  healthRecalc(); moodRecalc(); questCheckRewards(); draw()
      elseif a==keys.two  then actions.play();  healthRecalc(); moodRecalc(); questCheckRewards(); draw()
      elseif a==keys.three then actions.clean(); healthRecalc(); moodRecalc(); questCheckRewards(); draw()
      elseif a==keys.four  then actions.sleep(); healthRecalc(); moodRecalc(); questCheckRewards(); draw()
      elseif a==keys.five  then actions.pet();   healthRecalc(); moodRecalc(); questCheckRewards(); draw()
      end
    end
  end
end

if mon then term.redirect(termNative) end
termNative.setBackgroundColor(colors.black); termNative.setTextColor(colors.white)
termNative.clear(); termNative.setCursorPos(1,1)
print("Pet gespeichert. Bis bald, "..state.name.."!")
