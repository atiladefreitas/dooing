-- The sync sidecar: what the merge needs remembered between exchanges, kept
-- out of the todos file (dooing_todos.json is a contract other tools read;
-- bases and conflict trails are nobody else's business — the same reasoning
-- as bloocky's bloocky_sync.json).
--
-- The base is PER DEVICE: it is the state this server and that device last
-- agreed on, so two phones each have their own. Bases hold full todo values,
-- not hashes — a three-way merge needs to know *which field group* changed,
-- and only values can answer that.

local M = {}

local VERSION = 1

local data = nil

local function empty()
	return {
		version = VERSION,
		-- device id -> { revision = n, base = { [todo id] = todo },
		--                tombstones = { { id, deleted_at }, ... },
		--                last_sync = unix seconds }
		devices = {},
		-- The losing versions, so a lost edit is restorable. Same shape of
		-- promise as bloocky's trail: never destroy silently.
		conflicts = {},
	}
end

function M.path()
	if M._path_override then
		return M._path_override
	end
	local config = require("dooing.config")
	local save_path = config.options.save_path or (vim.fn.stdpath("data") .. "/dooing_todos.json")
	return vim.fn.fnamemodify(save_path, ":h") .. "/dooing_sync.json"
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
	if not ok or type(decoded) ~= "table" then
		vim.notify("Dooing: could not parse " .. M.path() .. ", starting sync state fresh", vim.log.levels.WARN)
		return data
	end
	for _, key in ipairs({ "devices", "conflicts" }) do
		if type(decoded[key]) == "table" then
			data[key] = decoded[key]
		end
	end
	return data
end

local function ensure_loaded()
	if not data then
		M.load()
	end
	return data
end

-- Temp file + rename, 0600: atomic within a filesystem, so a crash mid-write
-- leaves the previous state rather than a truncated file that reads as
-- "never synced" — and the bases mirror someone's whole todo list.
function M.save()
	ensure_loaded()
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
-- Per-device sync state
--------------------------------------------------------------------------

function M.device(device_id)
	ensure_loaded()
	data.devices[device_id] = data.devices[device_id]
		or { revision = 0, base = vim.empty_dict(), tombstones = {} }
	return data.devices[device_id]
end

-- Record the outcome of a successful exchange: the merged state becomes the
-- new agreement and the revision moves forward.
--
-- Deep-copied on the way in: the merge returns a base that SHARES tables
-- with the todos the caller is about to install as live state. Stored by
-- reference, the next edit would mutate the "agreement" too — and a base
-- that silently tracks one side can never detect that side's changes.
function M.commit_exchange(device_id, base, tombstones, now)
	local device = M.device(device_id)
	device.revision = (device.revision or 0) + 1
	device.base = base and vim.deepcopy(base) or vim.empty_dict()
	device.tombstones = tombstones and vim.deepcopy(tombstones) or {}
	device.last_sync = now or os.time()
	M.save()
	return device.revision
end

--------------------------------------------------------------------------
-- The conflict trail
--------------------------------------------------------------------------

function M.record_conflicts(device_id, conflicts, now)
	if not conflicts or #conflicts == 0 then
		return
	end
	ensure_loaded()
	now = now or os.time()
	for _, conflict in ipairs(conflicts) do
		table.insert(data.conflicts, {
			at = now,
			device = device_id,
			id = conflict.id,
			kind = conflict.kind,
			group = conflict.group,
			winner = conflict.winner,
			loser_value = conflict.loser_value,
			-- The whole losing todo when the caller could supply it — what
			-- makes :DooingSyncRestore able to bring the loser back.
			loser_todo = conflict.loser_todo,
		})
	end
	local config = require("dooing.config")
	local sync = config.options.sync or {}
	local limit = (sync.conflict or {}).trail_limit or 50
	while #data.conflicts > limit do
		table.remove(data.conflicts, 1)
	end
	M.save()
end

function M.conflicts()
	return ensure_loaded().conflicts
end

function M.unacknowledged_count()
	ensure_loaded()
	local count = 0
	for _, entry in ipairs(data.conflicts) do
		if not entry.acknowledged then
			count = count + 1
		end
	end
	return count
end

-- Reading the report is the acknowledgement — a marker that never clears is
-- one people stop seeing.
function M.acknowledge_conflicts()
	ensure_loaded()
	local changed = false
	for _, entry in ipairs(data.conflicts) do
		if not entry.acknowledged then
			entry.acknowledged = true
			changed = true
		end
	end
	if changed then
		M.save()
	end
	return changed
end

--------------------------------------------------------------------------
-- Hygiene
--------------------------------------------------------------------------

-- Bases for unpaired devices would sit in the file forever otherwise.
function M.prune_devices(valid_ids)
	ensure_loaded()
	local changed = false
	for device_id in pairs(data.devices) do
		if not valid_ids[device_id] then
			data.devices[device_id] = nil
			changed = true
		end
	end
	if changed then
		M.save()
	end
	return changed
end

function M.reset(device_id)
	ensure_loaded()
	if device_id then
		data.devices[device_id] = nil
	else
		data = empty()
	end
	M.save()
end

-- Spec hook.
function M.reset_for_tests()
	data = nil
end

return M
