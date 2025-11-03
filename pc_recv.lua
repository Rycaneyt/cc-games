-- pc_recv.lua  —  Empfängt Dateien/Ordner über rednet und schreibt sie nach <destRoot> (z.B. "disk/")
-- Start: pc_recv [destRoot]
-- Beispiel: pc_recv disk/
-- Auto-Discovery-Name: host("ccxfer","RECEIVER")

-- ========= Utilities =========
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

local function adler32(str)
  -- einfache Prüfsumme (integers gefittet), ausreichend für Transportkontrolle
  local MOD = 65521
  local a,b = 1,0
  for i=1,#str do
    a = (a + string.byte(str, i)) % MOD
    b = (b + a) % MOD
  end
  return string.format("%08x", (b << 16) ~ a)
end

local function mkdirs(path)
  -- erstellt alle Zwischenordner
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

local function readPartial(path)
  if not fs.exists(path) then return "" end
  local h=fs.open(path,"r")
  local d=h.readAll() or ""
  h.close()
  return d
end

-- ========= Config / Args =========
local destRoot = arg and arg[1] or ...
if not destRoot or destRoot == "" then destRoot = "." end
if destRoot:sub(-1) ~= "/" then destRoot = destRoot.."/" end

if not findWirelessModem() then
  print("Kein Wireless-Modem gefunden/aktiv. Bitte Modem anbauen & aktivieren.")
  return
end

rednet.host("ccxfer", "RECEIVER")
print("Empfang bereit. Ziel:", destRoot, "(hosted as ccxfer/RECEIVER)")

-- ========= Protokoll =========
-- Nachrichten sind Tabellen mit field 't':
-- t="hello"        {version, wants="send", rootRel=true/false}
-- t="file_meta"    {relPath, size, checksum, mode="file"}
-- t="dir_meta"     {relPath, mode="dir"}
-- t="chunk"        {relPath, idx, total, data}
-- t="end_file"     {relPath}
-- Acks:            send back {ok=true,t="ack",relPath=..., idx=?} bzw. Fehler {ok=false,err="..."}

local sessions = {}

local function handleHello(id, msg)
  -- Klar antworten, ob destRoot existiert/Schreibbar ist
  if not fs.exists(destRoot) then
    fs.makeDir(destRoot)
  end
  rednet.send(id, {t="hello_ack", ok=true, note="ready", destRoot=destRoot}, "ccxfer")
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
  -- Resume: falls Datei existiert, prüfen wie viele vollständige Chunks schon da sind
  local have = 0
  if fs.exists(target) then
    local existing = readPartial(target)
    -- einfache Heuristik: nur wenn size passt, versuchen zu resyncen
    if #existing < m.size then
      have = math.floor(#existing / 8192) -- unsere Chunkgröße (muss Sender matchen)
    else
      -- falls Datei vollständig da, Prüfsumme checken
      if adler32(existing) == m.checksum then
        print("[SKIP] Datei schon vollständig:", m.relPath)
        rednet.send(id, {t="ack_file_meta", ok=true, relPath=m.relPath, resume=math.huge}, "ccxfer")
        return
      end
      -- sonst überschreiben
      local h=fs.open(target,"w") h.close()
      have = 0
    end
  end
  -- leere Datei anlegen (oder truncaten)
  local h=fs.open(target,"w") h.close()
  sessions[m.relPath] = {size=m.size, checksum=m.checksum, received=0, chunks={} }
  rednet.send(id, {t="ack_file_meta", ok=true, relPath=m.relPath, resume=have}, "ccxfer")
  print(string.format("[FILE] %s  (%d B)", m.relPath, m.size))
end

local function handleChunk(id, m)
  local target = destRoot .. m.relPath
  if not sessions[m.relPath] then
    rednet.send(id, {t="ack", ok=false, relPath=m.relPath, idx=m.idx, err="no session"}, "ccxfer"); return
  end
  -- append chunk
  local h=fs.open(target, "a")
  h.write(m.data)
  h.close()
  sessions[m.relPath].received = sessions[m.relPath].received + #m.data
  local pct = math.min(100, math.floor((sessions[m.relPath].received / sessions[m.relPath].size)*100 + 0.5))
  term.setCursorPos(1, select(2, term.getCursorPos()))
  print(string.format("  ▸ %s  [%d/%d]  ~%d%%", m.relPath, m.idx, m.total, pct))
  rednet.send(id, {t="ack", ok=true, relPath=m.relPath, idx=m.idx}, "ccxfer")
end

local function handleEndFile(id, m)
  local target = destRoot .. m.relPath
  if not fs.exists(target) then
    rednet.send(id, {t="end_ack", ok=false, relPath=m.relPath, err="missing file"}, "ccxfer"); return
  end
  local data = readPartial(target)
  local ok = data and (#data > 0)
  if ok then
    -- Prüfsumme gegentesten
    local sum = adler32(data)
    if sessions[m.relPath] and sum ~= sessions[m.relPath].checksum then
      rednet.send(id, {t="end_ack", ok=false, relPath=m.relPath, err="checksum mismatch"}, "ccxfer"); return
    end
  end
  sessions[m.relPath] = nil
  rednet.send(id, {t="end_ack", ok=true, relPath=m.relPath}, "ccxfer")
  print("  ✔ fertig:", m.relPath)
end

-- ========= Loop =========
while true do
  local id, msg, prot = rednet.receive("ccxfer")
  if type(msg) ~= "table" or not msg.t then
    -- ignorieren / fremde Pakete
  else
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
