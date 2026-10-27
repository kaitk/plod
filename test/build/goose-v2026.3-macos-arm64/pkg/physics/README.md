# goose_physics

Rigid body physics for the [Goose](https://github.com/aardappel/goose)
programming language, on [Box3D](https://github.com/erincatto/box3d): worlds,
bodies, shapes of every kind Box3D has, joints, events, queries, a character
mover, recording and replay. A Goose *package*: the module `physics.goose`,
its C layer under `src/`, and the CMakeLists that builds the layer with
Box3D, which is the submodule `third_party/box3d`.

The API reference is Goose's
[standard library documentation](https://github.com/aardappel/goose/blob/master/docs/stdlib.md#physics),
and [docs/physics.md](docs/physics.md) describes how the layer is built.

## Using it

Physics is one of Goose's blessed packages: a program imports it by name,

```goose
import physics;
```

and the compiler knows where it comes from. A compiler built with
`-DGOOSE_BUILTIN_LIBS=all` has the package compiled in and runs such a
program with nothing else installed; otherwise the compiler fetches this
repository at the pinned tag into `~/.goose` the first time, builds the
layer with cmake and the C compiler it finds on the machine, and keeps it
for every program after that.

To use a particular version, a fork, or a checkout of your own, declare the
package in the program's root file instead:

```goose
import physics from "aardappel/goose_physics@v1";   // this repository, at a tag
import physics from "../goose_physics";             // a directory, used in place
```

`goose build program.goose` links the layer into the executable, and `goose
program.goose` runs it in-process. Programs in Goose's
[samples](https://github.com/aardappel/goose/tree/master/samples) show it in
use.

## Layout

| | |
|---|---|
| `physics.goose` | the module: constants, the structs that cross to C, the `extern fn`s and thin wrappers |
| `physics.build` | the package's sidecar: the CMake target to build, and that its functions run on the main thread only |
| `CMakeLists.txt` | builds Box3D and `goose_physics`, the layer, as static libraries |
| `src/` | the layer: `physics_api.h` lists every function the module declares; the test suite in Goose's repository checks the two agree (`test/api_check.py`) |
| `third_party/box3d` | Box3D, a shallow submodule pinned to a commit; clone with `--recursive` |

## License

Apache License 2.0, as Goose. Box3D has its own license in its repository.
