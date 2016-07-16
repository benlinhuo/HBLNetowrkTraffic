//
//  HBLNetworkRecorder.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

static NSString *const kHBLNetworkRecorderTransactionCreatedNotification = @"kHBLNetworkRecorderTransactionCreatedNotification";
static NSString *const kHBLNetworkRecorderTransactionUpdatedNotification = @"kHBLNetworkRecorderTransactionUpdatedNotification";
static NSString *const kHBLNetworkRecorderUserInfoTransactionKey = @"kHBLNetworkRecorderUserInfoTransactionKey";

@class HBLNetworkTransaction;

@interface HBLNetworkRecorder : NSObject

+ (instancetype)shared;

- (HBLNetworkTransaction *)beforeAsyncExecCreateTransactionWithRequestID:(NSString *)requestID;

- (void)recordRequestWillBeSentWithRequestID:(NSString *)requestID request:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;

- (void)recordDidReceivedResponseWithRequestID:(NSString *)requestID response:(NSURLResponse *)response;

- (void)recordDidReceivedDataWithRequestID:(NSString *)requestID dataLength:(int64_t)dataLength;

- (void)recordDidFinishedLoadingWithRequestID:(NSString *)requestID responseBody:(NSData *)responseBody endTime:(NSDate *)endTime;

- (void)recordDidFailedLoadingWithRequestID:(NSString *)requestID HBLErrorCode:(NSString *)code error:(NSError *)error;

- (void)recordMechanism:(NSString *)mechanism forRequestID:(NSString *)requestID;

- (void)postTransactionCreatedNotificationWithTransaction:(HBLNetworkTransaction *)transaction;

- (void)postTransactionUpdatedNotificationWithTransaction:(HBLNetworkTransaction *)transaction;

@end
