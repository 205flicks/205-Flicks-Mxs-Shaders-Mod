# Build 205 Flicks MXS Shaders Mod V3 (public)

Use Node.js and Zig 0.14.1 for Windows x64. From this source directory run:

    node build.mjs C:/path/to/zig.exe

The build helper uses its own directory, compiles the explicit C/assembly units,
creates Windows import libraries from the system DLL export tables, and writes
opengl32.dll one directory above this source folder. It does not load the result,
install it, modify the game executable, or start MX Simulator.

The generated/default_pack.c file embeds every shaderpacks/default file as bytes.
It matches the supplied shader sources. If editing GLSL, regenerate that payload
before rebuilding. The original logo asset and its derived header are included.

The public edition uses standard JSC500 depth of field. Its first-launch settings
are generated from the same Balanced values as the included Balanced preset.
Saved settings are kept in %LOCALAPPDATA%/205 Flicks MXS Shaders V3, separately
from the V2 editions. Existing V3 settings are preserved on later launches.

See VALIDATION.md and LICENSE-NOTICES.txt. The user's release README is left
unchanged in the install package and is not replaced by this source archive.
