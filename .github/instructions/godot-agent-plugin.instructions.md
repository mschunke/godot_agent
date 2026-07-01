---
description: "Use when editing the godot-agent plugin under `addons/godot_agent/`. Covers Godot 4.7 strict typing, @tool script hot-reload signal quirks, the canonical Anthropic-style message block format used across providers, Gemini thoughtSignature round-tripping, EditorSettings conventions, and Control/RichTextLabel UI pitfalls."
applyTo: "addons/godot_agent/**/*.gd"
---

# godot-agent Plugin Conventions

Godot 4.7 editor plugin. Everything under `addons/godot_agent/` runs inside the editor as a `@tool` script.

## Language and typing

- Every script starts with `@tool`. Omitting it means the class doesn't load in the editor.
- Godot 4.7 rejects `:=` inference when the right-hand side is `Variant` (typical for `Dictionary.get(...)`, `preload(...).new()`, factory returns). Declare the type explicitly:
  ```gdscript
  var pf: Variant = ProviderFactory.create(provider)      # factory can return null
  var rect: Rect2 = anchor.get_global_rect()              # untyped Control API return
  var is_pure_thought: bool = bool(p.get("thought", false)) or ...
  ```
- Never name a method `_get` / `_set` on a script that inherits from `Object` — they shadow the built-in virtuals. Use `_read` / `_write` (see `core/settings.gd`).
- `Control.get_screen_rect()` does **not** exist in Godot 4. Use `anchor.get_screen_position()` + `anchor.size`.

## `@tool` signal connections

Named-callable signal connections on nodes owned by hot-reloaded `@tool` scripts occasionally fire against the previous script revision and throw `Method not found`. When connecting a signal on a child `Control` (e.g. `TextEdit.gui_input`), prefer an inline lambda so the callable captures the current script state directly:

```gdscript
_input.gui_input.connect(func(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
            accept_event()
            _on_send_pressed())
```

Named `.connect(_on_named)` is still fine for signals on the agent / long-lived autoloads.

## Canonical conversation format

All providers (`providers/*.gd`) speak the same Anthropic-style block schema through `core/conversation.gd`:

- Roles: `system`, `user`, `assistant`.
- Block `type` values: `text`, `tool_use`, `tool_result`, `thought`.
- Tool calls carry `id`, `name`, `input`. Tool results echo the same `tool_use_id`.
- Provider-native data that must round-trip verbatim is stashed on the block under keys prefixed with the provider name (e.g. `_gemini_native_part`). Never rename these keys — they exist in stored conversation JSON files.

Providers convert to/from their native format in `_convert_messages` and their `send_conversation` response parser. When adding a new field, keep both directions symmetric.

## Gemini `thoughtSignature`

Gemini 2.5+ thinking models require every signed part to be echoed back verbatim on the next turn or the API rejects the request. Three signature shapes must be handled:

1. Inside a `functionCall` part (signature sibling of `functionCall` in the same part).
2. A bare `thoughtSignature` part with no visible text (pure thought).
3. Attached to a final visible text part — **still user-visible**; do not classify as thought.

Rule in `provider_gemini.gd`:

```gdscript
var is_pure_thought: bool = bool(p.get("thought", false)) or (p.has("thoughtSignature") and not p.has("text"))
```

Store the whole raw part (`_gemini_native_part`) on the block whenever a signature is present, and echo it back in `_convert_messages`.

## Provider response shape

Every `send_conversation` must return:

```gdscript
{
  "ok": bool,
  "error": String,                     # only when ok == false
  "stop_reason": String,               # end_turn | tool_use | max_tokens | error | ...
  "text": String,                      # user-visible assistant text for message_appended
  "tool_calls": Array,                 # [{id, name, input}]
  "assistant_content": Array,          # canonical blocks to persist
  "usage": Dictionary,
}
```

`_run_loop` in `core/agent.gd` fires `message_appended("assistant", resp.text)` only when `text != ""`, so make sure the parser puts final answer text in `text` — misclassifying it as thought is what causes "the final follow-up bubble never appears".

## Settings and storage

- All keys live in `EditorSettings` under the `godot_agent/` prefix. Read/write only through `core/settings.gd`.
- User-scoped values (API keys, model choices, provider) go in EditorSettings. Never write them to project files.
- Conversations persist as JSON in `res://addons/godot_agent/conversations/<id>.json` via `core/conversation_store.gd`. Autosave is driven by the `Conversation.changed` signal.

## HTTP

`HTTPRequest` must be attached to a live `Node` — providers accept `parent: Node` and hand it to `core/http_client.gd`. Don't spin up detached `HTTPRequest` nodes.

## UI

- `main_screen.gd` is added as a main-screen tab; it must set `size_flags_horizontal/vertical = SIZE_EXPAND_FILL` **and** anchor `PRESET_FULL_RECT` to avoid collapsing to the middle of the editor.
- `RichTextLabel` with `fit_content = true` inside a `VBoxContainer` occasionally lays out at height 0 before the next frame. Always give bubble bodies `custom_minimum_size = Vector2(0, 24)`.
- Scroll-to-bottom after appending should retry across ~6 frames (`await get_tree().process_frame`) because `ScrollBar.max_value` isn't final on the first frame after adding children.

## Files layout

```
addons/godot_agent/
  plugin.gd, plugin.cfg          # EditorPlugin entry point
  core/                          # agent loop, conversation, settings, http, logger, store
  providers/                     # provider_base + one file per vendor + factory
  tools/                         # tool_registry, tool_schemas, and per-domain *_tools.gd
  ui/                            # main_screen + dialogs
  conversations/                 # persisted chats (gitignored expectation)
```

New tools go in `tools/<domain>_tools.gd` and register in `tool_registry.gd` + `tool_schemas.gd`. New providers implement `provider_base.gd` and are wired through `provider_factory.gd`.
