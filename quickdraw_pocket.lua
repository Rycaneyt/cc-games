-- quickdraw_pocket.lua — QuickDraw Duel Client (Pocket)
-- Features: Namenseingabe (persistiert via Label), Early-Lockout, Statusanzeige

---------------------- Konfiguration ----------------------
local MATCH_CODE = "QD123"   -- muss zum Server passen
-----------------------------------------------------------

local modem = peripheral.find("modem"); assert(modem, "Kein Modem!")
rednet.open(peripheral.getName(modem))

local function clr(fg,bg) term.setTextColor(fg or colors.white); term.setBackgroundColor(bg or colors.black) end
local function center(y, txt, fg, bg)
  local w,h = term.getSize(); clr(fg,bg)
  term.setCursorPos(math.floor((w-#txt)/2)+1, y); term.write(txt)
  clr()
end
local function screen(title, subtitle, colorTitle, colorSub)
  term.clear(); center(2, title or "", colorTitle or colors.yellow)
  if subtitle then center(4, subtitle, colorSub or colors.lightGray) end
end

-- Name mit Default (persistiert im Computer-Label)
term.clear()
local defaultName = os.getComputerLabel() or ("Pocket"..os.getComputerID())
print("Dein Name (Enter = '"..defaultName.."'):")
local inName = read()
local NAME = (inName and inName~="") and inName or defaultName
pcall(os.setComputerLabel, NAME)

-- Server beitreten
screen("QuickDraw Duel", "Verbinde...")
rednet.broadcast({code=MATCH_CODE, name=NAME}, "qd_join")
local srv, ack = rednet.receive("qd_ack", 6)
assert(srv and ack and ack.ok, "Kein Server gefunden / falscher Code.")
if ack.name and ack.name~=NAME then NAME=ack.name; pcall(os.setComputerLabel, NAME) end
screen("QuickDraw Duel", "Verbunden als: "..NAME, colors.yellow, colors.cyan); sleep(1)

-- Spielschleife
while true do
  -- Warte auf Runde
  screen("Bereit machen...", "Warte auf Signal. NICHT drücken!", colors.orange, colors.red)
  local goTime = nil
  local early = false

  -- Warten bis GO; Eingaben vor GO -> "early"
  while true do
    local e,a,b,c = os.pullEvent()
    if e=="rednet_message" and b and type(b)=="table" and c=="qd_evt" then
      if b.type=="ready" then
        -- ignore; Anzeige bleibt
      elseif b.type=="go" then
        goTime = b.t0 or true
        screen("JETZT!!!", "DRÜCK JETZT!", colors.lime, colors.white)
        break
      elseif b.type=="end" then
        screen("Match Ende", "Sieger: "..(b.winner or "?"), colors.lime, colors.white); sleep(3)
      end
    elseif e=="mouse_click" or e=="key" then
      -- zu früh
      rednet.broadcast({code=MATCH_CODE, action="early"}, "qd_click")
      screen("Zu früh!", "Warte auf nächste Runde...", colors.red, colors.lightGray)
      early = true
      sleep(2)
      break
    end
  end

  -- Wenn Early, Runde für diesen Client vorbei – Server macht weiter
  if early then goto continue end

  -- Reaktionsphase: erste Eingabe -> "press"
  while true do
    local e = {os.pullEvent()}
    if e[1]=="mouse_click" or e[1]=="key" then
      rednet.broadcast({code=MATCH_CODE, action="press"}, "qd_click")
      screen("GESCHAFFT!", "Warte auf Auswertung...", colors.lime, colors
