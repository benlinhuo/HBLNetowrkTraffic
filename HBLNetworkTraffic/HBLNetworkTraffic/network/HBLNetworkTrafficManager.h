//
//  HBLNetworkTrafficManager.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/15.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HBLNetworkTrafficManager : NSObject

@property (nonatomic, strong) NSString *pageName;

+ (HBLNetworkTrafficManager *)shared;

- (void)configWithURL:(NSString *)url maxNumByOnce:(NSUInteger)maxNum;

@end
