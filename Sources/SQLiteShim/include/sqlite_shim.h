#ifndef NFS_SQLITE_SHIM_H
#define NFS_SQLITE_SHIM_H

#include <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Binds a UTF-8 string and asks SQLite to make its own copy.
int nfs_sqlite_bind_text_copy(sqlite3_stmt *statement, int index, const char *value);

/// Registers the UTF-8, case-insensitive REGEXP function used by advanced
/// filename and path searches.
int nfs_sqlite_register_regexp(sqlite3 *database);

#ifdef __cplusplus
}
#endif

#endif /* NFS_SQLITE_SHIM_H */
