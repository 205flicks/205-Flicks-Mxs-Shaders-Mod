# Build the native personal v2 renderer

Use Node.js and the official Zig 0.14.1 Windows x64 toolchain:

    node build.mjs C:/path/to/zig.exe

The helper resolves its own source folder, compiles the explicit C/assembly list,
creates import libraries from Windows system export tables, then links the DLL
at the repository root. It never installs, starts the game or loads the mod.
It uses no uploaded batch file. Generated/default_pack.c is a byte embedding of
shaderpacks/default/ and is included for inspection/rebuilding. If you edit GLSL,
regenerate those byte arrays before rebuilding; otherwise the embedded copy stays old.

The logo header is a grayscale GPU texture prepared from the user's original JPEG
in assets/, with only crop/resize for fitting; no replacement artwork was generated.
The source asset and derived header are both included. No extra image decoder is
loaded into the game.

See the root VALIDATION.md. Standalone test hosts and build intermediates are not
part of the normal runtime, and are excluded from this delivery.
