// The clang shim that publishes `ffi/include/macmon.h` to Swift as `import CMacmon`.
//
// The header beside this file is a symlink into `ffi/include/`, so there is one canonical copy
// and this file only gives the target a translation unit.
#include "macmon.h"
