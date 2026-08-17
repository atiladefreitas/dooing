-- The three-way todo merge. Pure: no clock, no filesystem, no vim state —
-- everything it knows arrives as arguments, so the same inputs give the same
-- answer here and in dooing-app/src/lib/sync/merge.ts, and the shared fixture
-- corpus (spec/fixtures/merge) holds both implementations to it.
--
-- The design (masterplan Part 2, docs/SYNC-PROTOCOL.md):
--   * `base` is the load-bearing structure — the todos as both sides last
--     agreed. "Did this side change?" is answered by comparing against base,
--     NEVER by trusting updated_at; two devices with skewed clocks must not
--     corrupt data. updated_at only breaks genuine conflicts.
--   * The merge is per FIELD GROUP, not per record: ticking a todo done on
--     the phone while giving it a due date in Neovim is complementary, and
--     whole-record last-write-wins would throw one of them away for nothing.
--   * Delete-vs-edit resurrects: a deletion is cheap to repeat, a lost edit
--     is not recoverable.
--   * Losing values are returned in `conflicts` so the caller can trail
--     them — remote-wins-style destruction is never silent.

local canonical = require("dooing.sync.canonical")

local M = {}

local NIL = vim.NIL

-- The groups. `category` is derived, never merged; `depth` is recomputed
-- from the final tree, so placement compares parent_id alone.
M.GROUPS = {
	{ name = "status", fields = { "done", "in_progress", "completed_at" } },
	{ name = "text", fields = { "text" } },
	{ name = "notes", fields = { "notes" } },
	{ name = "placement", fields = { "parent_id" } },
	{ name = "due", fields = { "due_at" } },
	{ name = "estimate", fields = { "estimated_hours" } },
	{ name = "priorities", fields = { "priorities" } },
}

-- One tag rule for the whole ecosystem: letters, digits, underscore, dash,
-- slash. This is PR #88's charset, applied here to the derivation the PR
-- missed; the app's extractCategory matches it character for character.
function M.derive_category(text)
	if type(text) ~= "string" then
		return ""
	end
	return text:match("#([%w_%-/]+)") or ""
end

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

-- JSON null and absent are the same fact on this wire.
local function val(todo, field)
	local v = todo[field]
	if v == NIL then
		return nil
	end
	return v
end

local function group_value(todo, group)
	local out = {}
	for _, field in ipairs(group.fields) do
		out[field] = todo and val(todo, field) or nil
	end
	return out
end

local function group_changed(todo, base, group)
	if not base then
		return true
	end
	return not canonical.equal(group_value(todo, group), group_value(base, group))
end

local function changed_at(todo)
	return val(todo, "updated_at") or val(todo, "created_at") or 0
end

-- Tie-break rule (normative): newer updated_at wins; on an exact tie the
-- side with the LEXICOGRAPHICALLY SMALLER device id wins. Deterministic on
-- both ends or the two sides disagree forever.
local function newer_side(l, r, local_device, remote_device)
	local lu, ru = changed_at(l), changed_at(r)
	if lu ~= ru then
		return lu > ru and "local" or "remote"
	end
	return tostring(local_device) < tostring(remote_device) and "local" or "remote"
end

-- One side's notes strictly extend the other's (prefix or suffix): both
-- edits survive as the longer text. Appending is what people do to a
-- scratchpad; this is the one conflict we can dissolve instead of judging.
local function notes_superset(a, b)
	if type(a) ~= "string" or type(b) ~= "string" or #a <= #b then
		return false
	end
	return a:sub(1, #b) == b or a:sub(-#b) == b
end

local function any_group_changed(todo, base)
	for _, group in ipairs(M.GROUPS) do
		if group_changed(todo, base, group) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Merging one todo present on both sides
--------------------------------------------------------------------------

local function merge_groups(id, b, l, r, local_device, remote_device, conflicts)
	local result = { id = id }

	for _, group in ipairs(M.GROUPS) do
		local lc = group_changed(l, b, group)
		local rc = group_changed(r, b, group)
		local winner_todo

		if not lc and not rc then
			winner_todo = b
		elseif lc and not rc then
			winner_todo = l
		elseif rc and not lc then
			winner_todo = r
		elseif canonical.equal(group_value(l, group), group_value(r, group)) then
			winner_todo = l
		elseif group.name == "notes" and notes_superset(val(l, "notes") or "", val(r, "notes") or "") then
			winner_todo = l
		elseif group.name == "notes" and notes_superset(val(r, "notes") or "", val(l, "notes") or "") then
			winner_todo = r
		else
			local side = newer_side(l, r, local_device, remote_device)
			winner_todo = side == "local" and l or r
			local loser_todo = side == "local" and r or l
			table.insert(conflicts, {
				id = id,
				kind = "edit-vs-edit",
				group = group.name,
				winner = side,
				loser_value = group_value(loser_todo, group),
			})
		end

		for _, field in ipairs(group.fields) do
			result[field] = winner_todo and val(winner_todo, field) or nil
		end
	end

	-- Record-level fields, outside every group:
	local lc_at, rc_at = val(l, "created_at"), val(r, "created_at")
	if b and val(b, "created_at") then
		result.created_at = val(b, "created_at")
	elseif lc_at and rc_at then
		result.created_at = math.min(lc_at, rc_at)
	else
		result.created_at = lc_at or rc_at
	end

	local lu, ru = val(l, "updated_at") or 0, val(r, "updated_at") or 0
	local u = math.max(lu, ru)
	result.updated_at = u > 0 and u or nil

	result.category = M.derive_category(result.text)
	return result
end

--------------------------------------------------------------------------
-- The tree post-pass: break cycles, recompute depth, order parents first
--------------------------------------------------------------------------

-- A merged parent_id graph can contain a cycle (A under B from one side, B
-- under A from the other). Silently kept it corrupts the list permanently,
-- so: promote the cycle member with the OLDEST change to top level (the
-- less recent reparent loses), report it, repeat until acyclic. Ties break
-- on the lexicographically greater id — any rule works as long as both
-- implementations share it.
local function break_cycles(by_id, conflicts)
	local function find_cycle(start)
		local seen = {}
		local node = start
		while node do
			if seen[node.id] then
				return node -- inside the cycle now
			end
			seen[node.id] = true
			node = node.parent_id and node.parent_id ~= NIL and by_id[node.parent_id] or nil
		end
		return nil
	end

	for _, start in pairs(by_id) do
		local hit = find_cycle(start)
		while hit do
			-- Collect the members of this cycle.
			local members = {}
			local node = hit
			repeat
				table.insert(members, node)
				node = by_id[node.parent_id]
			until node == nil or node.id == hit.id

			local victim = members[1]
			for _, member in ipairs(members) do
				local ma, va = changed_at(member), changed_at(victim)
				if ma < va or (ma == va and member.id > victim.id) then
					victim = member
				end
			end
			table.insert(conflicts, {
				id = victim.id,
				kind = "cycle",
				group = "placement",
				winner = nil,
				loser_value = { parent_id = victim.parent_id },
			})
			victim.parent_id = nil
			hit = find_cycle(start)
		end
	end
end

-- Depth is derived state: distance from the effective root. An orphan
-- (parent_id points at a todo that no longer exists) renders as a root, so
-- its depth is 0 — same rule as the app's rowsForDisplay.
local function recompute_depth(ordered, by_id)
	local depth_of = {}
	local function depth(todo, guard)
		if depth_of[todo.id] then
			return depth_of[todo.id]
		end
		guard = guard or {}
		if guard[todo.id] then
			return 0 -- unreachable once cycles are broken; belt and braces
		end
		guard[todo.id] = true
		local parent = todo.parent_id and todo.parent_id ~= NIL and by_id[todo.parent_id] or nil
		local d = parent and (depth(parent, guard) + 1) or 0
		depth_of[todo.id] = d
		return d
	end
	for _, todo in ipairs(ordered) do
		todo.depth = depth(todo)
	end
end

-- Deterministic output order: the incoming sequence (local order, then
-- remote-only ids in remote order), rearranged so every parent precedes its
-- children. Array position is otherwise meaningless — both UIs re-derive
-- display order — but nested insertion in dooing assumes parents first.
local function order_parents_first(sequence, by_id)
	local ordered, placed = {}, {}
	local function place(todo, guard)
		if placed[todo.id] then
			return
		end
		guard = guard or {}
		if guard[todo.id] then
			return
		end
		guard[todo.id] = true
		local parent = todo.parent_id and todo.parent_id ~= NIL and by_id[todo.parent_id] or nil
		if parent then
			place(parent, guard)
		end
		if not placed[todo.id] then
			placed[todo.id] = true
			table.insert(ordered, todo)
		end
	end
	for _, id in ipairs(sequence) do
		place(by_id[id])
	end
	return ordered
end

--------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------

--- Three-way merge of two full states against their last agreement.
---
--- input = {
---   base              = { [id] = todo },  -- last agreed state (may be {})
---   local_todos       = { todo, ... },
---   remote_todos      = { todo, ... },
---   local_tombstones  = { { id=..., deleted_at=... }, ... },
---   remote_tombstones = { ... },
---   local_device      = "...",  -- tie-break identities; must differ
---   remote_device     = "...",
--- }
---
--- returns {
---   todos      = ordered list, parents before children, depth recomputed,
---   tombstones = deletions the caller must remember/propagate,
---   base       = { [id] = todo } — the new agreement (share of `todos`),
---   conflicts  = { { id, kind, group?, winner?, loser_value? }, ... },
--- }
function M.merge(input)
	local base = input.base or {}
	local local_device = input.local_device or "local"
	local remote_device = input.remote_device or "remote"

	local locals_by_id, local_order = {}, {}
	for _, todo in ipairs(input.local_todos or {}) do
		locals_by_id[todo.id] = todo
		table.insert(local_order, todo.id)
	end
	local remotes_by_id, remote_order = {}, {}
	for _, todo in ipairs(input.remote_todos or {}) do
		remotes_by_id[todo.id] = todo
		table.insert(remote_order, todo.id)
	end
	local tomb_by_id = {}
	for _, t in ipairs(input.local_tombstones or {}) do
		tomb_by_id[t.id] = t
	end
	for _, t in ipairs(input.remote_tombstones or {}) do
		tomb_by_id[t.id] = tomb_by_id[t.id] or t
	end

	-- Every id, in deterministic sequence: local order, then remote-only.
	local sequence, seen = {}, {}
	for _, id in ipairs(local_order) do
		table.insert(sequence, id)
		seen[id] = true
	end
	for _, id in ipairs(remote_order) do
		if not seen[id] then
			table.insert(sequence, id)
			seen[id] = true
		end
	end
	for id in pairs(base) do
		if not seen[id] then
			table.insert(sequence, id) -- deleted on both sides, or on one
			seen[id] = true
		end
	end
	for id in pairs(tomb_by_id) do
		if not seen[id] then
			table.insert(sequence, id)
		end
	end

	local conflicts = {}
	local by_id = {}
	local out_sequence = {}
	local tombstones = {}

	for _, id in ipairs(sequence) do
		local b, l, r = base[id], locals_by_id[id], remotes_by_id[id]

		if l and r then
			by_id[id] = merge_groups(id, b, l, r, local_device, remote_device, conflicts)
			table.insert(out_sequence, id)
		elseif l and not r then
			if b then
				if any_group_changed(l, b) then
					-- Deleted remotely, edited here: the edit wins, loudly.
					by_id[id] = vim.deepcopy(l)
					table.insert(out_sequence, id)
					table.insert(conflicts, { id = id, kind = "delete-vs-edit", winner = "local" })
				else
					local t = tomb_by_id[id]
					table.insert(tombstones, { id = id, deleted_at = t and t.deleted_at or nil })
				end
			else
				-- Created locally since the last agreement (a stray tombstone
				-- with no base refers to a copy that never synced — ignore it).
				by_id[id] = vim.deepcopy(l)
				table.insert(out_sequence, id)
			end
		elseif r and not l then
			if b then
				if any_group_changed(r, b) then
					by_id[id] = vim.deepcopy(r)
					table.insert(out_sequence, id)
					table.insert(conflicts, { id = id, kind = "delete-vs-edit", winner = "remote" })
				else
					local t = tomb_by_id[id]
					table.insert(tombstones, { id = id, deleted_at = t and t.deleted_at or nil })
				end
			else
				by_id[id] = vim.deepcopy(r)
				table.insert(out_sequence, id)
			end
		else
			-- Gone from both sides: agreement. The tombstone has done its job.
		end
	end

	break_cycles(by_id, conflicts)

	local ordered = order_parents_first(out_sequence, by_id)
	recompute_depth(ordered, by_id)

	local new_base = {}
	for _, todo in ipairs(ordered) do
		new_base[todo.id] = todo
	end

	return { todos = ordered, tombstones = tombstones, base = new_base, conflicts = conflicts }
end

return M
