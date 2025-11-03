-- pc_recv.lua  —  Empfängt Dateien/Ordner über rednet und schreibt sie nach <destRoot> (z.B. "disk/")
-- Start: pc_recv [destRoot]
-- Beispiel: pc_recv disk/
-- Auto-Discovery-Name: host("ccxfer","RECEIVER")

-------------------------
-- Bit/Checksum Utils  --
-------------------------
local function bxor(a,b)
  if bit32 and bit32.bxor then return bit32.bxor(a,b) end
  if bit and bit.bxor then return bit.bxor(a,b) end
  error("Weder bit32 noch bit-Modul verfügbar")
end

local function lshift(a,n)
  if bit32 and bit32.lshift then return bit32.lshift(a,n) end
  if bit and bit.blshift then return bit.blshift(a,n) end
  error("Weder bit32 noch bit-Modul verfügbar")
end

local function adler32(str)
  local MOD = 65521
  local a,b = 1,0
  for i=1,#str do
    a = (a + string.byte(str, i)) % MOD
    b = (b + a) % MOD
  end
  return string.format("%08x", bxor(lshift(b, 16), a))
end

-------------------------
-- Helpers             --
-------------------------
local function findWirelessModem()
  if rednet.isOpen() then return true end
  if peripheral and peripheral.getNames then
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "modem" then
        local m = peripheral.wrap(name)
        if m and m.isWireless and m.isWireless() then
          rednet.open(name)
          return true
        end
      end
    end
  end
  return false
end

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

local function readAll(path)
  if not fs.exists(path) then return "" end
  local h=fs.open(path,"r")
  local d=h.readAll() or ""
  h.close()
  return d
end

-------------------------
-- Args / Setup        --
-------------------------
local tArgs = {...}
local destRoot = tArgs[1] or "."
if destRoot:sub(-1) ~= "/" then destRoot = destRoot.."/" end

if not findWirelessModem() then
  print("Kein Wireless-Modem gefunden/aktiv. Bitte Modem anbauen & aktivieren.")
  return
end

rednet.host("ccxfer", "RECEIVER")
if not fs.exists(destRoot) then fs.makeDir(destRoot) end
print("Empfang bereit. Ziel:", destRoot, "(ccxfer/RECEIVER)")

-------------------------
-- Protokoll State     --
-------------------------
-- Nachrichten:
--  t="hello"      {version, wants="send"}
--  t="dir_meta"   {relPath}
--  t="file_meta"  {relPath, size, checksum}
--  t="chunk"      {relPath, idx, total, data}
--  t="end_file"   {relPath}
local sessions = {}
local CHUNK = 8192

local function handleHello(id, msg)
  rednet.send(id, {t="hello_ack", ok=true, destRoot=destRoot}, "ccxfer")
end

local function handleDirMeta(id, m)
  local target = destRoot .. m.relPath
  if not fs.exists(target) then fs.makeDir(target) end
  rednet.send(id, {t="ack_dir", ok=true, relPath=m.relPath}, "ccxfer")
  print("[DIR]  ", m.relPath)
end

local function handleFileMeta(id, m)
  local target = destRoot .. m.relPath
  mkdirs(target)
  local have = 0
  if fs.exists(target) then
    local existing = readAll(target)
    if #existing < m.size then
      have = math.floor(#existing / CHUNK)
    else
      if adler32(existing) == m.checksum then
        print("[SKIP] Datei schon vollständig:", m.relPath)
        rednet.send(id, {t="ack_file_meta", ok=true, relPath=m.relPath, resume=math.huge}, "ccxfer")
        return
      end
      local h=fs.open(target,"w") h.close()
      have = 0
    end
  else
    local h=fs.open(target,"w") h.close()
  end
  sessions[m.relPath] = {size=m.size, checksum=m.checksum, received=0}
  rednet.send(id, {t="ack_file_meta", ok=true, relPath=m.relPath, resume=have}, "ccxfer")
  print(string.format("[FILE] %s  (%d B)", m.relPath, m.size))
end

local function handleChunk(id, m)
  local target = destRoot .. m.relPath
  if not sessions[m.relPath] then
    rednet.send(id, {t="ack", ok=false, relPath=m.relPath, idx=m.idx, err="no session"}, "ccxfer"); return
  end
  local h=fs.open(target, "a")
  h.write(m.data)
  h.close()
  local s = sessions[m.relPath]
  s.received = s.received + #m.data
  local pct = math.min(100, math.floor((s.received / s.size)*100 + 0.5))
  print(string.format("  ▸ %s  [%d/%d]  ~%d%%", m.relPath, m.idx, m.total, pct))
  rednet.send(id, {t="ack", ok=true, relPath=m.relPath, idx=m.idx}, "ccxfer")
end

local function handleEndFile(id, m)
  local target = destRoot .. m.relPath
  if not fs.exists(target) then
    rednet.send(id, {t="end_ack", ok=false, relPath=m.relPath, err="missing file"}, "ccxfer"); return
  end
  local data = readAll(target)
  local s = sessions[m.relPath]
  if s and adler32(data) ~= s.checksum then
    rednet.send(id, {t="end_ack", ok=false, relPath=m.relPath, err="checksum mismatch"}, "ccxfer"); return
  end
  sessions[m.relPath] = nil
  rednet.send(id, {t="end_ack", ok=true, relPath=m.relPath}, "ccxfer")
  print("  ✔ fertig:", m.relPath)
end

-------------------------
-- Main Loop           --
-------------------------
while true do
  local id, msg = rednet.receive("ccxfer")
  if type(msg) == "table" and msg.t then
    if msg.t == "hello" then
      handleHello(id, msg)
    elseif msg.t == "dir_meta" then
      handleDirMeta(id, msg)
    elseif msg.t == "file_meta" then
      handleFileMeta(id, msg)
    elseif msg.t == "chunk" then
      handleChunk(id, msg)
    elseif msg.t == "end_file" then
      handleEndFile(id, msg)
    end
  end
end
