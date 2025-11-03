-- pocket_recv_v2.lua — stabiler ccxfer-Empfänger für Pocket Computer
-- Nutzung: pocket_recv_v2 [Zielordner]
-- Beispiel: pocket_recv_v2 downloads/

-------------------------
-- Hilfsfunktionen     --
-------------------------
local function allSides()
  if peripheral and peripheral.getNames then
    return peripheral.getNames()
  elseif rs and rs.getSides then
    return rs.getSides()
  else
    return {"left","right","top","bottom","front","back"}
  end
end

local function openWirelessModem()
  if rednet.isOpen() then return true end
  for _,n in ipairs(allSides()) do
    local t = peripheral.getType and peripheral.getType(n)
    if t == "modem" then
      local m = peripheral.wrap(n)
      if m and m.isWireless and m.isWireless() then
        rednet.open(n)
        return true
      end
    end
  end
  return false
end

local function mkdirs(path)
  local parts, p = {}, ""
  for part in string.gmatch(path, "[^/]+") do table.insert(parts, part) end
  for i=1,#parts-1 do
    p = (p=="" and parts[i]) or (p.."/"..parts[i])
    if not fs.exists(p) then fs.makeDir(p) end
  end
end

local function writeFile(path, data, mode)
  mkdirs(path)
  local h = fs.open(path, mode or "w")
  h.write(data or "")
  h.close()
end

-------------------------
-- Setup / Argumente   --
-------------------------
local tArgs = {...}
local destRoot = tArgs[1] or "."
if destRoot:sub(-1) ~= "/" then destRoot = destRoot.."/" end

local CHUNK = 4096       -- kleinere Blöcke = stabiler
local RX_TIMEOUT = 20    -- Sekunden pro Paket warten

print("[recv] Ziel:", destRoot)
if not fs.exists(destRoot) then fs.makeDir(destRoot) end

if not openWirelessModem() then
  print("[recv] Kein Wireless-Modem gefunden oder nicht aktiv!")
  return
end

rednet.host("ccxfer", "RECEIVER")
print("[recv] Hosted as ccxfer/RECEIVER  ID:", os.getComputerID())

-------------------------
-- Hauptprogramm       --
-------------------------
while true do
  local id, msg = rednet.receive("ccxfer")
  if type(msg) ~= "table" or not msg.t then
    -- ignorieren
  elseif msg.t == "hello" then
    print("[recv] HELLO von", id)
    rednet.send(id, {t="hello_ack", ok=true, destRoot=destRoot}, "ccxfer")

  elseif msg.t == "dir_meta" then
    local rel = msg.relPath or ""
    local path = destRoot .. rel
    if rel == "" then
      rednet.send(id, {t="ack_dir", ok=true, relPath=rel}, "ccxfer")
    else
      if not fs.exists(path) then fs.makeDir(path) end
      print("[recv] DIR  :", rel)
      rednet.send(id, {t="ack_dir", ok=true, relPath=rel}, "ccxfer")
    end

  elseif msg.t == "file_meta" then
    local rel = msg.relPath
    local size = tonumber(msg.size or 0)
    local total = (size > 0) and math.ceil(size / CHUNK) or 0
    if not rel or rel == "" then
      rednet.send(id, {t="ack_file_meta", ok=false, relPath=rel, err="no relPath"}, "ccxfer")
    else
      local target = destRoot .. rel
      mkdirs(target)
      local h = fs.open(target,"w") h.close()
      print(string.format("[recv] FILE : %s (%d B) chunks=%d", rel, size, total))
      rednet.send(id, {t="ack_file_meta", ok=true, relPath=rel, resume=0}, "ccxfer")

      -- Chunks empfangen
      for idx = 1, total do
        local rid, chunk = rednet.receive("ccxfer", RX_TIMEOUT)
        if rid ~= id or type(chunk) ~= "table" or chunk.t ~= "chunk" or chunk.relPath ~= rel then
          print("[recv] Fehler/Timeout bei Chunk", idx, "-> Abbruch")
          rednet.send(id, {t="ack", ok=false, relPath=rel, idx=idx, err="timeout"}, "ccxfer")
          rel = nil
          break
        end
        writeFile(target, chunk.data or "", "a")
        local pct = math.floor((idx/total)*100 + 0.5)
        print(string.format("  ▸ %s  [%d/%d] ~%d%%", rel, idx, total, pct))
        rednet.send(id, {t="ack", ok=true, relPath=rel, idx=idx}, "ccxfer")
      end

      -- Abschluss bestätigen
      if rel then
        local _, endmsg = rednet.receive("ccxfer", RX_TIMEOUT)
        if type(endmsg) == "table" and endmsg.t == "end_file" and endmsg.relPath == rel then
          rednet.send(id, {t="end_ack", ok=true, relPath=rel}, "ccxfer")
          print("  ✔ fertig:", rel)
        else
          print("[recv] end_file fehlte oder Timeout:", rel)
        end
      end
    end

  else
    print("[recv] Unbekannter Typ:", tostring(msg.t))
  end
end
