local store = require("dooing.sync.store")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local function fresh()
	store.reset_for_tests()
	store._path_override = dir .. "/sync_" .. math.random(1e9) .. ".json"
end

describe("sync store", function()
	it("keeps a base per device", function()
		fresh()
		store.commit_exchange("phone-a", { x = { id = "x", text = "a" } }, {}, 1000)
		store.commit_exchange("phone-b", { y = { id = "y", text = "b" } }, {}, 1000)
		truthy(store.device("phone-a").base.x)
		eq(store.device("phone-a").base.y, nil)
		truthy(store.device("phone-b").base.y)
	end)

	it("advances the revision on every exchange", function()
		fresh()
		eq(store.commit_exchange("phone", {}, {}, 1000), 1)
		eq(store.commit_exchange("phone", {}, {}, 1001), 2)
	end)

	it("persists across a reload", function()
		fresh()
		store.commit_exchange("phone", { x = { id = "x" } }, { { id = "gone", deleted_at = 5 } }, 1000)
		local path = store._path_override
		store.reset_for_tests()
		store._path_override = path
		eq(store.device("phone").revision, 1)
		truthy(store.device("phone").base.x)
		eq(store.device("phone").tombstones[1].id, "gone")
	end)

	it("trails conflicts, trims to the limit, acknowledges on read", function()
		fresh()
		local many = {}
		for i = 1, 60 do
			table.insert(many, { id = "t" .. i, kind = "edit-vs-edit", group = "text", winner = "local" })
		end
		store.record_conflicts("phone", many, 1000)
		eq(#store.conflicts(), 50, "trimmed to trail_limit")
		eq(store.unacknowledged_count(), 50)
		truthy(store.acknowledge_conflicts())
		eq(store.unacknowledged_count(), 0)
	end)

	it("prunes state for unpaired devices", function()
		fresh()
		store.commit_exchange("kept", {}, {}, 1000)
		store.commit_exchange("gone", {}, {}, 1000)
		truthy(store.prune_devices({ kept = true }))
		eq(store.device("gone").revision, 0, "recreated empty, not remembered")
	end)

	it("writes 0600", function()
		fresh()
		store.commit_exchange("phone", {}, {}, 1000)
		local stat = vim.uv.fs_stat(store._path_override)
		eq(bit.band(stat.mode, tonumber("777", 8)), tonumber("600", 8))
	end)
end)
