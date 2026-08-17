-- Canonical serialization: one stable string per value, so "did this field
-- group change?" is a string comparison and never a walk that two
-- implementations might do differently.
--
-- This module is PARITY-CRITICAL: dooing-app/src/lib/sync/canonical.ts must
-- produce byte-identical output for the same value, and the shared fixture
-- corpus (spec/fixtures/merge) holds both to it. Change the rules here and
-- there together, never in one place.
--
-- Rules:
--   * object keys sorted; keys whose value is null/absent are DROPPED —
--     Lua's encoder omits nil and the wire contract says absent, not null,
--     so null and absent must compare equal.
--   * integers print without a decimal point; other numbers via %.14g
--     (matches JS String() for the short decimals real data contains —
--     do not put pathological floats like 1/3 in fixtures).
--   * strings escaped exactly as JSON.stringify does: `"` `\` and control
--     characters, nothing else.

local M = {}

local NIL = vim.NIL

local ESCAPES = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function encode_string(s)
	return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
		return ESCAPES[c] or ("\\u%04x"):format(c:byte())
	end) .. '"'
end

local function encode_number(n)
	if n % 1 == 0 and n == n and n ~= math.huge and n ~= -math.huge then
		return ("%d"):format(n)
	end
	return ("%.14g"):format(n)
end

local function is_array(t)
	if vim.islist then
		return vim.islist(t)
	end
	return vim.tbl_islist(t)
end

local function encode(value)
	if value == nil or value == NIL then
		return "null"
	end
	local kind = type(value)
	if kind == "boolean" then
		return value and "true" or "false"
	end
	if kind == "number" then
		return encode_number(value)
	end
	if kind == "string" then
		return encode_string(value)
	end
	if kind == "table" then
		-- An empty table decoded from JSON `{}` carries vim.empty_dict()'s
		-- metatable; a plain empty table reads as an empty array.
		if next(value) == nil then
			if getmetatable(value) == getmetatable(vim.empty_dict()) then
				return "{}"
			end
			return "[]"
		end
		if is_array(value) then
			local parts = {}
			for _, item in ipairs(value) do
				table.insert(parts, encode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key, item in pairs(value) do
			if item ~= nil and item ~= NIL then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local parts = {}
		for _, key in ipairs(keys) do
			table.insert(parts, encode_string(tostring(key)) .. ":" .. encode(value[key]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("cannot canonicalize a " .. kind)
end

M.encode = encode

function M.equal(a, b)
	return encode(a) == encode(b)
end

return M
