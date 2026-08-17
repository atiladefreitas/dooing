-- The shared merge corpus. dooing-app runs the SAME cases (vendored copy of
-- spec/fixtures/merge/cases.json) — a case only one implementation passes is
-- a bug in the other one.

local canonical = require("dooing.sync.canonical")
local merge = require("dooing.sync.merge")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local file = io.open(root .. "/spec/fixtures/merge/cases.json", "r")
local cases = vim.json.decode(file:read("*a"))
file:close()

local function by_id(a, b)
	return a.id < b.id
end

local function normalize_conflicts(list)
	local out = {}
	for _, c in ipairs(list or {}) do
		table.insert(out, { id = c.id, kind = c.kind, group = c.group, winner = c.winner })
	end
	table.sort(out, function(a, b)
		if a.id ~= b.id then
			return a.id < b.id
		end
		return (a.group or "") .. a.kind < (b.group or "") .. b.kind
	end)
	return out
end

local function sorted(list)
	local copy = vim.deepcopy(list or {})
	table.sort(copy, by_id)
	return copy
end

describe("merge fixtures", function()
	for _, case in ipairs(cases) do
		it(case.name, function()
			local input = case.input
			local side_l, side_r = input["local"], input.remote
			local result = merge.merge({
				base = input.base,
				local_todos = side_l.todos,
				remote_todos = side_r.todos,
				local_tombstones = side_l.tombstones,
				remote_tombstones = side_r.tombstones,
				local_device = side_l.device,
				remote_device = side_r.device,
			})

			eq(canonical.encode(sorted(result.todos)), canonical.encode(sorted(case.expected.todos)), "todos")
			eq(
				canonical.encode(sorted(result.tombstones)),
				canonical.encode(sorted(case.expected.tombstones)),
				"tombstones"
			)
			eq(
				canonical.encode(normalize_conflicts(result.conflicts)),
				canonical.encode(normalize_conflicts(case.expected.conflicts)),
				"conflicts"
			)
		end)
	end
end)
