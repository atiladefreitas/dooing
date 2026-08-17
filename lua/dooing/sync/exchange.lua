-- One full sync exchange with a paired device: merge the device's state with
-- ours against the base we last agreed on, persist the outcome everywhere it
-- needs to live, and hand back the merged state.
--
-- Protocol shape (docs/SYNC-PROTOCOL.md):
--   request  { revision, todos = [...], tombstones = [{id, deleted_at}] }
--   response { revision, todos, tombstones, conflicts }
--
-- The device applies the response wholesale (reconciling mid-flight edits on
-- its side with its own copy of the merge engine). After a successful
-- exchange both sides hold the same list, and the server's per-device base
-- records the new agreement.

local config = require("dooing.config")
local merge = require("dooing.sync.merge")
local state = require("dooing.state")
local store = require("dooing.sync.store")

local M = {}

-- The server's identity in the updated_at tie-break. Device ids are hex, so
-- "server" (s > f) sorts after every device id — meaning: on an exact
-- timestamp tie, the device wins. Documented in SYNC-PROTOCOL.md.
local SERVER_DEVICE = "server"

-- The exchange always works on the GLOBAL list. If a project list happens to
-- be loaded in this session, state.replace_global_todos writes the global
-- file without touching the live project state.
local function server_todos()
	local global_path = config.options.save_path
	if state.current_save_path == nil or state.current_save_path == global_path then
		return state.todos
	end
	local file = io.open(global_path, "r")
	if not file then
		return {}
	end
	local content = file:read("*all")
	file:close()
	if not content or content == "" then
		return {}
	end
	local ok, decoded = pcall(vim.json.decode, content)
	return (ok and type(decoded) == "table") and decoded or {}
end

-- The merge trails only the losing GROUP value; the report wants the whole
-- losing todo so :DooingSyncRestore can bring it back. Attach it here, where
-- both sides' full lists are still at hand.
local function enrich_conflicts(conflicts, server_by_id, device_by_id)
	for _, conflict in ipairs(conflicts) do
		local loser
		if conflict.winner == "local" then
			loser = device_by_id[conflict.id]
		elseif conflict.winner == "remote" then
			loser = server_by_id[conflict.id]
		end
		if loser then
			conflict.loser_todo = vim.deepcopy(loser)
		end
	end
	return conflicts
end

--- Run one exchange. `device` is the authorized device (from sync/devices),
--- `payload` the decoded request body. Returns (response) or (nil, status,
--- message) for protocol errors.
function M.todos_exchange(device, payload)
	if type(payload) ~= "table" or type(payload.todos) ~= "table" then
		return nil, 400, "expected a JSON body with a todos array"
	end

	local before = server_todos()
	local device_state = store.device(device.id)

	local result = merge.merge({
		base = device_state.base or {},
		local_todos = before,
		remote_todos = payload.todos,
		local_tombstones = {},
		remote_tombstones = payload.tombstones or {},
		local_device = SERVER_DEVICE,
		remote_device = device.id,
	})

	local server_by_id, device_by_id = {}, {}
	for _, todo in ipairs(before) do
		server_by_id[todo.id] = todo
	end
	for _, todo in ipairs(payload.todos) do
		device_by_id[todo.id] = todo
	end
	enrich_conflicts(result.conflicts, server_by_id, device_by_id)

	local live = state.replace_global_todos(result.todos)
	local revision = store.commit_exchange(device.id, result.base, result.tombstones)
	store.record_conflicts(device.id, result.conflicts)

	-- What actually changed on our side, for the notification.
	local changed = 0
	local after_ids = {}
	for _, todo in ipairs(result.todos) do
		after_ids[todo.id] = true
		local prior = server_by_id[todo.id]
		if not prior or (prior.updated_at or 0) ~= (todo.updated_at or 0) then
			changed = changed + 1
		end
	end
	for _, todo in ipairs(before) do
		if not after_ids[todo.id] then
			changed = changed + 1
		end
	end

	if #result.conflicts > 0 then
		vim.notify(
			("Dooing sync (%s): %d conflict%s resolved - run :DooingSyncReport"):format(
				device.name or device.id,
				#result.conflicts,
				#result.conflicts == 1 and "" or "s"
			),
			vim.log.levels.WARN
		)
	elseif changed > 0 then
		vim.notify(
			("Dooing sync (%s): %d change%s"):format(device.name or device.id, changed, changed == 1 and "" or "s"),
			vim.log.levels.INFO
		)
	end

	if live and changed > 0 then
		pcall(function()
			local ui = require("dooing.ui")
			if ui.is_window_open() then
				ui.render_todos()
			end
		end)
	end

	return {
		revision = revision,
		todos = result.todos,
		tombstones = result.tombstones,
		conflicts = result.conflicts,
	}
end

--------------------------------------------------------------------------
-- Status, report, restore — the user-facing side of the trail
--------------------------------------------------------------------------

local function open_scratch(title, lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

	local width = math.min(90, math.floor(vim.o.columns * 0.8))
	local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = config.options.window.border,
		title = " " .. title .. " ",
	})
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })
end

function M.status()
	local devices = require("dooing.sync.devices")
	local server = require("dooing.server")
	local lines = { "# Dooing sync status", "" }

	table.insert(lines, "- server: " .. (server.is_running() and "running" or "stopped"))
	local paired = devices.devices()
	if #paired == 0 then
		table.insert(lines, "- no paired devices (open the share page and scan the QR)")
	end
	for i, device in ipairs(paired) do
		local info = store.device(device.id)
		table.insert(
			lines,
			("- %d. %s (id %s): revision %d, last sync %s"):format(
				i,
				device.name,
				device.id,
				info.revision or 0,
				info.last_sync and os.date("%Y-%m-%d %H:%M", info.last_sync) or "never"
			)
		)
	end
	if #paired > 0 then
		table.insert(lines, "")
		table.insert(lines, "Unpair one with `:DooingSyncRevoke <number|id|name>`.")
	end
	local unseen = store.unacknowledged_count()
	if unseen > 0 then
		table.insert(lines, "")
		table.insert(lines, ("%d unread conflict%s - :DooingSyncReport"):format(unseen, unseen == 1 and "" or "s"))
	end
	open_scratch("Dooing sync", lines)
end

local function describe_value(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	for key, v in pairs(value) do
		table.insert(parts, key .. "=" .. vim.inspect(v))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

function M.report()
	local conflicts = store.conflicts()
	local lines = { "# Sync conflicts", "" }
	if #conflicts == 0 then
		table.insert(lines, "None. Every exchange so far merged cleanly.")
	else
		table.insert(lines, "The losing side of each conflict is kept here.")
		table.insert(lines, "Restore one as a new todo with `:DooingSyncRestore <n>`.")
		table.insert(lines, "")
	end
	for i, conflict in ipairs(conflicts) do
		local title = conflict.loser_todo and conflict.loser_todo.text or conflict.id or "?"
		table.insert(lines, ("## %d. %s"):format(i, title))
		table.insert(lines, "- when: " .. os.date("%Y-%m-%d %H:%M", conflict.at or 0))
		table.insert(lines, ("- what: %s (%s), the %s side won"):format(
			conflict.kind or "?",
			conflict.group or "whole todo",
			conflict.winner or "?"
		))
		if conflict.loser_value ~= nil then
			table.insert(lines, "- losing value: " .. describe_value(conflict.loser_value))
		end
		table.insert(lines, "")
	end
	open_scratch("Sync conflicts", lines)

	-- Reading the report IS the acknowledgement (bloocky's rule): markers
	-- for these conflicts stop showing once you have actually seen them.
	store.acknowledge_conflicts()
end

-- Resolve a user-supplied handle — a list number (as shown by
-- :DooingSyncStatus), a device id, or a name — to exactly one device.
-- Names can collide (pair the same phone twice and you have two "Redmi"s),
-- so an ambiguous name is refused rather than guessed at.
local function resolve_device(arg)
	local devices = require("dooing.sync.devices")
	local paired = devices.devices()
	if #paired == 0 then
		return nil, "no devices are paired"
	end

	local index = tonumber(arg)
	if index then
		if paired[index] then
			return paired[index]
		end
		return nil, ("no device number %d (see :DooingSyncStatus)"):format(index)
	end

	local by_name = {}
	for _, device in ipairs(paired) do
		if device.id == arg then
			return device
		end
		if device.name == arg then
			table.insert(by_name, device)
		end
	end
	if #by_name == 1 then
		return by_name[1]
	end
	if #by_name > 1 then
		return nil, ("%d devices are called %q - use the number or id from :DooingSyncStatus"):format(#by_name, arg)
	end
	return nil, ("no paired device matches %q (see :DooingSyncStatus)"):format(tostring(arg))
end

-- Unpair a device: its token stops working immediately, and its sync state
-- (base, revision) goes too, so re-pairing later starts from a clean
-- first exchange instead of a stale agreement.
function M.revoke(arg)
	if not arg or arg == "" then
		M.status()
		return false, "no device given"
	end
	local device, err = resolve_device(vim.trim(arg))
	if not device then
		vim.notify("Dooing: " .. err, vim.log.levels.ERROR)
		return false, err
	end
	require("dooing.sync.devices").revoke(device.id)
	store.reset(device.id)
	vim.notify(("Dooing: unpaired %s (id %s)"):format(device.name, device.id), vim.log.levels.INFO)
	return true
end

-- Completion for :DooingSyncRevoke — numbers and ids (names may collide).
function M.revoke_candidates()
	local out = {}
	for i, device in ipairs(require("dooing.sync.devices").devices()) do
		table.insert(out, tostring(i))
		table.insert(out, device.id)
	end
	return out
end

-- Bring a losing version back as a NEW todo, leaving the winner alone —
-- what makes conflict resolution recoverable rather than destructive.
function M.restore(index)
	local conflicts = store.conflicts()
	local conflict = conflicts[tonumber(index) or 0]
	if not conflict then
		vim.notify("Dooing: no conflict at " .. tostring(index), vim.log.levels.ERROR)
		return
	end
	local text
	if conflict.loser_todo and conflict.loser_todo.text then
		text = conflict.loser_todo.text
	elseif type(conflict.loser_value) == "table" and conflict.loser_value.text then
		text = conflict.loser_value.text
	elseif type(conflict.loser_value) == "table" and conflict.loser_value.notes then
		text = "restored notes: " .. conflict.loser_value.notes
	else
		vim.notify("Dooing: that conflict has nothing restorable", vim.log.levels.WARN)
		return
	end
	state.add_todo(text .. " (restored)")
	vim.notify(("Dooing: restored %q as a new todo"):format(text), vim.log.levels.INFO)
	pcall(function()
		local ui = require("dooing.ui")
		if ui.is_window_open() then
			ui.render_todos()
		end
	end)
end

return M
