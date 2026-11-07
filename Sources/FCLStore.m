/*
 * 通话记录库的读写。
 *
 * 数据库在 /var/mobile/Library/CallHistoryDB/CallHistory.storedata（Core Data，WAL 模式），
 * 受 data vault 保护：调用方的二进制必须带
 * com.apple.private.security.storage.CallHistory 与 com.apple.private.CallHistory.read-write
 * （见 tools/App.entitlements），否则连打开都会被拒绝。
 */
#import "FCLStore.h"
#import <sqlite3.h>
#import <uuid/uuid.h>

static NSString *const kDBPath = @"/var/mobile/Library/CallHistoryDB/CallHistory.storedata";

/* 测试时可以指向数据库的副本，避免动到真实记录。 */
static NSString *FCLDBPath(void) {
    const char *env = getenv("FCL_DB_PATH");
    if (env && *env) return [NSString stringWithUTF8String:env];
    return kDBPath;
}

static NSString *FCLCountryCodeForNumber(NSString *address) {
    NSString *digits = [[address stringByReplacingOccurrencesOfString:@"+" withString:@""]
                        stringByReplacingOccurrencesOfString:@" " withString:@""];
    digits = [digits stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (digits.length == 11 && [digits hasPrefix:@"1"]) return @"cn";
    if ([address hasPrefix:@"0"] || [address hasPrefix:@"+86"]) return @"cn";
    return nil;
}

NSString *FCLInsertCallRecord(NSString *address, NSString *name, NSDate *date,
                              BOOL originated, BOOL answered, double duration) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(FCLDBPath().UTF8String, &db, SQLITE_OPEN_READWRITE, NULL);
    if (rc != SQLITE_OK) {
        NSString *msg = [NSString stringWithFormat:@"打开数据库失败(%d): %s", rc,
                         db ? sqlite3_errmsg(db) : "?"];
        if (db) sqlite3_close(db);
        return msg;
    }
    sqlite3_busy_timeout(db, 5000);

    static const char *kInsertSQL =
        "INSERT INTO ZCALLRECORD (Z_PK, Z_ENT, Z_OPT, ZANSWERED, ZCALL_CATEGORY, ZCALLTYPE,"
        " ZDISCONNECTED_CAUSE, ZHANDLE_TYPE, ZORIGINATED, ZREAD, ZVERIFICATIONSTATUS, ZDATE,"
        " ZDURATION, ZADDRESS, ZISO_COUNTRY_CODE, ZNAME, ZSERVICE_PROVIDER, ZUNIQUE_ID,"
        " ZJUNKCONFIDENCE, ZNUMBER_AVAILABILITY, ZFILTERED_OUT_REASON)"
        " VALUES (?, 2, 1, ?, 1, 1, ?, 2, ?, 1, 0, ?, ?, ?, ?, ?, 'com.apple.Telephony', ?, 0, 0, 0)";

    NSString *failure = nil;
    sqlite3_stmt *st = NULL;
    long long nextPK = 0;
    char uuidStr[37] = {0};
    unsigned char uuidBytes[16] = {0};
    NSString *cc = nil;
    BOOL ok = YES;

    if (sqlite3_exec(db, "BEGIN IMMEDIATE", NULL, NULL, NULL) != SQLITE_OK) {
        failure = [NSString stringWithFormat:@"开启事务失败: %s", sqlite3_errmsg(db)];
        ok = NO;
    }

    if (ok) {
        if (sqlite3_prepare_v2(db, "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='CallRecord'", -1, &st, NULL) == SQLITE_OK &&
            sqlite3_step(st) == SQLITE_ROW) {
            nextPK = sqlite3_column_int64(st, 0);
        }
        if (st) { sqlite3_finalize(st); st = NULL; }
        if (nextPK <= 0) {
            failure = @"找不到 Z_PRIMARYKEY 的 CallRecord 行";
            ok = NO;
        }
    }

    if (ok) {
        nextPK += 1;
        uuid_generate(uuidBytes);
        uuid_unparse_upper(uuidBytes, uuidStr);
        cc = FCLCountryCodeForNumber(address);

        if (sqlite3_prepare_v2(db, kInsertSQL, -1, &st, NULL) != SQLITE_OK) {
            failure = [NSString stringWithFormat:@"准备插入语句失败: %s", sqlite3_errmsg(db)];
            ok = NO;
        }
    }

    if (ok) {
        int idx = 1;
        sqlite3_bind_int64(st, idx++, nextPK);
        sqlite3_bind_int(st, idx++, answered ? 1 : 0);
        sqlite3_bind_int(st, idx++, (answered || originated) ? 0 : 6); /* 未接来电的断开原因 */
        sqlite3_bind_int(st, idx++, originated ? 1 : 0);
        sqlite3_bind_double(st, idx++, [date timeIntervalSinceReferenceDate]);
        sqlite3_bind_double(st, idx++, duration);
        sqlite3_bind_text(st, idx++, address.UTF8String, -1, SQLITE_TRANSIENT);
        if (cc.length) sqlite3_bind_text(st, idx++, cc.UTF8String, -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(st, idx++);
        if (name.length) sqlite3_bind_text(st, idx++, name.UTF8String, -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(st, idx++);
        sqlite3_bind_text(st, idx++, uuidStr, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(st) != SQLITE_DONE) {
            failure = [NSString stringWithFormat:@"插入失败: %s", sqlite3_errmsg(db)];
            ok = NO;
        }
        sqlite3_finalize(st);
        st = NULL;
    }

    if (ok) {
        if (sqlite3_prepare_v2(db, "UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='CallRecord'", -1, &st, NULL) != SQLITE_OK) {
            failure = [NSString stringWithFormat:@"准备主键语句失败: %s", sqlite3_errmsg(db)];
            ok = NO;
        } else {
            sqlite3_bind_int64(st, 1, nextPK);
            if (sqlite3_step(st) != SQLITE_DONE) {
                failure = [NSString stringWithFormat:@"更新主键失败: %s", sqlite3_errmsg(db)];
                ok = NO;
            }
            sqlite3_finalize(st);
            st = NULL;
        }
    }

    if (ok) {
        if (sqlite3_exec(db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) {
            failure = [NSString stringWithFormat:@"提交事务失败: %s", sqlite3_errmsg(db)];
            ok = NO;
        }
    }

    if (ok) {
        NSLog(@"[fch] 已写入通话记录 Z_PK=%lld 号码=%@ 名字=%@ 呼出=%d 接通=%d 时长=%.0f",
              nextPK, address, name.length ? name : @"(无)", originated, answered, duration);
        sqlite3_close(db);
        return nil;
    }

    sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
    if (st) sqlite3_finalize(st);
    sqlite3_close(db);
    NSLog(@"[fch] 写入失败: %@", failure);
    return failure ?: @"未知错误";
}

NSString *FCLDumpRecentRecords(void) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(FCLDBPath().UTF8String, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        NSString *msg = [NSString stringWithFormat:@"打开数据库失败: %s", db ? sqlite3_errmsg(db) : "?"];
        if (db) sqlite3_close(db);
        return msg;
    }
    NSMutableString *out = [NSMutableString string];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, "SELECT Z_PK, ZDATE, ZADDRESS, ZNAME, ZORIGINATED, ZANSWERED, ZDURATION"
                                " FROM ZCALLRECORD ORDER BY Z_PK DESC LIMIT 8", -1, &st, NULL) == SQLITE_OK) {
        while (sqlite3_step(st) == SQLITE_ROW) {
            [out appendFormat:@"%lld | %s | %s | %s | 呼出=%d 接通=%d 时长=%.0f\n",
                              sqlite3_column_int64(st, 0),
                              (const char *)sqlite3_column_text(st, 1) ?: "",
                              (const char *)sqlite3_column_text(st, 2) ?: "",
                              (const char *)sqlite3_column_text(st, 3) ?: "(null)",
                              sqlite3_column_int(st, 4),
                              sqlite3_column_int(st, 5),
                              sqlite3_column_double(st, 6)];
        }
        sqlite3_finalize(st);
    }
    sqlite3_close(db);
    return out;
}
