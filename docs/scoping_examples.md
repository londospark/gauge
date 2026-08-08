# Scoped resources: worked examples (Dear ImGui, ported)

This is a browse-along companion to [scoping.md](scoping.md). It takes real,
canonical [Dear ImGui](https://github.com/ocornut/imgui) patterns and shows how
they read in londolang's proposed `scoped` syntax. The language isn't built
yet — the lexer and AST exist; these are the target shape.

## The cast: ImGui → londolang

| Dear ImGui (C++) | londolang (`scoped`) |
|---|---|
| `ImGui::NewFrame()` / `ImGui::Render()` | `Frame { ... }` |
| `ImGui::Begin(name)` / `ImGui::End()` | `Window(name) { ... }` |
| `if (ImGui::Begin(name)) { ...; ImGui::End(); }` | `Window(name) { ... }` — the failure gate |
| `ImGui::PushFont(f)` / `ImGui::PopFont()` | `Font(f) { ... }` |
| RAII wrapper classes (`ImScoped::Window`) | none needed — blocks do it |

## The scoped resources

```odin
Frame  :: scoped { imgui_new_frame, imgui_render }
Window :: scoped { window_begin, window_end }
Font   :: scoped { font_push, font_pop }
```

## Example 1 — hello, world!

The canonical first window:

```cpp
ImGui::Begin("Hello, world!");
ImGui::Text("This is some useful text.");
ImGui::End();
```

```odin
Frame {
	Window("Hello, world!") {
		Text("This is some useful text.")
	}
}
```

`Frame` and `Window` nest; the frame is torn down after the window. Both
pairings are guaranteed by construction.

## Example 2 — the failure gate (collapsed windows)

`ImGui::Begin` returns `false` when the window is collapsed, so the canonical
C++ is an `if`:

```cpp
if (ImGui::Begin("My Window")) {
    ImGui::Text("This code is only shown if the window is open.");
    ImGui::End();
}
```

In londolang the scoped block *is* the gate — if the constructor returns
`false`, the body is skipped and no cleanup runs, so the `if` disappears:

```odin
Frame {
	Window("My Window") {
		Text("This code is only shown if the window is open.")
	}
}
```

Clay's `layout_begin` always succeeds; ImGui's can fail. The gate covers both.

## Example 3 — real work: checkboxes, a button, and a closing flag

From the ImGui demo ("Hello, world!" window):

```cpp
static bool show_demo_window = true;
static bool show_another_window = false;

ImGui::Begin("Hello, world!");
ImGui::Text("This is some useful text.");
ImGui::Checkbox("Demo Window", &show_demo_window);
ImGui::Checkbox("Another Window", &show_another_window);
if (ImGui::Button("Close Me")) show_demo_window = false;
ImGui::End();

if (show_another_window) {
    ImGui::Begin("Another Window", &show_another_window);
    ImGui::Text("Hello from another window!");
    if (ImGui::Button("Close Me")) show_another_window = false;
    ImGui::End();
}
```

```odin
show_demo_window     := true
show_another_window  := false

Frame {
	Window("Hello, world!") {
		Text("This is some useful text.")
		Checkbox("Demo Window", &show_demo_window)
		Checkbox("Another Window", &show_another_window)
		if Button("Close Me") {
			show_demo_window = false
		}
	}

	if show_another_window {
		Window("Another Window", &show_another_window) {
			Text("Hello from another window!")
			if Button("Close Me") {
				show_another_window = false
			}
		}
	}
}
```

Notes:

- `&show_demo_window` is ImGui's `p_open` — the window writes the open flag
  through the pointer. Same semantics, same spelling.
- The body can `return`, `break`, or throw — `window_end` still runs, because
  it's a defer.
- A window guarded by `if show_another_window` is just a normal conditional
  around a scoped block.

## Example 4 — a tool window with sliders

```cpp
ImGui::Begin("Parameters");
static float value = 0.5f;
static int count = 4;
ImGui::SliderFloat("value", &value, 0.0f, 1.0f);
ImGui::SliderInt("count", &count, 1, 32);
ImGui::End();
```

```odin
Frame {
	Window("Parameters") {
		Slider("value", &value, 0.0, 1.0)
		Slider("count", &count, 1, 32)
	}
}
```

The sliders do real work — they read and write the bound variables through the
pointers — and the window is guaranteed closed around them.

## Example 5 — a multi-resource scope (LIFO)

`PushFont`/`PopFont` is a perfect scoped pair, and it shows why the multi form
is worth having. Here the window is the implicit `it`; the font gets a name:

```cpp
ImGui::Begin("Debug");
ImGui::PushFont(font_mono);
ImGui::Text("monospaced");
ImGui::PopFont();
ImGui::End();
```

```odin
Frame {
	Window("Debug"),
	Font(font_mono) as mono {
		Text("monospaced")
	}
}
```

The defers stack **LIFO**: the font pops before the window ends — exactly the
order the C++ demands. At most one resource uses the implicit `it`; every other
resource needs `as name` (forcing names for all in the multi case is an open
option).

## Example 6 — a scoped frame plus persistent state

The frame itself is just another scoped resource, so the whole app loop is
blocks end to end:

```odin
main :: () {
	window := create_window(...)
	// ...
	for running {
		Frame {
			Toolbar { ... }
			if show_viewport {
				Viewport { ... }
			}
		}
	}
}
```

Persistent state (flags, sizes, the window handle) lives in plain variables;
the scoped resources only bound the per-frame begin/end pairs.

## Why these aren't just macros or wrappers

Each example is pure sugar over the pair it names — `Window("Debug")` is
`window_begin(&it, "Debug")` + `defer window_end(&it)`. There is no object, no
hidden state, no macro, and no ownership machinery. The arena/stack memory is
still yours; the syntax only guarantees the pairing.
