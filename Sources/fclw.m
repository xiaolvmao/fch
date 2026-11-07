/*
 * 开发用命令行工具（不进安装包）。
 *
 *   fclw --add <号码> [名字] [秒数] [originated:0|1] [answered:0|1]
 *   fclw --probe          查看能否读写通话记录库
 *   fclw --dump           打印最新几条记录
 *   fclw --copydb <目标>   复制一份库出来做试验
 *
 * 设置 FCL_DB_PATH 可以让它指向数据库副本，不碰真实记录。
 */
#import <Foundation/Foundation.h>
#import <sqlite3.h>

#include "pkgid.h"
#import "FCLStore.h"

static NSString *const kDBPath = @"/var/mobile/Library/CallHistoryDB/CallHistory.storedata";

static NSString *FCLDBPath(void) {
    const char *env = getenv("FCL_DB_PATH");
    if (env && *env) return [NSString stringWithUTF8String:env];
    return kDBPath;
}

static void Probe(void) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(FCLDBPath().UTF8String, &db, SQLITE_OPEN_READWRITE, NULL);
    printf("打开读写: rc=%d %s\n", rc, rc == SQLITE_OK ? "ok" : (db ? sqlite3_errmsg(db) : "?"));
    if (rc == SQLITE_OK) {
        sqlite3_busy_timeout(db, 3000);
        if (sqlite3_exec(db, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK) {
            printf("写事务: ok\n");
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        } else {
            printf("写事务失败: %s\n", sqlite3_errmsg(db));
        }
    }
    if (db) sqlite3_close(db);
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:FCLDBPath() error:NULL];
    printf("属主 %s:%s 权限 %o\n",
           [attrs[NSFileOwnerAccountName] UTF8String] ?: "?",
           [attrs[NSFileGroupOwnerAccountName] UTF8String] ?: "?",
           [attrs[NSFilePosixPermissions] unsignedIntValue]);
}

static int CopyDB(NSString *dest) {
    for (NSString *suffix in @[@"", @"-wal", @"-shm"]) {
        NSData *data = [NSData dataWithContentsOfFile:[kDBPath stringByAppendingString:suffix]];
        if (!data) { printf("%s: 无此文件\n", suffix.UTF8String); continue; }
        if (![data writeToFile:[dest stringByAppendingString:suffix] atomically:YES]) {
            printf("%s: 写入失败\n", suffix.UTF8String);
            return 1;
        }
        printf("%s: %lu 字节\n", suffix.UTF8String, (unsigned long)data.length);
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            printf("用法: fclw --add <号码> [名字] [秒数] [originated] [answered] | --probe | --dump | --copydb <目标>\n");
            return 2;
        }
        if (strcmp(argv[1], "--probe") == 0) { Probe(); return 0; }
        if (strcmp(argv[1], "--dump") == 0) { printf("%s", FCLDumpRecentRecords().UTF8String); return 0; }
        if (argc >= 3 && strcmp(argv[1], "--copydb") == 0) {
            return CopyDB([NSString stringWithUTF8String:argv[2]]);
        }
        if (argc >= 3 && strcmp(argv[1], "--add") == 0) {
            NSString *address = [NSString stringWithUTF8String:argv[2]];
            NSString *name = argc >= 4 ? [NSString stringWithUTF8String:argv[3]] : nil;
            double duration = argc >= 5 ? atof(argv[4]) : 30;
            BOOL originated = argc >= 6 ? atoi(argv[5]) != 0 : YES;
            BOOL answered = argc >= 7 ? atoi(argv[6]) != 0 : YES;
            NSString *failure = FCLInsertCallRecord(address, name, [NSDate date], originated, answered, duration);
            if (failure) { printf("失败: %s\n", failure.UTF8String); return 1; }
            printf("成功\n");
            return 0;
        }
        printf("未知参数\n");
        return 2;
    }
}
