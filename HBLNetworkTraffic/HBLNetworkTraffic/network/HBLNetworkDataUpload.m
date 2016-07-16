//
//  HBLNetworkDataUpload.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/15.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkDataUpload.h"
#import "HBLNetworkRecorder.h"
#import "AppDelegate.h"
#import "HBLNetworkTransaction.h"
#import "HBLCommonConfig.h"
#import "HBLNetworkUtility.h"


#define SetSafeStringNil(value) \
((value == nil) ? (@"") : ([NSString stringWithFormat:@"%@",value]))

static NSString const *networkDataUploadFile = @"network.dataupload";

@interface HBLNetworkDataUpload ()

@property (nonatomic, strong) NSMutableArray *hasTransactions; // 单个元素就是一个 NSDictionary
@property (nonatomic, strong) dispatch_queue_t ioQueue; // 操作文件的，都使用串行队列

@property (nonatomic, strong) NSString *filePath;

@end

@implementation HBLNetworkDataUpload

+ (HBLNetworkDataUpload *)shared
{
    static dispatch_once_t onceToken;
    static HBLNetworkDataUpload *dataUpload = nil;
    dispatch_once(&onceToken, ^{
        dataUpload = [[self alloc] init];
        [dataUpload addNotificationObserver];
        
    });
    return dataUpload;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // 读取文件，获取已有条数
        self.ioQueue = dispatch_queue_create("com.hbl.fileOperation", DISPATCH_QUEUE_SERIAL);
        // 因为串行，所以可以保证执行顺序
        dispatch_async(_ioQueue, ^{
            self.hasTransactions = [NSMutableArray arrayWithContentsOfFile:self.filePath];
            if (!self.hasTransactions) {
                self.hasTransactions = [NSMutableArray array];
            }
        });
    }
    return self;
}

- (void)addNotificationObserver
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willSend:) name:kHBLNetworkRecorderTransactionCreatedNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSend:) name:kHBLNetworkRecorderTransactionUpdatedNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(forceSend) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
}

- (void)willSend:(NSNotification *) notification
{
    NSDictionary *userInfo = [notification userInfo];
    HBLNetworkTransaction *tranaction = userInfo[kHBLNetworkRecorderUserInfoTransactionKey];
    tranaction.startTime = [NSDate date];
    NSString *pageName = self.pageName;
    tranaction.pageName = pageName;
}

- (void)didSend:(NSNotification *)notification
{
    NSDictionary *userInfo = [notification userInfo];
    HBLNetworkTransaction *tranaction = userInfo[kHBLNetworkRecorderUserInfoTransactionKey];
    
    NSString *url = tranaction.request.URL.absoluteString;
    if ([url hasPrefix:self.url]) { // 回传数据给服务器的这个 API ，要丢弃，不然就可能在发送条数为1时变成死循环了
        return;
    }
    
    NSDictionary *dic = [self transformTransactionToDictionary:tranaction];
    [self.hasTransactions addObject:dic];
    
    NSString *status = [HBLNetworkUtility getNetworkStatus];
    
    if (self.hasTransactions.count >= (self.maxSendNum) && [status isEqualToString:@"WIFI"]) {
        // 表示到达发送的条数，可以发送了
        [self postInfoWithNetworkTransactions:self.hasTransactions];
        
        
    } else {
        // 写文件
        dispatch_async(self.ioQueue, ^{
            [self.hasTransactions writeToFile:self.filePath atomically:YES];
        });
        
    }
    
}


/**
 
 
 {"user_id":"111",
 "start_time":"1467081484",
 "end_time":"1467081486",
 "network":"1",
 "htttp_code":"200",
 "response_code":"4001",
 "send_sum":"100",
 "send_unit":"b",
 "receive_sum":"600",
 "use_cache":"0",
 "page_name":"1-000005",
 "page_token":"c4ca4238a0b923820dcc509a6f75849b",
 "url":"http://api.master.stage.angejia.com/mobile/member/configs",
 "method":"post",
 "ip" : "192.168.162.56",
 "params":"city_id=1&version_id=25517e75b67bbf5fe3ec82e61a8d1d18",
 "header":{
 "dvid":"216821D1-C706-4588-9A5A-201606171504",
 "Content-Type":"application/json",
 "app_version":"3.81",
 "app_type":"i-angejia",
 "os" : "9.3"
 }
 
 }
 
 */

- (NSDictionary *)transformTransactionToDictionary:(HBLNetworkTransaction *)transaction
{
    NSString *url = transaction.request.URL.absoluteString;
    
    NSMutableDictionary *postDictionary = [NSMutableDictionary dictionary];
    NSString *receiveDataLength = [NSString stringWithFormat:@"%lli",transaction.receivedDataLength];
    NSHTTPURLResponse *response = transaction.response;
    NSString *statusCode = [NSString stringWithFormat:@"%li",(long)response.statusCode];
    
    NSDate *startTime = transaction.startTime;
    NSTimeInterval starttimeStamp = [startTime timeIntervalSince1970];
    NSString *startTimeStampString = [NSString stringWithFormat:@"%f",starttimeStamp];
    
    NSDate *endTime = transaction.endTime;
    NSTimeInterval endtimeStamp = [endTime timeIntervalSince1970];
    NSString *endTimeStampString = [NSString stringWithFormat:@"%f",endtimeStamp];
    
    NSString *pageName = transaction.pageName;
    NSDictionary *allHTTPHeaderFields = transaction.request.allHTTPHeaderFields;
    NSString *contentType = allHTTPHeaderFields[@"content-type"];
    
    NSString *pageToken = [NSString stringWithFormat:@"%@.%@",pageName,startTime]; // 唯一表识一个页面，用于统计某个页面的流量
    
    NSString *sendLength = [NSString stringWithFormat:@"%lli",transaction.sendDataLength];
    if (contentType.length < 1) {
        contentType = allHTTPHeaderFields[@"Content-type"];
    }
    
    
    NSString *params = nil;
    
    if ([transaction.request.HTTPMethod isEqualToString:@"POST"]) {
        params = [[NSString alloc] initWithData:transaction.request.HTTPBody encoding:NSUTF8StringEncoding];
    }else{
        params = @"";
    }
    
    //set http header
    postDictionary[@"start_time"]   = startTimeStampString ;
    postDictionary[@"end_time"]     = endTimeStampString ;
    postDictionary[@"network"]      = SetSafeStringNil(transaction.networkStatus);
    postDictionary[@"htttp_code"]   = statusCode ;
    postDictionary[@"response_code"]    = transaction.errorCode;
    postDictionary[@"send_sum"]         = sendLength;
    postDictionary[@"receive_sum"]      = receiveDataLength;
    
    postDictionary[@"page_name"]    = pageName ;
    postDictionary[@"page_token"]   = pageToken ;
    postDictionary[@"url"]          = url;
    postDictionary[@"method"]       = transaction.request.HTTPMethod;
    postDictionary[@"ip"]           = SetSafeStringNil(transaction.ip);
    postDictionary[@"params"]       = params;
    
    
    NSMutableDictionary *header = [NSMutableDictionary dictionaryWithCapacity:5];
    header[@"dvid"]         = SetSafeStringNil([HBLCommonConfig shared].uuid);
    header[@"Content-Type"] = SetSafeStringNil(contentType);
    header[@"app_version"]  = SetSafeStringNil([HBLCommonConfig shared].appVerSion);
    header[@"app_type"]     = @"i-angejia";
    header[@"os"]           = SetSafeStringNil([HBLCommonConfig shared].osv);
    [postDictionary setValue:header forKey:@"header"];
    
    return postDictionary;
}

- (void)postInfoWithNetworkTransactions:(NSArray *)transactions
{
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *inProcessSession = [NSURLSession sessionWithConfiguration:sessionConfig delegate:nil delegateQueue:nil];
    
    NSURL *managerUrl = [NSURL URLWithString:self.url];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:managerUrl cachePolicy:sessionConfig.requestCachePolicy timeoutInterval:sessionConfig.timeoutIntervalForRequest];
    request.HTTPMethod = @"POST";
    
    NSError *error;
    NSData *postData = [NSJSONSerialization dataWithJSONObject:transactions options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        NSLog(@"json convert error, object = %@", self);
    }else{
        NSString *postString = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
        NSLog(@"post data :#########\n%@\n",postString);
    }
    
    request.HTTPBody = postData;
    // 信号量
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSInteger statusCode = 0;
    
    NSURLSessionDataTask *dataTask = [inProcessSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString *resultString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"result :%@",resultString);
        
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
            statusCode = httpResponse.statusCode;
        }
        
        dispatch_semaphore_signal(semaphore);
        
    }];
    
    [dataTask resume];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (httpResponse && ((statusCode >= 200 && statusCode <= 300) || statusCode == 304) && !error) {
        // 请求成功，数据清空
        [self.hasTransactions removeAllObjects];
        // 删除文件
        dispatch_async(self.ioQueue, ^{
            [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:nil];
        });
        
    } else {
        // 请求失败
    }
}


-(void)forceSend{
    // 如果当前是 WI-FI 环境
    if ([[HBLNetworkUtility getNetworkStatus] isEqualToString:@"WIFI"]) {
        [self postInfoWithNetworkTransactions:self.hasTransactions];
    }
    
}

#pragma mark -  getter / setter

- (NSString *)filePath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = paths[0];
    path  = [NSString stringWithFormat:@"%@/%@", path, networkDataUploadFile];
    NSLog(@"HBLNetworkDataUpload: filePath = %@", path);
    return path;
}

@end
