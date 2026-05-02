# TODO

## v0.2 — Session-scope opt-in

Currently the library is mount-scoped: state is discarded on every full page load (initial mount), preserved across remounts (dropped-connection recovery).

**This is a policy decision, not a storage limitation.** The storage is keyed by the WebSocket CSRF token, which survives full reloads (it's session-tied — only rotates on logout/session expiry/cookie clear). What makes the *behavior* mount-scoped is the explicit `store().put(token, %{})` call inside the `_mounts == 0` branch of `mount/1`, which wipes the entry on every fresh mount.

To add session-scope as an opt-in, skip that wipe for components that opted in:

```elixir
StickyAssigns.recover(socket, id, [tab: :general], scope: :session)
# default: scope: :mount (current behavior)
```

Implementation sketch:
- Track per-component scope alongside defaults in the `:sticky_assigns_defaults` PD entry
- On `_mounts == 0`, instead of wiping the whole token entry, partition by scope:
  load saved values for `:session`-scoped components, drop `:mount`-scoped ones
- Document UX implications clearly (state survives reload — user has no URL to share, no force-reload to reset; this is the same UX as localStorage but server-side)

### Why we held this for v0.2

- v0.1 should ship the mechanism that's already battle-tested in Jot (mount-scope only)
- Session-scope semantics deserve their own design pass, especially around:
  - Multi-tab interactions (same token, multiple LVs writing the same component_id)
  - When to expire entries (today they live forever in ETS — fine for mount-scope where wipe-on-reload bounds growth, problematic for session-scope)
  - Default behavior for the existing ETS backend (does it need TTL?)

### Notes from the analysis

- `phoenix_live_session` (pentacent) solves "LV writes session" by replacing `Plug.Session` with an ETS-backed store. We don't need to absorb that — our existing ETS-by-CSRF-token store gives us session-persistence "for free" once we drop the explicit wipe.
- localStorage via JS hooks (Jot's current approach for theme / sidebar / hotbar) is a *different* mechanism with the same UX surface. It avoids the LV-can't-write-cookies problem by writing client-side. A future v0.3 could add `scope: :local_storage` for LS-backed sticky assigns, but that's significantly more work (JS hook + handshake on mount).

## v0.2 — Other items

- [ ] Phoenix.LiveViewTest integration test covering full mount → recover → preserve → remount cycle (current tests exercise the PD-state branches directly)
- [ ] LiveView-level recovery (currently only LiveComponents)
- [ ] TTL / size limits on `StickyAssigns.Store.ETS`
- [ ] Built-in Redis backend
- [ ] Replace `:_mounts` / `:_csrf_token` magic-string params with structured options or document them as the contract

## Quality

- [ ] Doctests on the public functions
- [ ] Bench: store contention under many concurrent LVs
- [ ] CHANGELOG.md once we cut 0.1.0
- [ ] Hex publish
