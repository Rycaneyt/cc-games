-- pocket_recv_v2.lua — Stabiler ccxfer-Empfänger für Pocket-Computer
-- Usage: pocket_recv_v2 [destRoot]
-- Beispiel: pocket_recv_v2 downloads/

-------------------------
-- Helferfunktionen    --
-------------------------
local function allSides()
  if peripheral and peripheral.getNames then
    return peripheral.getNames()
  end
  if rs and rs.getSides then
    return rs.getSides()
  end
  return {"left","right","top","bottom","front","back"}
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
-- Config / Args       --
-------------------------
local tArgs = {...}
local destRoot = tArgs[1] or "."
if destRoot:sub(-1) ~= "/" then destRoot = destRoot.."/" end

local CHUNK = 4096          -- kleinere Blöcke = stabiler
local RX_TIMEOUT = 20       -- Sekunden-Timeout pro Paket

print("[recv] Ziel:", destRoot)
if not fs.exists(destRoot) then fs.makeDir(destRoot) end

if not openWire
