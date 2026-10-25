# SQLCipher

`//submodules/sqlcipher` exports the `SQLCipher` Clang module, statically built with Apple's CommonCrypto provider. It is the database engine behind `//libraries/grdb`; do not add a separate system SQLite dependency for GRDB.

The vendored amalgamation is SQLCipher **4.19.0 Community**, based on SQLite **3.53.4**. `Sources/sqlite3.c` and `include/sqlite3.h` were copied unchanged from the sibling `Telegram-iOS/submodules/sqlcipher` checkout:

| File | SHA256 |
| --- | --- |
| `Sources/sqlite3.c` | `8640c653acadf665cce6331646f60b5b74a4690746f2c4a2d8f688a0570a0c0c` |
| `include/sqlite3.h` | `8a9d1bff44d75174ca6dea3ea9bac50a6104d86facb566647b8bb839375b7b3a` |

Contact builds independently of Telegram. Upstream source: <https://github.com/sqlcipher/sqlcipher/tree/v4.19.0>. The generated amalgamation is checked in so building Contact does not require generating SQLite sources or accessing the sibling repository.

The build enables the codec, CommonCrypto, required SQLCipher initialization/shutdown hooks, threads, FTS5 and in-memory temporary storage. It disables default memory statistics and mmap support. Unlike Telegram's build, it retains declaration types, progress callbacks and deprecated APIs required by GRDB. Runtime connection settings and the encryption key belong to the future account-storage layer; linking SQLCipher alone does not encrypt a database.

`include/grdb_config.h` is GRDB 7.11.1's `Support/SQLCipher_config.h`, with only its include changed from `<SQLCipher/sqlite3.h>` to `"sqlite3.h"`. It exposes the upstream variadic-function wrappers to Swift. `SQLCipher.h` and the module map are Contact's integration headers.

SQLCipher's source license is preserved in the amalgamation and `SQLCipher-LICENSE.txt`; the latter is bundled with GRDB's MIT license in `GRDB.bundle`.
