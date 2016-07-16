//
//  HBLNetworkTrafficManager.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/15.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkTrafficManager.h"
#import "HBLNetworkObserver.h"
#import "HBLNetworkDataUpload.h"

// 默认最大发送条数
static const NSUInteger maxSendNum = 20;

@implementation HBLNetworkTrafficManager

/**
 * @param  NSString      url       将数据回传到服务器的地址
 * @param  NSUInteger    maxNum    数据回传服务器时最大发送条数
 *
 */

+ (HBLNetworkTrafficManager *)shared
{
    static dispatch_once_t onceToken;
    static HBLNetworkTrafficManager *manager = nil;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (void)configWithURL:(NSString *)url maxNumByOnce:(NSUInteger)maxNum
{
    [HBLNetworkDataUpload shared].url = url;
    if (maxNum <= 0) {
        [HBLNetworkDataUpload shared].maxSendNum = maxSendNum;
    } else {
        [HBLNetworkDataUpload shared].maxSendNum = maxNum;
    }
    
    [HBLNetworkObserver setEnabled:YES];
}

- (void)setPageName:(NSString *)pageName
{
    [HBLNetworkDataUpload shared].pageName = pageName;
}

@end
