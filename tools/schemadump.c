/* 临时工具：以只读方式打印通话记录数据库的结构与样本行，供开发期间确认字段。 */
#include <stdio.h>
#include <sqlite3.h>

static int row_cb(void *u, int n, char **v, char **c) {
    (void)u; (void)c;
    for (int i = 0; i < n; i++) {
        printf("%s%s", i ? " | " : "", v[i] ? v[i] : "NULL");
    }
    printf("\n");
    return 0;
}

static void query(sqlite3 *db, const char *label, const char *sql) {
    printf("\n== %s ==\n", label);
    char *err = NULL;
    int rc = sqlite3_exec(db, sql, row_cb, NULL, &err);
    if (rc != SQLITE_OK) {
        printf("error: %s\n", err ? err : "?");
        sqlite3_free(err);
    }
}

static void sample(sqlite3 *db) {
    printf("\n== sample rows (name=value) ==\n");
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, "select * from ZCALLRECORD order by Z_PK desc limit 2", -1, &st, NULL) != SQLITE_OK) {
        printf("prepare failed: %s\n", sqlite3_errmsg(db));
        return;
    }
    int rows = 0;
    while (sqlite3_step(st) == SQLITE_ROW) {
        rows++;
        printf("-- row %d\n", rows);
        int n = sqlite3_column_count(st);
        for (int i = 0; i < n; i++) {
            const char *name = sqlite3_column_name(st, i);
            int type = sqlite3_column_type(st, i);
            printf("   %-28s = ", name);
            if (type == SQLITE_NULL) {
                printf("NULL\n");
            } else if (type == SQLITE_TEXT) {
                printf("\"%s\"\n", (const char *)sqlite3_column_text(st, i));
            } else if (type == SQLITE_BLOB) {
                printf("<blob %d bytes>\n", sqlite3_column_bytes(st, i));
            } else {
                printf("%s\n", sqlite3_column_text(st, i));
            }
        }
    }
    sqlite3_finalize(st);
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "/var/mobile/Library/CallHistoryDB/CallHistory.storedata";
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, NULL);
    if (rc != SQLITE_OK) {
        printf("open error %d: %s\n", rc, db ? sqlite3_errmsg(db) : "?");
        return 1;
    }
    query(db, "tables", "select name from sqlite_master where type='table' order by name");
    query(db, "ZCALLRECORD columns", "PRAGMA table_info(ZCALLRECORD)");
    query(db, "Z_PRIMARYKEY (call)", "select Z_ENT,Z_NAME,Z_MAX from Z_PRIMARYKEY where Z_NAME like '%CALL%'");
    query(db, "row count", "select count(*) from ZCALLRECORD");
    sample(db);
    sqlite3_close(db);
    return 0;
}
