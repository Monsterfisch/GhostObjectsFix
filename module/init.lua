-- Ghost Objects Fix
--
-- The game keeps the small objects ("entities": flags, projectiles, dust and spray clouds,
-- smoke, birds ...) of each tile in a linked list: a head word per tile and a "next" word in
-- each entity record (ids below 25 use a separate head byte per tile). Every list is drawn on
-- its own tile, at most 10 entries each.
--
-- The lists get tangled: an entity is freed while some list still reaches it (the entity
-- update frees an entity whose "next" is itself; when it is the head of its tile, the tile
-- keeps pointing at the freed slot, and unlinking gives up after 100 steps or when the entity
-- is not where its tile says). The next entity created in that slot - a tower flag, a stone,
-- an arrow - is drawn on that old tile too, and its "next" joins the lists of two tiles.
-- Saved games and maps keep the tangle. Seen on Reconquista_Trail_4: a player's tower flag
-- drawn over a river, flickering as the spray clouds in front of it came and went.
--
-- Fix: at the start of the entity update, every few updates, rebuild all lists from the tile
-- each living entity really stands on (its own tile field, the one the game's unlink uses).
-- Nothing walks a list at that moment.

-- the entity update: push ecx / push ebx / push ebp / push esi / mov esi, ecx /
-- mov ecx, [tick] / mov eax, 0x66666667 / imul ecx / sar edx, 2
-- Match the unique body even when the first six bytes have been overwritten.
local UPDATE_AOB = "8B 0D ? ? ? ? B8 67 66 66 66 F7 E9 C1 FA 02 8B C2 C1 E8 1F 03 C2 8D 04 80 03 C0 2B C8 75 07 C7 46 08 19 00 00 00"
local UPDATE_BYTES = { 0x51, 0x53, 0x55, 0x56, 0x8B, 0xF1 }
local CHAIN_OPCODE, CHAIN_PADDING = 0xE9, 0x90

-- the unlink: its head byte array at +0x2A, its head word array at +0x78
local UNLINK_AOB = "53 55 56 8B 74 24 10 8B C6 69 C0 E8 00 00 00 57 8D 3C 08 8B 47 60 33 ED 33 DB 3B C5 0F 84 ? ? ? ? 83 FE 19 7D 4D 0F B6 90"
local UNLINK = { byteHead = 0x2A, byteHeadOp = { 0x0F, 0xB6, 0x90 }, wordHead = 0x78, wordHeadOp = { 0x0F, 0xBF, 0x14, 0x45 } }

-- the seagull removal loop: `cmp ecx, <entity slots>` at +0x40
local GULLS_AOB = "B9 01 00 00 00 56 89 0D ? ? ? ? BE 02 00 00 00 8B C1 69 C0 E8 00 00 00 66 39 B0"
local GULLS = { cap = 0x42, capOp = { 0x81, 0xF9 } }

local TILES = 80400           -- 400 x 400 diamond
local BYTE_IDS = 0x19         -- ids below this use the byte heads

local DEFAULTS = { enabled = true, interval = 10 }

local TEMPLATE = [[
pushad
pushfd
dec dword [COUNTDOWN]
jg og_done
mov dword [COUNTDOWN], INTERVAL
mov ebx, ecx
cld
xor eax, eax
mov edi, WORD_HEAD
mov ecx, TILES / 2
rep stosd
mov edi, BYTE_HEAD
mov ecx, TILES / 4
rep stosd
mov esi, CAP - 1
og_loop:
mov eax, esi
imul eax, eax, 0xE8
add eax, ebx
cmp word [eax + 0x3C], 0
je og_unlinked
mov edx, [eax + 0x60]
test edx, edx
jle og_unlinked
cmp edx, TILES
jae og_bad
cmp esi, BYTE_IDS
jge og_word
movzx ecx, byte [edx + BYTE_HEAD]
mov [eax + 0x32], cx
mov ecx, esi
mov [edx + BYTE_HEAD], cl
jmp og_next
og_word:
mov cx, [edx * 2 + WORD_HEAD]
mov [eax + 0x32], cx
mov [edx * 2 + WORD_HEAD], si
jmp og_next
og_bad:
mov dword [eax + 0x60], 0
og_unlinked:
mov word [eax + 0x32], 0
og_next:
dec esi
jnz og_loop
og_done:
popfd
popad
TAIL
]]

local PROLOGUE_TAIL = [[
push ecx
push ebx
push ebp
push esi
mov esi, ecx
jmp BACK]]
local CHAIN_TAIL = [[
jmp CHAIN]]

local function scan(pattern, what)
  local ok, address = pcall(core.AOBScan, pattern)
  if not ok or address == nil or address == 0 then
    log(WARNING, "ghost-objects-fix: " .. what .. " not found; nothing changed")
    return nil
  end
  return address
end

local function bytesAre(address, expected)
  for i, byte in ipairs(expected) do
    if core.readByte(address + i - 1) & 0xFF ~= byte then return false end
  end
  return true
end

local function setting(config, name)
  if type(config) == "table" and config[name] ~= nil then return config[name] == true end
  return DEFAULTS[name]
end

local function number(config, name, low, high)
  local value = type(config) == "table" and tonumber(config[name]) or nil
  if value == nil then value = DEFAULTS[name] end
  return math.max(low, math.min(high, math.floor(value)))
end

local M = {}

function M:enable(config)
  if not setting(config, "enabled") then return end
  local body = scan(UPDATE_AOB, "the entity update")
  if not body then return end
  local duplicate = core.scanForAOB(UPDATE_AOB, body + 1)
  if duplicate and duplicate ~= 0 then
    error("ghost-objects-fix: the entity update signature is ambiguous")
  end
  local update = body - #UPDATE_BYTES
  local chain
  if not bytesAre(update, UPDATE_BYTES) then
    if core.readByte(update) ~= CHAIN_OPCODE or core.readByte(update + 5) ~= CHAIN_PADDING then
      log(WARNING, "ghost-objects-fix: another module changed the start of the entity update; nothing changed")
      return
    end
    chain = (update + 5 + core.readInteger(update + 1)) % 4294967296
  end
  local unlink = scan(UNLINK_AOB, "the entity tile list walker")
  local gulls = scan(GULLS_AOB, "the seagull removal")
  if not unlink or not gulls then return end
  if not bytesAre(unlink + UNLINK.byteHead - 3, UNLINK.byteHeadOp)
      or not bytesAre(unlink + UNLINK.wordHead - 4, UNLINK.wordHeadOp)
      or not bytesAre(gulls + GULLS.cap - 2, GULLS.capOp) then
    log(WARNING, "ghost-objects-fix: the entity code is not the one this module knows; nothing changed")
    return
  end
  local byteHead = core.readInteger(unlink + UNLINK.byteHead)
  local wordHead = core.readInteger(unlink + UNLINK.wordHead)
  local cap = core.readInteger(gulls + GULLS.cap)
  if byteHead - wordHead ~= TILES * 2 or cap < 100 or cap > 20000 then
    log(WARNING, "ghost-objects-fix: unexpected entity tables; nothing changed")
    return
  end
  local interval = number(config, "interval", 1, 500)
  local countdown = core.allocate(4, true)
  local function resetCountdown()
    core.writeInteger(countdown, interval)
  end
  resetCountdown()
  modules["map-extensions"]:registerSection("ghost-objects-fix", {
    initialize = resetCountdown,
    deserialize = resetCountdown,
    serialize = function() end,
  })
  local script = TEMPLATE:gsub("TAIL", chain and CHAIN_TAIL or PROLOGUE_TAIL)
  local stub = core.allocateAssembly(script, {
    COUNTDOWN = countdown, INTERVAL = interval, WORD_HEAD = wordHead, BYTE_HEAD = byteHead,
    TILES = TILES, CAP = cap, BYTE_IDS = BYTE_IDS, BACK = update + #UPDATE_BYTES, CHAIN = chain or 0,
  })
  core.writeCode(update, { 0xE9, core.itob(core.getRelativeAddress(update, stub, -5)), 0x90 })
  log(INFO, string.format("ghost-objects-fix: tile object lists are rebuilt every %d entity updates (%d slots)%s",
    interval, cap, chain and ", chained to the existing entity update hook" or ""))
end

function M:disable() end

return M
