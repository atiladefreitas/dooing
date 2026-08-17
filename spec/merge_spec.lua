-- Invariants the fixture corpus cannot express: output ordering, the new
-- base mirroring the output, symmetry, and the loser trail carrying values.

local canonical = require("dooing.sync.canonical")
local merge = require("dooing.sync.merge")

local function todo(id, fields)
	return vim.tbl_extend("force", { id = id, text = "t", category = "", created_at = 1, updated_at = 1 }, fields or {})
end

describe("merge invariants", function()
	it("orders parents before children in the output", function()
		-- Local order deliberately child-first.
		local result = merge.merge({
			base = {},
			local_todos = { todo("c", { parent_id = "p", updated_at = 5 }), todo("p") },
			remote_todos = {},
		})
		eq(#result.todos, 2)
		eq(result.todos[1].id, "p")
		eq(result.todos[2].id, "c")
		eq(result.todos[2].depth, 1)
	end)

	it("returns a base that mirrors the merged todos exactly", function()
		local result = merge.merge({
			base = {},
			local_todos = { todo("a") },
			remote_todos = { todo("b") },
		})
		eq(canonical.encode(result.base.a), canonical.encode(result.todos[1].id == "a" and result.todos[1] or result.todos[2]))
		local count = 0
		for _ in pairs(result.base) do
			count = count + 1
		end
		eq(count, #result.todos)
	end)

	it("is symmetric: swapping sides swaps winners, never outcomes", function()
		local base = { a1 = todo("a1", { text = "x", updated_at = 100 }) }
		local l = { todo("a1", { text = "left", updated_at = 300 }) }
		local r = { todo("a1", { text = "right", updated_at = 200 }) }

		local one = merge.merge({ base = base, local_todos = l, remote_todos = r, local_device = "s", remote_device = "p" })
		local two = merge.merge({ base = base, local_todos = r, remote_todos = l, local_device = "p", remote_device = "s" })

		eq(canonical.encode(one.todos), canonical.encode(two.todos), "same merged state from either seat")
		eq(one.conflicts[1].winner, "local")
		eq(two.conflicts[1].winner, "remote")
	end)

	it("carries the losing value in the conflict, for the trail", function()
		local base = { a1 = todo("a1", { notes = "a", updated_at = 100 }) }
		local result = merge.merge({
			base = base,
			local_todos = { todo("a1", { notes = "mine", updated_at = 300 }) },
			remote_todos = { todo("a1", { notes = "theirs", updated_at = 200 }) },
		})
		eq(result.conflicts[1].loser_value.notes, "theirs")
	end)

	it("ignores a stray tombstone with no base and no surviving copy elsewhere", function()
		local result = merge.merge({
			base = {},
			local_todos = { todo("a1") },
			remote_todos = {},
			remote_tombstones = { { id = "a1", deleted_at = 999 } },
		})
		eq(#result.todos, 1, "the existing copy survives a tombstone that never shared a base with it")
		eq(#result.tombstones, 0)
	end)

	it("breaks a self-parent", function()
		local result = merge.merge({
			base = {},
			local_todos = { todo("a1", { parent_id = "a1" }) },
			remote_todos = {},
		})
		eq(result.todos[1].parent_id, nil)
		eq(result.todos[1].depth, 0)
		eq(result.conflicts[1].kind, "cycle")
	end)

	it("derives category with the shared charset", function()
		eq(merge.derive_category("fix #labels-web now"), "labels-web")
		eq(merge.derive_category("under_score #a_b"), "a_b")
		eq(merge.derive_category("path #area/ui"), "area/ui")
		eq(merge.derive_category("no tag"), "")
		eq(merge.derive_category(nil), "")
	end)
end)
