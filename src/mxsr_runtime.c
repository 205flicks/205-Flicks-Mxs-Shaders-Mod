/* Minimal C helpers for the LLVM/UCRT build. MIT; LICENSE-MXSR.txt.
 * This all-C module has constant static initializers and no C++ constructors.
 * Windows loads the imported UCRT; this DLL uses its own DllMain entry directly.
 */
#include <stdio.h>
#include <stdarg.h>
#include <math.h>

int __cdecl vfprintf(FILE *stream, const char *format, va_list args)
{
    return __stdio_common_vfprintf(0, stream, format, NULL, args);
}

/* Compile this unit with -fno-builtin so these calls are not folded into sincos. */
void sincos(double x, double *s, double *c)
{
    *s = sin(x);
    *c = cos(x);
}
