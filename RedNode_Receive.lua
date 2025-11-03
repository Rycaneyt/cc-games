-- pocket_recv.lua — Empfängt Dateien über Rednet direkt auf den Pocket-Computer
-- Nutzung: pocket_recv [zielOrdner]

local tArgs = {...}
local destRoot = tArgs[1] or "."
if destRoot:sub(-1) ~= "/" then destRoot = destRoot.."/" end

local function findWirelessModem()
  if rednet.isOpen() then return true end
  for _,side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      return true
    end
  end
  return false
end

if not findWirelessModem() then
  print("Kein Modem gefunden! Bitte Modem anbringen und aktivieren.")
  return
end

rednet.host("ccxfer", "RECEIVER")
print("Empfangsbereit – speichere unter:", destRoot)

local function mkdirs(path)
  local parts = {}
  for part in string.gmatch(path, "[^/]+") do table.insert(parts, part) end
  local p = ""
  for i=1,#parts-1 do
    p = p == "" and parts[i] or (p.."/"..parts[i])
    if not fs.exists(p) then fs.makeDir(p) end
  end
end

local function writeFile(path, data)
  mkdirs(path)
  local h=fs.open(path,"w")
  h.write(data)
  h.close()
end

while true do
  local id,msg = rednet.receive("ccxfer")
  if type(msg) == "table" and msg.t == "hello" then
    rednet.send(id, {t="hello_ack", ok=true, destRoot=destRoot}, "ccxfer")
  elseif type(msg) == "table" and msg.t == "dir_meta" then
    local path = destRoot .. msg.relPath
    if not fs.exists(path) then fs.makeDir(path) end
    rednet.send(id, {t="ack_dir", ok=true}, "ccxfer")
  elseif type(msg) == "table" and msg.t == "file_meta" then
    print("Empfange:", msg.relPath, "("..msg.size.."B)")
    local buffer = ""
    for i=1, math.ceil(msg.size / 8192) do
      local _,chunk = rednet.receive("ccxfer")
      if chunk and chunk.data then
        buffer = buffer .. chunk.data
        rednet.send(id, {t="ack", ok=true, idx=i}, "ccxfer")
      end
    end
    writeFile(destRoot .. msg.relPath, buffer)
    print("✔ Fertig:", msg.relPath)
  end
end
