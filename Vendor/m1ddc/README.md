# Display routing source

`ioregistry.m`, `ioregistry.h` and `utils.h` come from https://github.com/waydabber/m1ddc at commit `04d949794102eb8df01ad3681afff6464a3eede2` (MIT, copyright 2021 waydabber). LICENSE is included in this directory and the app bundle.

Perch changes: initialize/check display enumeration, release temporary property-key strings and the registry root, and compile for up to 16 displays. This adapter is used only in a short-lived command process. Its retained display dictionaries/strings and adapters are bounded by that process lifetime; it is not a long-lived in-process API.

Perch does not compile upstream's unrestricted CLI or I2C parser. `Sources/PerchDisplay.m` exposes only list, current input, capabilities, and input selection; `DDCWire.c` validates response headers, status, feature, length and checksum. No brightness, factory reset, power, KVM or arbitrary VCP command is exposed. The adapter uses private Apple IOAV/CoreDisplay APIs, so future OS compatibility must be tested.
