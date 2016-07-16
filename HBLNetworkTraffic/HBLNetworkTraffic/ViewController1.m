//
//  ViewController1.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/16.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "ViewController1.h"
#import "HBLNetworkTrafficManager.h"

@interface ViewController1 ()

@end

@implementation ViewController1

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ViewController1";
    self.view.backgroundColor = [UIColor whiteColor];
    
    [HBLNetworkTrafficManager shared].pageName = @"ViewController1";
    [self sendApi];
    
}

- (void)sendApi
{
    NSString *urlString = @"http://m.angejia.com/sh";
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSOperationQueue *queue = [NSOperationQueue mainQueue];
    
    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        NSLog(@"线程：%@ 数据内容：%lu", [NSThread currentThread], data.length);
        
        
    }];
}



@end
