//
//  HBLNetworkRecorder.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkRecorder.h"
#import "HBLNetworkTransaction.h"
#import "HBLNetworkUtility.h"



@interface HBLNetworkRecorder ()

@property (nonatomic, strong) NSMutableArray *testArray;
@property (nonatomic, strong) NSMutableDictionary *transactionsForRequestID; // 以 requestID 为 key 的多条记录
@property (nonatomic, strong) dispatch_queue_t queue;

@end

@implementation HBLNetworkRecorder

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.testArray = [NSMutableArray array];
        self.transactionsForRequestID = [NSMutableDictionary dictionary];
        // 串行队列
        self.queue = dispatch_queue_create("com.angejia.HBLNetworkRecorder", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (instancetype)shared
{
    static HBLNetworkRecorder *recorder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        recorder = [[[self class] alloc] init];
    });
    return recorder;
}

// 防止数据过多。所以用完便释放
- (void)deleteTransactionForRequestID:(NSString *)requestID
{
    
    HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
    
    //测试代码
    [self printResult:transaction];
    
    if (transaction) {
        [self.transactionsForRequestID removeObjectForKey:requestID];
    }
}

#pragma mark - network need

// 在执行异步之前创建 transaction ，发送通知，方便外部可以正确获取 startTime、pageID 等数据
- (HBLNetworkTransaction *)beforeAsyncExecCreateTransactionWithRequestID:(NSString *)requestID
{
    HBLNetworkTransaction *transaction = [HBLNetworkTransaction new];
    [self.transactionsForRequestID setObject:transaction forKey:requestID];
    [self postTransactionCreatedNotificationWithTransaction:transaction];
    return transaction;
}

- (void)recordRequestWillBeSentWithRequestID:(NSString *)requestID request:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    if (redirectResponse) {
        [self recordDidReceivedResponseWithRequestID:requestID response:redirectResponse];
        
        NSDate *endTime = [NSDate date];
        [self recordDidFinishedLoadingWithRequestID:requestID responseBody:nil endTime:endTime];
    }
    
    dispatch_async(self.queue, ^{
        int64_t length = 0;
        NSDictionary *headers = request.allHTTPHeaderFields;
        if (headers) {
            NSData *headerData = [NSPropertyListSerialization dataWithPropertyList:headers
                                                                            format:NSPropertyListBinaryFormat_v1_0
                                                                           options:0
                                                                             error:NULL
                                  ];
            
            length += headerData.length;
        }
        NSData *httpBody = request.HTTPBody;
        if (httpBody) {
            length += httpBody.length;
        }
        
        HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
        if (transaction) {
            transaction.requestID = requestID;
            transaction.request = request;
            transaction.sendDataLength = length;
            transaction.networkStatus = [HBLNetworkUtility getNetworkStatus];
            transaction.ip = [HBLNetworkUtility getIp];
            
            //[self postTransactionUpdatedNotificationWithTransaction:transaction];
        }
    });
}

- (void)recordDidReceivedResponseWithRequestID:(NSString *)requestID response:(NSHTTPURLResponse *)response
{
    NSDate *reponseTime = [NSDate date];
    
    dispatch_async(self.queue, ^{
        HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
        if (transaction) {
            transaction.response = response;
            transaction.transactionState = HBLNetworkTransactionStateReceivingData;
            transaction.latency = -[reponseTime timeIntervalSinceDate:transaction.startTime];
            
            //[self postTransactionUpdatedNotificationWithTransaction:transaction];
        }
    });
    
}

- (void)recordDidReceivedDataWithRequestID:(NSString *)requestID dataLength:(int64_t)dataLength
{
    dispatch_async(self.queue, ^{
        HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
        if (transaction) {
            transaction.receivedDataLength += dataLength;
            //[self postTransactionUpdatedNotificationWithTransaction:transaction];
        }
    });
    
}

- (void)recordDidFinishedLoadingWithRequestID:(NSString *)requestID responseBody:(NSData *)responseBody endTime:(NSDate *)endTime
{
    
    dispatch_async(self.queue, ^{
        HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
        if (transaction) {
            transaction.transactionState = HBLNetworkTransactionStateFinished;
            transaction.duration = [endTime timeIntervalSinceDate:transaction.startTime];
            transaction.endTime = endTime;
            NSString *errorCode = [HBLNetworkUtility getErrorCodeFromData:responseBody];
            transaction.errorCode = errorCode;
            
            [self postTransactionUpdatedNotificationWithTransaction:transaction];
            
            [self deleteTransactionForRequestID:requestID];
        }
    });
    
}

- (void)recordDidFailedLoadingWithRequestID:(NSString *)requestID HBLErrorCode:(NSString *)code error:(NSError *)error
{
    NSDate *endTime = [NSDate date];
    
    dispatch_async(self.queue, ^{
        HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
        if (transaction) {
            transaction.transactionState = HBLNetworkTransactionStateFailed;
            transaction.duration = -[transaction.startTime timeIntervalSinceNow];
            transaction.endTime = endTime;
            transaction.error = error;
            transaction.errorCode = code;
            
            [self postTransactionUpdatedNotificationWithTransaction:transaction];
            
            [self deleteTransactionForRequestID:requestID];
        }
    });
    
}

// 将那个类调用的哪个方法也告诉给后端
- (void)recordMechanism:(NSString *)mechanism forRequestID:(NSString *)requestID
{
    dispatch_async(self.queue, ^{
        HBLNetworkTransaction *transaction = self.transactionsForRequestID[requestID];
        if (transaction) {
            transaction.requestMechanism = mechanism;
        }
    });
    
}

#pragma notification

// 通知一般都是在主线程中
- (void)postTransactionCreatedNotificationWithTransaction:(HBLNetworkTransaction *)transaction
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *userInfo = @{ kHBLNetworkRecorderUserInfoTransactionKey: transaction};
        [[NSNotificationCenter defaultCenter] postNotificationName:kHBLNetworkRecorderTransactionCreatedNotification object:self userInfo:userInfo];
    });
    
}

- (void)postTransactionUpdatedNotificationWithTransaction:(HBLNetworkTransaction *)transaction
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *userInfo = @{ kHBLNetworkRecorderUserInfoTransactionKey: transaction};
        [[NSNotificationCenter defaultCenter] postNotificationName:kHBLNetworkRecorderTransactionUpdatedNotification object:self userInfo:userInfo];
    });
    
}

- (void)printResult:(HBLNetworkTransaction *)transaction
{
    NSLog(@"resultID=%@, url=%@, method=%@, sendNum=%lld, receiveNum=%lld, startTime=%@, endTime=%@, networkStatus=%@, error=%@, mechanism=%@, errorCode=%@", transaction.requestID, transaction.request.URL, transaction.request.HTTPMethod, transaction.sendDataLength, transaction.receivedDataLength, transaction.startTime, transaction.endTime, transaction.networkStatus, transaction.error, transaction.requestMechanism, transaction.errorCode);
}

@end

