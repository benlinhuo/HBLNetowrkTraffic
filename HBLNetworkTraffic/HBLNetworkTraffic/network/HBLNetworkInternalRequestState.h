//
//  HBLNetworkInternalRequestState.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HBLNetworkInternalRequestState : NSObject

@property (nonatomic, copy) NSURLRequest *request;
@property (nonatomic, strong) NSMutableData *dataAccumulator;

@end
