# Dooing LAN sync protocol

This document is **normative**: the plugin's server and the companion app are
both checked against it, and a disagreement between an implementation and
this document is a bug in the implementation.

Scope: dooing's own bus — todos over the LAN. Time blocks belong to
bloocky.nvim, which documents its own formats in `bloocky.nvim/docs/`; the
`/blocks` endpoint here is a deprecated passthrough (see below).

## Transport

Plain HTTP over the local network, default port **7283**, bound to `0.0.0.0`
(configurable: `sync.server.bind`, `sync.server.port`). The server accepts
one request per connection and closes it (`Connection: close`).

The threat model and its consequences:

- **No CORS headers, ever.** A browser page must not be able to read
  responses.
- **Any request carrying an `Origin` header is rejected 403** — nothing
  legitimate sends one to this server.
- **The `Host` header must be an IP literal (or `localhost`) with the
  server's port**, otherwise 403. DNS rebinding needs a DNS *name*; the
  plugin only ever hands out IP literals.
- Request caps: 8 KB of headers, 1 MB of body, 16 concurrent connections,
  10 s idle timeout. `Transfer-Encoding` is not supported; requests are
  framed by `Content-Length` only.
- The device list lives at `stdpath("state")/dooing/devices.json`, mode
  `0600`, and stores only the **sha256** of each bearer token.

## Versions and the QR payload

`GET /version` (public) identifies the server:

```json
{ "protocol": 2, "product": "dooing" }
```

The QR page (`GET /`, public — it is what the plugin opens in your browser)
encodes a JSON payload:

```json
{ "v": 2, "p": "dooing", "host": "http://192.168.1.20:7283", "t": "<pairing token>" }
```

- `v` — protocol version. `p` — which product's bus this is.
- `t` — a **single-use pairing token**, minted per page load, valid 10
  minutes, dead after any restart of Neovim.

The **v1 payload** was the bare string `http://<ip>:7283/todos`. Clients that
can parse both should prefer v2. Servers older than protocol 2 have no
`/version` endpoint — a 404 there means v1.

## Pairing

```
POST /v2/pair
{ "token": "<pairing token from the QR>", "device_name": "atila-iphone" }

200 { "device_id": "…", "device_token": "…", "name": "…" }
401 { "error": "invalid or expired pairing token" }
```

The `device_token` is the long-lived credential. It is returned exactly once
and never stored in plaintext on the plugin side; the client must keep it in
the platform keychain (SecureStore), not in ordinary app storage.

## Data endpoints

`GET /todos` — the todos file, verbatim, read from disk **per request**.
`GET /blocks` — bloocky's blocks file, verbatim. **Deprecated**: this exists
so one product's absence degrades a feature rather than breaking a product,
but blocks belong on bloocky's own bus and this passthrough will be removed
one release after that bus ships.

Auth posture: both endpoints require `Authorization: Bearer <device_token>`
**unless** `sync.server.allow_v1 = true` (the current default), which keeps
them public for app builds that predate pairing. `allow_v1` will default to
`false` one release later. The browser guards above apply in every mode.

## Todo wire shape

The array element shape is dooing's `state.lua` todo, byte-compatible with
`dooing-app/src/types/todo.ts`. Two rules matter for sync:

- **`updated_at`** (unix **seconds**, like every timestamp here) is bumped by
  the plugin on every mutation. It is *optional for readers*: absent means
  "fall back to `created_at`". It is used only to break genuine conflicts and
  order reports — change detection never trusts it.
- **Unknown keys must be preserved** by every reader that writes the shape
  back. The schema is allowed to grow without a lockstep release only
  because of this rule.

## The v2 sync exchange

```
POST /v2/sync/todos            (Authorization: Bearer <device_token>)
{ "revision": 41, "todos": [ …full device state… ],
  "tombstones": [ { "id": "…", "deleted_at": 1755043200 } ] }

200 { "revision": 42, "todos": [ …merged state… ],
      "tombstones": [ … ], "conflicts": [ … ] }
```

**Full state, not deltas.** The device sends everything it has; the server
merges it against the per-device base it stored at the last exchange (its
sidecar, `dooing_sync.json`) and replies with the merged state, which the
device installs (reconciling any mid-flight edits through its own copy of the
merge engine). After a 200, both sides hold the same list.

Rules a client must follow:

- **Send tombstones for every deletion** since the last exchange, with
  `deleted_at` in unix seconds. After a 200 the client's tombstone list is
  drained — the server has recorded what it needs.
- **The response is the new base.** Store `response.todos` (keyed by id) as
  the agreement; change detection compares live state against it. If the
  user edited while the request was in flight, reconcile
  `(sent, current, response)` three-way — never clobber, never re-send blind.
- **The merge is normative** in the shared fixture corpus
  (`spec/fixtures/merge/cases.json`). Per field group; base decides changed;
  `updated_at` breaks genuine ties; on an exact timestamp tie the
  lexicographically smaller device id wins — the server calls itself
  `"server"`, which sorts after every hex device id, so **ties go to the
  device**. Delete-vs-edit resurrects. Losing values come back in
  `conflicts` (with `loser_todo` where available) and are also trailed
  server-side for `:DooingSyncRestore`.
- `revision` increments per exchange per device; it is informational (the
  base carries the actual state).

Errors: `401` unpaired or revoked; `400` malformed body; `404` a pre-v2
plugin — fall back to the read-only v1 `GET /todos`.

## Server behaviour worth knowing

- The exchange always operates on the **global** list. If a project list is
  loaded in the Neovim session, the global file is updated on disk and the
  live project state is not touched.
- The server never re-stamps merged todos (`state.replace_global_todos`) —
  `updated_at` values are part of the agreement both sides hold.
- Concurrent writers of the todos file (a second Neovim instance) are merged
  through the same engine at save time, not clobbered.
