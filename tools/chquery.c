/* 临时工具：对通话记录库执行一条只读 SQL 并打印结果。用法：chquery "SQL" */
#include <stdio.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc < 2) { printf("usage: chquery <sql>\n"); return 2; }
    const char *path = argc > 2 ? argv[2] : "/var/mobile/Library/CallHistoryDB/CallHistory.storedata";
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        printf("open error: %s\n", db ? sqlite3_errmsg(db) : "?");
        return 1;
    }
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, argv[1], -1, &st, NULL) != SQLITE_OK) {
        printf("prepare error: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return 1;
    }
    int n = sqlite3_column_count(st);
    for (int i = 0; i < n; i++) printf("%s%s", i ? " | " : "", sqlite3_column_name(st, i));
    printf("\n");
    int rc;
    while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
        for (int i = 0; i < n; i++) {
            int t = sqlite3_column_type(st, i);
            if (i) printf(" | ");
            if (t == SQLITE_NULL) printf("NULL");
            else printf("%s", sqlite3_column_text(st, i));
        }
        printf("\n");
    }
    if (rc != SQLITE_DONE) printf("step error: %s\n", sqlite3_errmsg(db));
    sqlite3_finalize(st);
    sqlite3_close(db);
    return 0;
}
