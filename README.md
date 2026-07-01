# Godot Agent

An in-editor AI programming assistant for Godot 4.x. Talks to the models you already pay for — bring your own API key.

- **Supported providers**: Anthropic (Claude), OpenAI (ChatGPT), Google (Gemini).
- **Capabilities**: planning, coding (GDScript / scenes), asset generation (images), debugging.
- **UI**: appears as an **"AI"** tab next to *2D / 3D / Script* on top of the editor.
- **Full Godot access**: the agent can read/write files, inspect and edit scenes, attach scripts, run the project, and query `ClassDB` — through a canonical tool interface each provider is adapted to.
- **Optional internet access**: toggle in the top bar. When on, each provider uses its native web search (Anthropic `web_search_20250305`, OpenAI `web_search`, Gemini `google_search`).
- **Requires Godot 4.x**. Pure GDScript, no compilation or external dependencies.

## Install

### Option A — clone this repo as a Godot project

```
git clone https://github.com/<you>/godot-agent.git
```

Open the folder in Godot 4 (`Project → Import`). The addon is already listed under `Project → Project Settings → Plugins`.

### Option B — drop the addon into your own project

Copy `addons/godot_agent/` into your project's `addons/` folder, then enable **Godot Agent** in `Project → Project Settings → Plugins`.

## Configure

1. Open the **AI** tab in the top toolbar.
2. Click **Settings**.
3. Paste an API key for at least one provider. Keys are saved in `EditorSettings` (user-scoped, never written to your project files).
4. Pick a provider from the top bar and start chatting.

Default models can be overridden in Settings:

| Provider  | Default                          |
| --------- | -------------------------------- |
| Anthropic | `claude-sonnet-4-5-20250929`     |
| OpenAI    | `gpt-5`                          |
| Gemini    | `gemini-2.5-pro`                 |

## What the agent can do

The agent exposes a canonical toolset that every provider is adapted to:

| Domain     | Tools |
| ---------- | ----- |
| Filesystem | `list_project_files`, `read_file`, `write_file`, `create_directory` |
| Scenes     | `get_current_scene`, `get_scene_tree`, `get_node`, `open_scene`, `save_scene`, `create_node`, `delete_node`, `set_node_property`, `attach_script` |
| Scripts    | `create_script`, `patch_script` |
| Editor     | `run_project`, `stop_project`, `get_class_docs`, `list_singletons` |
| Assets     | `generate_image` (OpenAI `gpt-image-1` or Gemini Imagen) |

Anthropic doesn't do image generation, so when Claude is the chat provider the image tool automatically routes to whichever of OpenAI / Gemini has a key configured (change in Settings → *Image provider*).

## Architecture

```
addons/godot_agent/
├── plugin.cfg / plugin.gd       # EditorPlugin, adds "AI" main-screen tab
├── ui/
│   ├── main_screen.gd           # chat UI (built programmatically)
│   └── settings_dialog.gd
├── core/
│   ├── agent.gd                 # tool-calling loop
│   ├── conversation.gd          # canonical message store
│   ├── settings.gd              # EditorSettings-backed prefs + API keys
│   ├── logger.gd
│   └── http_client.gd           # awaitable HTTPRequest wrapper
├── providers/
│   ├── provider_base.gd
│   ├── provider_anthropic.gd    # /v1/messages
│   ├── provider_openai.gd       # /v1/chat/completions
│   ├── provider_gemini.gd       # v1beta/models/*:generateContent
│   └── provider_factory.gd
└── tools/
    ├── tool_schemas.gd          # canonical, provider-neutral tool defs
    ├── tool_registry.gd         # dispatch by name
    ├── project_tools.gd
    ├── scene_tools.gd
    ├── script_tools.gd
    ├── editor_tools.gd
    └── image_tools.gd
```

The conversation is stored in **provider-neutral** form (`{type: "text"|"tool_use"|"tool_result"}` blocks, à la Anthropic). Each provider adapter converts to and from its native format on send, so the same tool schemas and message history work with all three providers.

## Security notes

- API keys live in `EditorSettings`, which is per-user and not part of your project. They're **not** committed if you check `godot-agent` into git.
- The agent has direct write access to your project (`res://`) and can run the game. Review destructive tool calls in the chat log; keep the *"Warn on destructive tool calls"* setting on if you want a heads-up.
- When **Web** is off, no HTTP request is made outside your chosen provider's chat endpoint.

## License

MIT — see [LICENSE](LICENSE).
