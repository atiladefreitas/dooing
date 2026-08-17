-- Paired devices and the one-time tokens that pair them.
--
-- The QR encodes a short-lived pairing token. A device exchanges it (once)
-- for a long-lived bearer token it presents on every data request. Only the
-- sha256 of the bearer token is stored, so this file leaking does not leak a
-- credential — the same reason a sane server stores password hashes.

local M = {}

local VERSION = 1
local PAIRING_TTL_SECONDS = 600 -- a QR left on screen is valid for 10 minutes

local data = nil

local function empty()
	return {
		version = VERSION,
		devices = {}, -- { id, name, token_sha256, paired_at, last_seen }
		pending = {}, -- token -> { created_at }
	}
end

function M.path()
	return M._path_override or (vim.fn.stdpath("state") .. "/dooing/devices.json")
end

function M.load()
	data = empty()
	local file = io.open(M.path(), "r")
	if not file then
		return data
	end
	local content = file:read("*a")
	file:close()
	if not content or content == "" then
		return data
	end
	local ok, decoded = pcall(vim.json.decode, content)
	if ok and type(decoded) == "table" then
		if type(decoded.devices) == "table" then
			data.devices = decoded.devices
		end
		-- `pending` is deliberately NOT loaded: a pairing token dies with the
		-- session that displayed its QR. Anything else would let a token from
		-- a QR shown last week still pair a device today.
	end
	return data
end

local function ensure_loaded()
	if not data then
		M.load()
	end
	return data
end

-- Temp file + rename, mode 0600 — same shape as bloocky's sidecar writes. A
-- crash mid-write must leave the previous device list, not a truncated file
-- that reads as "no devices are paired".
local function save()
	local path = M.path()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local tmp = path .. ".tmp"
	local fd = vim.uv.fs_open(tmp, "w", tonumber("600", 8))
	if not fd then
		vim.notify("Dooing: could not write " .. tmp, vim.log.levels.ERROR)
		return false
	end
	vim.uv.fs_write(fd, vim.json.encode(data))
	vim.uv.fs_close(fd)
	local ok, err = vim.uv.fs_rename(tmp, path)
	if not ok then
		os.remove(tmp)
		vim.notify("Dooing: could not replace " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	return true
end

--------------------------------------------------------------------------
-- Tokens
--------------------------------------------------------------------------

-- CSPRNG-backed hex string. uv.random blocks only for these few bytes.
local function random_hex(bytes)
	local raw = vim.uv.random(bytes)
	if not raw then
		error("no entropy source available")
	end
	return (raw:gsub(".", function(c)
		return ("%02x"):format(c:byte())
	end))
end

local function prune_pending(now)
	for token, entry in pairs(data.pending) do
		if now - (entry.created_at or 0) > PAIRING_TTL_SECONDS then
			data.pending[token] = nil
		end
	end
end

-- A fresh pairing token for the QR. Kept in memory (and mirrored to the file
-- only as pending state that load() ignores), single-use, short-lived.
function M.new_pairing_token(now)
	ensure_loaded()
	now = now or os.time()
	prune_pending(now)
	local token = random_hex(16)
	data.pending[token] = { created_at = now }
	return token
end

-- Exchange a pairing token for a device identity. The token is consumed
-- whether or not anything else goes wrong later — one scan, one chance.
function M.pair(token, device_name, now)
	ensure_loaded()
	now = now or os.time()
	prune_pending(now)

	if type(token) ~= "string" or not data.pending[token] then
		return nil, "invalid or expired pairing token"
	end
	data.pending[token] = nil

	local bearer = random_hex(24)
	local device = {
		id = random_hex(8),
		name = tostring(device_name or "device"):sub(1, 64),
		token_sha256 = vim.fn.sha256(bearer),
		paired_at = now,
		last_seen = now,
	}
	table.insert(data.devices, device)
	if not save() then
		return nil, "could not persist the device list"
	end
	-- The bearer token exists in plaintext exactly once: in this response.
	return { device_id = device.id, device_token = bearer, name = device.name }
end

-- Authorization header -> device, or nil. Constant shape either way; the
-- comparison is on hashes so the stored file never holds the credential.
function M.authorize(authorization_header)
	ensure_loaded()
	if type(authorization_header) ~= "string" then
		return nil
	end
	local bearer = authorization_header:match("^[Bb]earer%s+(%S+)$")
	if not bearer then
		return nil
	end
	local hashed = vim.fn.sha256(bearer)
	for _, device in ipairs(data.devices) do
		if device.token_sha256 == hashed then
			device.last_seen = os.time()
			return device
		end
	end
	return nil
end

function M.devices()
	return ensure_loaded().devices
end

-- "Is there an app synced?" — pairing is the opt-in signal the auto server
-- start keys off: nobody pairs a device without wanting it to sync.
function M.has_paired_devices()
	return #ensure_loaded().devices > 0
end

function M.revoke(device_id)
	ensure_loaded()
	for i, device in ipairs(data.devices) do
		if device.id == device_id then
			table.remove(data.devices, i)
			save()
			return true
		end
	end
	return false
end

-- Spec hook: point the store somewhere disposable and start fresh.
function M.reset_for_tests()
	data = nil
end

return M
