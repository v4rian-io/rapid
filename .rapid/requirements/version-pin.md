# feature/version-pin

A repository holds data alone under .rapid, pinning the rapid version it runs: setup writes the pin beside hook stubs, the installed rapid serves each repository at its pinned tag, an upgrade is an admin MODE commit of the pin, which rapid upgrade writes.

Test: version-pin
