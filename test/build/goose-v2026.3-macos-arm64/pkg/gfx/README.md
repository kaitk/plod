# goose_gfx

Graphics, audio and user interfaces for the
[Goose](https://github.com/aardappel/goose) programming language: `gfx`, a
window, input, GPU buffers, textures, graphics and compute pipelines on
SDL3's GPU API; `audio`, procedural PCM sound effects through SDL3; and
`ui`, immediate-mode windows and widgets on Nuklear, drawn through gfx. One
Goose *package* with three modules, since the three share one SDL build
and ui draws through gfx: `gfx.goose`, `audio.goose` and `ui.goose`, their
C layers under `src/`, and the CMakeLists that builds the layers with SDL3
and Nuklear, the submodules under `third_party/`.

The API references are in Goose's standard library documentation:
[gfx](https://github.com/aardappel/goose/blob/master/docs/stdlib.md#gfx),
[audio](https://github.com/aardappel/goose/blob/master/docs/stdlib.md#audio)
and [ui](https://github.com/aardappel/goose/blob/master/docs/stdlib.md#ui).
[docs/gfx.md](docs/gfx.md), [docs/audio.md](docs/audio.md) and
[docs/ui.md](docs/ui.md) describe how the layers are built.

## Using it

The three are blessed packages of Goose: a program imports them by name,

```goose
import gfx;
import audio;
import ui;
```

and the compiler knows where they come from. A compiler built with
`-DGOOSE_BUILTIN_LIBS=all` has the package compiled in and runs such a
program with nothing else installed; otherwise the compiler fetches this
repository at the pinned tag into `~/.goose` the first time, builds the
layers with cmake and the C compiler it finds on the machine, and keeps
them for every program after that.

To use a particular version, a fork, or a checkout of your own, declare the
package in the program's root file instead, under its package name `gfx`;
the other two modules are then `gfx.audio` and `gfx.ui`:

```goose
import gfx from "aardappel/goose_gfx@v1";   // this repository, at a tag
import gfx.audio;
import gfx.ui;
```

`goose build program.goose` links the layers into the executable, and
`goose program.goose` runs it in-process. Shaders are GLSL, compiled into
the program by the compiler's `embed_shader`. Programs in Goose's
[samples](https://github.com/aardappel/goose/tree/master/samples) show all
three modules in use.

## Layout

| | |
|---|---|
| `gfx.goose`, `audio.goose`, `ui.goose` | the modules: constants, the structs that cross to C, the `extern fn`s and thin wrappers |
| `gfx.build` | the package's sidecar: the CMake target to build, and that its functions run on the main thread only |
| `CMakeLists.txt` | builds SDL3, `goose_gfx`, `goose_audio` and `goose_ui` as static libraries, carried by the target `goose_gfx_package` |
| `src/gfx/`, `src/audio/`, `src/ui/` | the layers; each `*_api.h` lists every function its module declares, and `test/api_check.py` checks the two agree |
| `src/gfx/gfx_blob.h` | the shader blob the compiler writes and the layer reads, a copy of the compiler's header kept in step by the blob's version |
| `test/audio_device.c` | the audio layer's own test, the CMake target `goose_audio_test` |
| `test/window/` | the gfx showcase and input test, which need a display and a GPU; run from a Goose checkout |
| `third_party/SDL`, `third_party/nuklear` | shallow submodules pinned to commits; clone with `--recursive` |

The headless tests of the modules run in Goose's own test suite.

## License

Apache License 2.0, as Goose. SDL and Nuklear have their own licenses in
their repositories.
