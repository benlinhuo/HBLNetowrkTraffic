//
//  BIFUUIDGenerator.m
//  BIFCore
//
//  Created by wysasun on 14/12/3.
//  Copyright (c) 2014年 Plan B Inc. All rights reserved.
//

#import "BIFUUID.h"
#import "BIFKeychain.h"
#import <UIKit/UIKit.h>

//serviceName 的前缀com.xxx需要和bundleId一致
static NSString *serviceName = @"com.angejiaApps";
static NSString *uuidName = @"angejiaAppsUUID";
static NSString *pasteboardType = @"angejiaAppsContent";

typedef NS_ENUM (NSUInteger, RTGroupUUIDType){
    RTGroupUUIDTypeAnjuke,
    RTGroupUUIDTypeBroker
};

@interface BIFUUID ()

@property (nonatomic, strong) BIFKeychain *myKeyChain;
@property (nonatomic, copy, readwrite) NSString *uuid;

@end

@implementation BIFUUID

- (void)saveUUID:(NSString *)uuid
{
    BOOL saveOk = NO;
    NSData *uuidData = [self.myKeyChain find:uuidName];
    if (uuidData == nil) {
        saveOk = [self.myKeyChain insert:uuidName data:[self changeStringToData:uuid]];
    }else{
        saveOk = [self.myKeyChain update:uuidName data:[self changeStringToData:uuid]];
    }
    if (!saveOk) {
        [self createPasteBoradValue:uuid forIdentifier:uuidName];
    }
}

- (NSString *)uuid
{
    if (!_uuid) {
        _uuid = [[self getUUID] copy];
    }
    return _uuid;
}

#pragma mark -- privite method

- (BIFKeychain *)myKeyChain
{
    if (!_myKeyChain) {
        _myKeyChain = [[BIFKeychain alloc] initWithService:serviceName withGroup:[NSString stringWithFormat:@"%@.%@", [BIFKeychain bundleSeedID], @"com.angejia.*"]];
    }
    return _myKeyChain;
}

- (NSData *)changeStringToData:(NSString *)str
{
    return [str dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)getUUID
{
    NSData *uuidData = [self.myKeyChain find:uuidName];
    NSString *uuid = nil;
    if (uuidData != nil) {
        NSString *temp = [[NSString alloc] initWithData:uuidData encoding:NSUTF8StringEncoding];
        uuid = [NSString stringWithFormat:@"%@", temp];
    }
    if (uuid.length == 0) {
        uuid = [self readPasteBoradforIdentifier:uuidName];
    }
    
    if (uuid.length == 0) {
        uuid = [self generateUUID];
        [self saveUUID:uuid];
    }
    return uuid;
}

- (NSString *)timeString
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyyMMddHHmm"];
    NSString *date = [formatter stringFromDate:[NSDate date]];
    //    date = @"2014102610:41 p.m.";
    if ([date hasSuffix:@".m."]) {
        if ([date hasSuffix:@"a.m."]) {//上午
            NSRange r = [date rangeOfString:@":"];
            NSString *yyyyMMddHH = [date substringToIndex:r.location];
            NSString *mm = [date substringWithRange:NSMakeRange(r.location + 1, 2)];
            date = [yyyyMMddHH stringByAppendingString:mm];
        } else {//下午
            NSRange r = [date rangeOfString:@":"];
            NSString *yyyyMMdd = [date substringToIndex:r.location - 2];
            NSString *HH = [date substringWithRange:NSMakeRange(r.location - 2, 2)];
            NSString *mm = [date substringWithRange:NSMakeRange(r.location + 1, 2)];
            HH = [@([HH integerValue] + 12) stringValue];
            date = [NSString stringWithFormat:@"%@%@%@", yyyyMMdd, HH, mm];
        }
    }
    return date;
}

- (NSString *)generateUUID
{
    NSString *key = @"BIFUUID";
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    //    uuid = @"986CD03B-7BCB-427E-B116-2014102610:41 a.m.";
    if ((uuid.length == 0) || ([uuid hasSuffix:@".m."])) {
        [[NSUserDefaults standardUserDefaults] setObject:[self createUUID] forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return [[NSUserDefaults standardUserDefaults] objectForKey:key];
    } else {
        return uuid;
    }
}

/**
 *  创建uuid
 *
 *  @return 创建的uuid，以时间替换最后一个下划线后面的字段
 */
- (NSString *)createUUID
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    NSString *uuidWithDate = (__bridge NSString *)string;
    
    uuidWithDate = [[uuidWithDate substringToIndex:24] stringByAppendingString:[self timeString]];
    return uuidWithDate;
}

/**
 *  keychain保存失败的备用操作，保存到剪切板
 *
 *  @param value      需要保存的数据
 *  @param identifier 索引
 */
- (void)createPasteBoradValue:(NSString *)value forIdentifier:(NSString *)identifier
{
    UIPasteboard *pb = [UIPasteboard pasteboardWithName:serviceName create:YES];
    NSDictionary *dict = [NSDictionary dictionaryWithObject:value forKey:identifier];
    NSData *dictData = [NSKeyedArchiver archivedDataWithRootObject:dict];
    [pb setData:dictData forPasteboardType:pasteboardType];
}

- (NSString *)readPasteBoradforIdentifier:(NSString *)identifier
{
    UIPasteboard *pb = [UIPasteboard pasteboardWithName:serviceName create:YES];
    NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithData:[pb dataForPasteboardType:pasteboardType]];
    return [dict objectForKey:identifier];
}

@end
