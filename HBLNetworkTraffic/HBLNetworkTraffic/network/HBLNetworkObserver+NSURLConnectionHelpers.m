//
//  HBLNetworkObserver+NSURLConnectionHelpers.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkObserver+NSURLConnectionHelpers.h"
#import "HBLNetworkUtility.h"
#import "HBLNetworkRecorder.h"
#import "HBLNetworkInternalRequestState.h"

@implementation HBLNetworkObserver(NSURLConnectionHelpers)

- (void)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response delegate:(id <NSURLConnectionDelegate>)delegate
{
    NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:connection];
    [[HBLNetworkRecorder shared] beforeAsyncExecCreateTransactionWithRequestID:requestID];
    
    [self performBlock:^{
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        requestState.request = request;
        
        [[HBLNetworkRecorder shared] recordRequestWillBeSentWithRequestID:requestID request:request redirectResponse:response];
        
        NSString *mechanism = [NSString stringWithFormat:@"NSURLConnection (delegate: %@)", [delegate class]];
        [[HBLNetworkRecorder shared] recordMechanism:mechanism forRequestID:requestID];
    }];
    
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response delegate:(id <NSURLConnectionDelegate>)delegate
{
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:connection];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        NSMutableData *data = nil;
        if (response.expectedContentLength > 0) {
            data = [[NSMutableData alloc] initWithCapacity:(NSUInteger)response.expectedContentLength];
        } else {
            data = [NSMutableData data];
        }
        requestState.dataAccumulator = data;
        
        [[HBLNetworkRecorder shared] recordDidReceivedResponseWithRequestID:requestID response:response];
    }];
    
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data delegate:(id <NSURLConnectionDelegate>)delegate
{
    data = [data copy];
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:connection];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        [requestState.dataAccumulator appendData:data];
        
        [[HBLNetworkRecorder shared] recordDidReceivedDataWithRequestID:requestID dataLength:data.length];
    }];
    
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection delegate:(id <NSURLConnectionDelegate>)delegate
{
    NSDate *endTime = [NSDate date];
    
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:connection];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        
        [[HBLNetworkRecorder shared] recordDidFinishedLoadingWithRequestID:requestID responseBody:requestState.dataAccumulator endTime:endTime];
        [self removeRequestStateForRequestID:requestID];
    }];
    
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error delegate:(id <NSURLConnectionDelegate>)delegate
{
    [self performBlock:^{
        NSString *requestID = [HBLNetworkUtility requestIDforConnectionOrTask:connection];
        
        HBLNetworkInternalRequestState *requestState = [self requestStateForRequestID:requestID];
        if (requestState.request) {
            NSString *errorCode = [HBLNetworkUtility getErrorCodeFromData:requestState.dataAccumulator];
            [[HBLNetworkRecorder shared] recordDidFailedLoadingWithRequestID:requestID HBLErrorCode:errorCode error:error];
        }
        
        
        [self removeRequestStateForRequestID:requestID];
    }];
    
}

- (void)connectionWillCancel:(NSURLConnection *)connection
{
    [self performBlock:^{
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"cancelled"};
        
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];
        [self connection:connection didFailWithError:error delegate:nil];
    }];
    
    
    
}


@end
