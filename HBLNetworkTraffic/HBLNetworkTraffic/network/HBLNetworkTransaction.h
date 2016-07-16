//
//  HBLNetworkTransaction.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, HBLNetworkTransactionState) {
    HBLNetworkTransactionStateUnstarted,
    HBLNetworkTransactionStateAwaitingResponse,
    HBLNetworkTransactionStateReceivingData,
    HBLNetworkTransactionStateFinished,
    HBLNetworkTransactionStateFailed,
};

@interface HBLNetworkTransaction : NSObject

@property (nonatomic, strong) NSString *requestID;

@property (nonatomic, strong) NSURLRequest *request;

@property (nonatomic, strong) NSHTTPURLResponse *response;

@property (nonatomic, strong) NSDate *startTime;

@property (nonatomic, strong) NSDate *endTime;

@property (nonatomic, strong) NSString *pageName;

@property (nonatomic, assign) int64_t sendDataLength;

@property (nonatomic, assign) int64_t receivedDataLength;

@property (nonatomic, strong) NSString *networkStatus; // 网络状态 3G 等

@property (nonatomic, strong) NSString *ip;



@property (nonatomic, strong) NSString *errorCode; // 安个家的特殊业务：result:{"code":2001,"msg":"\u5e93\u5b58\u4e0d\u5b58\u5728"}

@property (nonatomic, assign) HBLNetworkTransactionState transactionState;

@property (nonatomic, assign) NSTimeInterval latency; // send 到 didReceiveData 的时间间隔

@property (nonatomic, assign) NSTimeInterval duration; // send 到 didFinished 的时间间隔

@property (nonatomic, strong) NSString *requestMechanism; // 哪个类调用的哪个方法

@property (nonatomic, strong) NSError *error;

@end

