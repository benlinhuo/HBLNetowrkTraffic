//
//  HBLNetworkObserver.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HBLNetworkInternalRequestState;

@interface HBLNetworkObserver : NSObject

@property (nonatomic, strong) NSMutableDictionary *requestStatesForRequestIDs;

+ (void)setEnabled:(BOOL)enabled;

+ (instancetype)shared;

- (HBLNetworkInternalRequestState *)requestStateForRequestID:(NSString *)requestID;

- (void)removeRequestStateForRequestID:(NSString *)requestID;

- (void)performBlock:(dispatch_block_t)block;

@end
