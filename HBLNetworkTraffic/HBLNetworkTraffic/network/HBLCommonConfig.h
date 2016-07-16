//
//  HBLCommonConfig.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/15.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "BIFSingleton.h"

@interface HBLCommonConfig : BIFSingleton

/**
 *  设备唯一识别码
 */
@property (nonatomic, readonly) NSString *uuid;

/**
 *  app version，app 版本号
 */
@property (nonatomic, readonly) NSString *appVerSion;

/**
 *  操作系统版本
 */
@property (nonatomic, readonly) NSString *osv;

@end
