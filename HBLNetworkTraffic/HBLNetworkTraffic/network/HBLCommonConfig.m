//
//  HBLCommonConfig.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/15.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLCommonConfig.h"
#import "BIFUUID.h"
#import <UIKit/UIKit.h>

@interface HBLCommonConfig ()

@property (nonatomic, strong) NSString *appVerSion;

@end

@implementation HBLCommonConfig

- (NSString *)uuid
{
    return [BIFUUID shared].uuid;
}

- (NSString *)appVerSion
{
    if (!_appVerSion) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Info"
                                                         ofType:@"plist"];
        
        NSDictionary *dic = [[NSDictionary alloc] initWithContentsOfFile:path];
        
        _appVerSion = dic[@"CFBundleShortVersionString"];
    }
    
    return _appVerSion;
}

- (NSString *)osv
{
    return [UIDevice currentDevice].systemVersion;
}

@end
