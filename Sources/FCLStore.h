#import <Foundation/Foundation.h>

/*
 * 把一条通话记录写进系统通话记录库。
 * 成功返回 nil，失败返回原因。
 */
NSString *FCLInsertCallRecord(NSString *address, NSString *name, NSDate *date,
                              BOOL originated, BOOL answered, double duration);

/* 只读检查：最新几条记录，调试用。 */
NSString *FCLDumpRecentRecords(void);
