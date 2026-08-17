-- Minimal test runner. Run it with `scripts/test.sh`, or directly:
--
--     nvim -l spec/run.lua
--
-- Neovim is the interpreter, so specs get the real API — vim.json, vim.uv,
-- vim.fn.sha256 — with no shims and nothing to install. Busted would need a
-- fake `vim` global, and a fake is exactly the wrong thing to test against
-- when the whole point is how this code behaves inside Neovim.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local failures, passed = {}, 0
local scope = nil

function describe(name, fn)
	local outer = scope
	scope = outer and (outer .. " " .. name) or name
	fn()
	scope = outer
end

function it(name, fn)
	local label = (scope and scope .. " › " or "") .. name
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		table.insert(failures, { label = label, err = err })
	end
end

-- Assertions. They throw, `it` catches — the message is what you read when
-- something breaks, so it carries both values.
local function fail(msg)
	error(msg, 3)
end

function eq(actual, expected, msg)
	if not vim.deep_equal(actual, expected) then
		fail(
			("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual))
		)
	end
end

function neq(actual, expected, msg)
	if vim.deep_equal(actual, expected) then
		fail(("%sexpected something other than %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected)))
	end
end

function truthy(value, msg)
	if not value then
		fail(("%sexpected a truthy value, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(value)))
	end
end

function falsy(value, msg)
	if value then
		fail(("%sexpected a falsy value, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(value)))
	end
end

local files = vim.fn.glob(root .. "/spec/*_spec.lua", false, true)
table.sort(files)
for _, file in ipairs(files) do
	local ok, err = pcall(dofile, file)
	if not ok then
		table.insert(failures, { label = vim.fn.fnamemodify(file, ":t") .. " (failed to load)", err = err })
	end
end

for _, failure in ipairs(failures) do
	io.write("FAIL  ", failure.label, "\n      ", tostring(failure.err), "\n")
end
io.write(("\n%d passed, %d failed\n"):format(passed, #failures))
os.exit(#failures == 0 and 0 or 1)
