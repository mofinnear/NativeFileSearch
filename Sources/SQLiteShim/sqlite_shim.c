#include "sqlite_shim.h"

#include <locale.h>
#include <regex.h>
#include <stddef.h>
#include <string.h>

typedef struct {
    regex_t expression;
    int valid;
} NFSCompiledRegex;

static void nfs_free_regex(void *pointer) {
    NFSCompiledRegex *compiled = (NFSCompiledRegex *)pointer;
    if (compiled == NULL) {
        return;
    }
    if (compiled->valid) {
        regfree(&compiled->expression);
    }
    sqlite3_free(compiled);
}

static void nfs_configure_regex_locale(void) {
    const char *current = setlocale(LC_CTYPE, NULL);
    if (current != NULL && strcmp(current, "C") != 0) {
        return;
    }

    // The default command-line-tool process locale can be "C" even though
    // macOS filenames are UTF-8. Prefer the user's UTF-8 locale, then use
    // common macOS locale names as fallbacks.
    if (setlocale(LC_CTYPE, "") == NULL ||
        (setlocale(LC_CTYPE, NULL) != NULL &&
         strcmp(setlocale(LC_CTYPE, NULL), "C") == 0)) {
        setlocale(LC_CTYPE, "UTF-8");
    }
    if (setlocale(LC_CTYPE, NULL) != NULL &&
        strcmp(setlocale(LC_CTYPE, NULL), "C") == 0) {
        setlocale(LC_CTYPE, "en_US.UTF-8");
    }
}

static void nfs_sqlite_regexp(
    sqlite3_context *context,
    int argumentCount,
    sqlite3_value **arguments
) {
    if (argumentCount != 2 ||
        sqlite3_value_type(arguments[0]) == SQLITE_NULL ||
        sqlite3_value_type(arguments[1]) == SQLITE_NULL) {
        sqlite3_result_int(context, 0);
        return;
    }

    const char *pattern = (const char *)sqlite3_value_text(arguments[0]);
    const char *value = (const char *)sqlite3_value_text(arguments[1]);
    if (pattern == NULL || value == NULL) {
        sqlite3_result_int(context, 0);
        return;
    }

    NFSCompiledRegex *compiled =
        (NFSCompiledRegex *)sqlite3_get_auxdata(context, 0);
    if (compiled == NULL) {
        compiled = (NFSCompiledRegex *)sqlite3_malloc(sizeof(*compiled));
        if (compiled == NULL) {
            sqlite3_result_error_nomem(context);
            return;
        }
        compiled->valid = 0;
        int compileResult = regcomp(
            &compiled->expression,
            pattern,
            REG_EXTENDED | REG_ICASE | REG_NOSUB
        );
        if (compileResult == 0) {
            compiled->valid = 1;
        }
        sqlite3_set_auxdata(context, 0, compiled, nfs_free_regex);
    }

    if (!compiled->valid) {
        // An invalid pattern is a non-match. The Swift layer logs the failed
        // query, while SQLite remains safe and the app keeps running.
        sqlite3_result_int(context, 0);
        return;
    }

    int matchResult = regexec(&compiled->expression, value, 0, NULL, 0);
    sqlite3_result_int(context, matchResult == 0 ? 1 : 0);
}

int nfs_sqlite_bind_text_copy(sqlite3_stmt *statement, int index, const char *value) {
    return sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT);
}

int nfs_sqlite_register_regexp(sqlite3 *database) {
    nfs_configure_regex_locale();
    return sqlite3_create_function_v2(
        database,
        "regexp",
        2,
        SQLITE_UTF8 | SQLITE_DETERMINISTIC,
        NULL,
        nfs_sqlite_regexp,
        NULL,
        NULL,
        NULL
    );
}
