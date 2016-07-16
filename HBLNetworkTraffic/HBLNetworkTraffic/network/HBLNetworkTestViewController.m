//
//  HBLNetworkTestViewController.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkTestViewController.h"
#import "HBLNetworkTrafficManager.h"
#import "ViewController.h"
#import "ViewController1.h"
#import "ViewController2.h"

@interface HBLNetworkTestViewController ()<NSURLSessionDownloadDelegate>

@end

@implementation HBLNetworkTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [HBLNetworkTrafficManager shared].pageName = @"HBLNetworkTestViewController";
    
}

- (IBAction)sendAsynchronousRequest:(id)sender
{
    UIViewController *vc = [[ViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
    
    
    
    NSString *urlString = @"http://m.angejia.com/sh";
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSOperationQueue *queue = [NSOperationQueue mainQueue];
    
    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        NSLog(@"线程：%@ 数据内容：%lu", [NSThread currentThread], data.length);
        
        
    }];
}


- (IBAction)sendSynchronousRequest:(id)sender
{
    UIViewController *vc = [[ViewController1 alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
    
    
    
    
    NSString *urlString = @"http://m.angejia.com/sale/sh/?from=Hp_Button";
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    NSLog(@"内容：%lu\n", data.length);
    NSLog(@"错误：%@\n", error);
}

- (IBAction)dataTaskWithRequestWithCompletionHandler:(id)sender
{
    UIViewController *vc = [[ViewController2 alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
    
    
    
    
    NSString *urlString = @"http://m.angejia.com/broker/bj/?from=Hp_Button";
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSLog(@"dataTaskWithRequest:completionHandler: 内容：%lu\n",data.length);
        
    }];
    
    [dataTask resume];
}

- (IBAction)uploadTaskWithRequestfromData:(id)sender
{
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://jsonplaceholder.typicode.com/posts"]];
    
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];//这一行一定不能少，因为后面是转换成JSON发送的
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPMethod:@"POST"];
    [request setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    [request setTimeoutInterval:20];
    NSDictionary * dataToUploaddic = @{@"text":@"test data"};
    NSData * data = [NSJSONSerialization dataWithJSONObject:dataToUploaddic
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:nil];
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionUploadTask * uploadtask = [session uploadTaskWithRequest:request fromData:data completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"error = %@, data.length = %ld", error, data.length);
        
    }];
    [uploadtask resume];
    
}

- (IBAction)downloadTaskWithRequest:(id)sender
{
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
    
    // 下载该图片的流量可以查看浏览器->Network->字段 Content-Length
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://img.agjimg.com/FoJ_7ZkXoZ1BGPWql5FrDMCtEQlb"]];
    
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:request];
    
    [downloadTask resume];
}


#pragma mark - NSURLSessionDownloadDelegate
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    NSLog(@"过程中：");
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSLog(@"图片下载结束");
}


@end
