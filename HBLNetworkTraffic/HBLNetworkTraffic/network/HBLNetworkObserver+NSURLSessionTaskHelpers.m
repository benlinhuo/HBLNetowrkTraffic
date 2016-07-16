//
//  HBLNetworkObserver+NSURLSessionTaskHelpers.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkObserver+NSURLSessionTaskHelpers.h"
#import "HBLNetworkUtility.h"
#import "HBLNetworkRecorder.h"
#import "HBLNetworkInternalRequestState.h"

@implementation HBLNetworkObserver (NSURLSessionTaskHelpers)

// 某个请求重定向，会重新发送一个新的 API 请求。我们会当成两条流量记录
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler delegate:(id <NSURLSessionDelegate>)delegate
{
    NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:task];
    [[HBLNetworkRecorder shared] beforeAsyncExecCreateTransactionWithRequestID:requestID];
    
    [self performBlock:^{
        
        [[HBLNetworkRecorder shared] recordRequestWillBeSentWithRequestID:requestID request:request redirectResponse:response];
    }];
    
}

- (void)URLSessionTaskWillResume:(NSURLSessionTask *)task
{
    NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:task];
    [[HBLNetworkRecorder shared] beforeAsyncExecCreateTransactionWithRequestID:requestID];
    
    [self performBlock:^{
        // resume 在同一个 task 中可能会被多次调用，只考虑第一次
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        if (!requestState.request) {
            requestState.request = task.currentRequest;
            
            [[HBLNetworkRecorder shared] recordRequestWillBeSentWithRequestID:requestID request:task.currentRequest redirectResponse:nil];
        }
    }];
    
}

#pragma mark - dataTask
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler delegate:(id <NSURLSessionDelegate>)delegate
{
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:dataTask];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        if (response.expectedContentLength > 0) {
            requestState.dataAccumulator = [[NSMutableData alloc] initWithCapacity:(NSUInteger)response.expectedContentLength];
        } else {
            requestState.dataAccumulator = [NSMutableData data];
        }
        
        NSString *mechanism = [NSString stringWithFormat:@"NSURLSessionDataTask (delegate: %@)", [delegate class]];
        
        [[HBLNetworkRecorder shared] recordMechanism:mechanism forRequestID:requestID];
        
        [[HBLNetworkRecorder shared] recordDidReceivedResponseWithRequestID:requestID response:response];
    }];
    
    
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data delegate:(id <NSURLSessionDelegate>)delegate
{
    data = [data copy];
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:dataTask];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        [requestState.dataAccumulator appendData:data];
        
        [[HBLNetworkRecorder shared] recordDidReceivedDataWithRequestID:requestID dataLength:data.length];
    }];
    
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error delegate:(id <NSURLSessionDelegate>)delegate
{
    NSDate *endTime = [NSDate date];
    
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:task];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        if (error) {
            NSString *errorCode = [HBLNetworkUtility getErrorCodeFromData:requestState.dataAccumulator];
            
            [[HBLNetworkRecorder shared] recordDidFailedLoadingWithRequestID:requestID HBLErrorCode:errorCode error:error];
        } else {
            [[HBLNetworkRecorder shared] recordDidFinishedLoadingWithRequestID:requestID responseBody:requestState.dataAccumulator endTime:endTime];
        }
        [self removeRequestStateForRequestID:requestID];
    }];
    
}

#pragma mark - downloadTask

// dataTask 转 downloadTask
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask delegate:(id <NSURLSessionDelegate>)delegate
{
    [self performBlock:^{
        // 后台下载任务，用于标记以便之后获取到该 task
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:dataTask];
        [HBLNetworkUtility setRequestID:requestID forConnectionTask:dataTask];
    }];
    
}

// 我们没有考虑 cancelByProductingResumeData（中断下载）的情况，因为我们 dataLength 是已下载内容的长度相加
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite delegate:(id <NSURLSessionDelegate>)delegate
{
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:downloadTask];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        if (!requestState.dataAccumulator) {
            NSUInteger totalExpectedToWrite = ((NSUInteger)totalBytesExpectedToWrite > 0) ? (NSUInteger)totalBytesExpectedToWrite : 0;
            requestState.dataAccumulator = [[NSMutableData alloc] initWithCapacity:totalExpectedToWrite];
            
            [[HBLNetworkRecorder shared] recordDidReceivedResponseWithRequestID:requestID response:downloadTask.response];
            
            NSString *mechanism = [NSString stringWithFormat:@"NSURLSessionDownloadTask (delegate: %@)", [delegate class]];
            [[HBLNetworkRecorder shared] recordMechanism:mechanism forRequestID:requestID];
            
        }
        // 数据长度有了，但是数据内容，在 didFinishDownloadingToURL: 方法中传过来了，在那个时候更新数据
        [[HBLNetworkRecorder shared] recordDidReceivedDataWithRequestID:requestID dataLength:bytesWritten];
    }];
    
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location data:(NSData *)data delegate:(id <NSURLSessionDelegate>)delegate
{
    data = [data copy];
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:downloadTask];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        [requestState.dataAccumulator appendData:data];
    }];
    
}


@end
