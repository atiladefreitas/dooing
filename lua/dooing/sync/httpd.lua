-- HTTP request framing and the guards every route sits behind.
--
-- Pure functions, no sockets: server.lua feeds chunks in and writes the
-- returned strings out, so everything here runs under the spec suite. The old
-- server treated one read_start chunk as one complete request, which happens
-- to work for a small GET and cannot work for a POST body — this replaces
-- that, it does not extend it.

local M = {}

-- Caps. Generous for the payloads involved (a big todo list is tens of KB)
-- and small enough that a hostile peer cannot balloon memory.
M.MAX_HEADER_BYTES = 8 * 1024
M.MAX_BODY_BYTES = 1024 * 1024

--------------------------------------------------------------------------
-- Request parsing
--------------------------------------------------------------------------

-- One parser per connection. Feed it chunks as they arrive:
--
--   parser:feed(chunk) -> request | nil, err
--
-- nil-and-no-error means "incomplete, keep reading". An err is fatal for the
-- connection: respond 4xx and close. A returned request has `method`, `path`
-- (query stripped, kept in `query`), lower-cased `headers`, and `body`.
function M.new_parser()
	return setmetatable({ buffer = "", head = nil }, { __index = M })
end

local function parse_head(head)
	local first_line_end = head:find("\r\n", 1, true) or #head + 1
	local request_line = head:sub(1, first_line_end - 1)
	local method, target = request_line:match("^(%u+) (%S+) HTTP/1%.[01]$")
	if not method then
		return nil, "malformed request line"
	end

	local headers = {}
	for line in head:sub(first_line_end + 2):gmatch("([^\r\n]+)") do
		local name, value = line:match("^([^:%s]+):%s*(.-)%s*$")
		if not name then
			return nil, "malformed header"
		end
		headers[name:lower()] = value
	end

	local path, query = target:match("^([^?]*)%??(.*)$")
	return {
		method = method,
		path = path,
		query = query,
		headers = headers,
		body = "",
	}
end

function M:feed(chunk)
	self.buffer = self.buffer .. (chunk or "")

	if not self.head then
		local head_end = self.buffer:find("\r\n\r\n", 1, true)
		if not head_end then
			if #self.buffer > M.MAX_HEADER_BYTES then
				return nil, "headers too large"
			end
			return nil -- incomplete
		end
		local head, err = parse_head(self.buffer:sub(1, head_end - 1))
		if not head then
			return nil, err
		end
		self.head = head
		self.buffer = self.buffer:sub(head_end + 4)
	end

	local length = tonumber(self.head.headers["content-length"] or 0) or 0
	if length < 0 or self.head.headers["transfer-encoding"] then
		return nil, "unsupported framing"
	end
	if length > M.MAX_BODY_BYTES then
		return nil, "body too large"
	end
	if #self.buffer < length then
		return nil -- incomplete
	end

	local request = self.head
	request.body = self.buffer:sub(1, length)
	self.head = nil
	self.buffer = ""
	return request
end

--------------------------------------------------------------------------
-- Guards
--------------------------------------------------------------------------

local function is_ip_literal(name)
	if name == "localhost" then
		return true
	end
	-- IPv4: four dot-separated numbers, each 0-255.
	local a, b, c, d = name:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if a then
		for _, part in ipairs({ a, b, c, d }) do
			if tonumber(part) > 255 then
				return false
			end
		end
		return true
	end
	-- IPv6 literal in brackets (already split from the port by the caller).
	if name:match("^%[[%x:]+%]$") then
		return true
	end
	return false
end

-- The DNS-rebinding defence. A rebinding attack needs a DNS *name* that a
-- hostile server points at this machine; the plugin only ever hands out IP
-- literals, so any Host carrying a name is a browser resolving someone
-- else's domain. Reject it, and reject a port that is not ours.
function M.check_host(host_header, port)
	if type(host_header) ~= "string" or host_header == "" then
		return false
	end
	local name, host_port = host_header:match("^(%[[%x:]+%]):(%d+)$")
	if not name then
		name = host_header:match("^(%[[%x:]+%])$")
	end
	if not name then
		name, host_port = host_header:match("^([^:]+):(%d+)$")
	end
	if not name then
		name = host_header
	end
	if host_port and tonumber(host_port) ~= port then
		return false
	end
	if not host_port and port ~= 80 then
		return false
	end
	return is_ip_literal(name)
end

-- A request carrying Origin comes from a browser page doing a cross-origin
-- fetch. Nothing legitimate does that: the app is not a browser and the QR
-- page only navigates. With no CORS headers a browser could not read the
-- response anyway, but rejecting outright also stops "simple request" writes.
function M.check_origin(origin_header)
	return origin_header == nil
end

--------------------------------------------------------------------------
-- Responses
--------------------------------------------------------------------------

local STATUS_TEXT = {
	[200] = "OK",
	[400] = "Bad Request",
	[401] = "Unauthorized",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[413] = "Payload Too Large",
	[500] = "Internal Server Error",
}

-- No Access-Control-Allow-Origin, deliberately: the wildcard the old server
-- sent is what let any web page on the network read the todo list.
function M.response(status, content_type, body)
	body = body or ""
	return table.concat({
		("HTTP/1.1 %d %s"):format(status, STATUS_TEXT[status] or "Unknown"),
		"Content-Type: " .. (content_type or "text/plain"),
		"Content-Length: " .. #body,
		"Connection: close",
		"",
		body,
	}, "\r\n")
end

function M.json_response(status, value)
	return M.response(status, "application/json", vim.json.encode(value))
end

function M.error_response(status, message)
	return M.json_response(status, { error = message })
end

return M
