//
//  HBLNetworkObserver+NSURLConnectionHelpers.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkObserver.h"

@interface HBLNetworkObserver (NSURLConnectionHelpers)

- (void)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response delegate:(id <NSURLConnectionDelegate>)delegate;
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response delegate:(id <NSURLConnectionDelegate>)delegate;

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data delegate:(id <NSURLConnectionDelegate>)delegate;

- (void)connectionDidFinishLoading:(NSURLConnection *)connection delegate:(id <NSURLConnectionDelegate>)delegate;
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error delegate:(id <NSURLConnectionDelegate>)delegate;

- (void)connectionWillCancel:(NSURLConnection *)connection;

@end
