//
//  HBLNetworkObserver.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <objc/runtime.h>
#import <objc/message.h>

#import "HBLNetworkObserver.h"
#import "HBLNetworkObserver+NSURLConnectionHelpers.h"
#import "HBLNetworkObserver+NSURLSessionTaskHelpers.h"
#import "HBLNetworkUtility.h"
#import "HBLNetworkRecorder.h"
#import "HBLNetworkInternalRequestState.h"

typedef void (^NSURLSessionAsyncCompletion)(id fileURLOrData, NSURLResponse *response, NSError *error);

@interface HBLNetworkObserver ()

@property (nonatomic, strong) dispatch_queue_t queue;

@end

@implementation HBLNetworkObserver

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.requestStatesForRequestIDs = [NSMutableDictionary dictionary];
        self.queue = dispatch_queue_create("com.angejia.HBLNetworkObserver", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (instancetype)shared
{
    static HBLNetworkObserver *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[[self class] alloc] init];
        
    });
    return shared;
}

// 动态设置初始化，是否需要流量统计。每次程序启动都需要指定。主线程中初始化
+ (void)setEnabled:(BOOL)enabled
{
    if (enabled) {
        [self injectIntoAllNetworkDelegateClasses];
    }
}

- (void)performBlock:(dispatch_block_t)block
{
    dispatch_async(self.queue, block);
}

- (HBLNetworkInternalRequestState *)requestStateForRequestID:(NSString *)requestID
{
    HBLNetworkInternalRequestState *requestState = self.requestStatesForRequestIDs[requestID];
    if (!requestState) {
        requestState = [HBLNetworkInternalRequestState new];
        [self.requestStatesForRequestIDs setObject:requestState forKey:requestID];
    }
    return  requestState;
}

- (void)removeRequestStateForRequestID:(NSString *)requestID
{
    [self.requestStatesForRequestIDs removeObjectForKey:requestID];
}

#pragma mark - inject

+ (void)injectIntoAllNetworkDelegateClasses
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const SEL selectors[] = {
            @selector(connectionDidFinishLoading:),
            @selector(connection:willSendRequest:redirectResponse:),
            @selector(connection:didReceiveResponse:),
            @selector(connection:didReceiveData:),
            @selector(connection:didFailWithError:),
            @selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:),
            @selector(URLSession:dataTask:didReceiveData:),
            @selector(URLSession:dataTask:didReceiveResponse:completionHandler:),
            @selector(URLSession:task:didCompleteWithError:),
            @selector(URLSession:dataTask:didBecomeDownloadTask:delegate:),
            @selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:),
            @selector(URLSession:downloadTask:didFinishDownloadingToURL:)
        };
        
        const int numSelectors = sizeof(selectors) / sizeof(SEL);
        
        Class *classes = NULL;
        // 获取项目所有类的数目
        int numClasses = objc_getClassList(NULL, 0);
        
        if (numClasses > 0) {
            // classes 表示项目中的所有类
            classes = (__unsafe_unretained Class*)malloc(sizeof(Class) * numClasses);
            numClasses = objc_getClassList(classes, numClasses);
            
            // 循环所有类中的所有方法，只要某个类有 selectors 中的任何一个方法，就进行 swizzle method
            for (NSInteger classIdx = 0; classIdx < numClasses; classIdx++) {
                Class class = classes[classIdx];
                
                if (class == [HBLNetworkObserver class]) {
                    continue;
                }
                
                // 防止引入的 FLEXNetworkObserver 这个类造成干扰
                if ([NSStringFromClass(class) isEqualToString:@"FLEXNetworkObserver"]) {
                    continue;
                }
                
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(class, &methodCount);
                BOOL matchingSelectorFound = NO; // 用于结束一个类的循环
                
                for (unsigned int methodIdx = 0; methodIdx < methodCount; methodIdx++) {
                    for (int selectorIdx = 0; selectorIdx < numSelectors; selectorIdx++) {
                        if (method_getName(methods[methodIdx]) == selectors[selectorIdx]) {
                            [self injectIntoDelegateClass:class];
                            matchingSelectorFound = YES;
                            break;
                        }
                    }
                    if (matchingSelectorFound) {
                        break;
                    }
                }
                
                free(methods);
                
            }
            
            free(classes);
        }
        
        [self injectIntoNSURLConnectionCancel];
        [self injectIntoNSURLSessionTaskResume];
        
        [self injectIntoNSURLConnectionAsynchronousClassMethod];
        [self injectIntoNSURLConnectionSynchronousClassMethod];
        
        [self injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods];
        [self injectIntoNSURLSessionAsyncUploadTaskMethods];
        
    });
}



// 所有的都是用了 dispatch_once ，只需要一次即可
+ (void)injectIntoDelegateClass:(Class)cls
{
    // Connections
    [self injectWillSendRequestIntoDelegateClass:cls];
    [self injectDidReceiveDataIntoDelegateClass:cls];
    [self injectDidReceiveResponseIntoDelegateClass:cls];
    [self injectDidFinishLoadingIntoDelegateClass:cls];
    [self injectDidFailWithErrorIntoDelegateClass:cls];
    
    // Sessions
    [self injectTaskWillPerformHTTPRedirectionIntoDelegateClass:cls];
    [self injectTaskDidReceiveDataIntoDelegateClass:cls];
    [self injectTaskDidReceiveResponseIntoDelegateClass:cls];
    [self injectTaskDidCompleteWithErrorIntoDelegateClass:cls];
    [self injectRespondsToSelectorIntoDelegateClass:cls];
    
    // Data tasks
    [self injectDataTaskDidBecomeDownloadTaskIntoDelegateClass:cls];
    
    // Download tasks
    [self injectDownloadTaskDidWriteDataIntoDelegateClass:cls];
    [self injectDownloadTaskDidFinishDownloadingIntoDelegateClass:cls];}

// cancel
+ (void)injectIntoNSURLConnectionCancel
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [NSURLConnection class];
        SEL selector = @selector(cancel);
        SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
        
        typedef void(^CancelBlock)(NSURLConnection *con);
        CancelBlock block = ^(NSURLConnection *con){
            // 嵌入的统计代码
            [[HBLNetworkObserver shared] connectionWillCancel:con];
            // 本应该执行的代码
            ((void(*)(id, SEL))objc_msgSend)(con, swizzledSelector);
        };
        
        // 为该类添加 swizzledSelector 的实现
        [HBLNetworkUtility replaceImpOfOriginSelector:selector Class:class swizzledBlock:block swizzledSelector:swizzledSelector];
    });
}

// resume
+ (void)injectIntoNSURLSessionTaskResume
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // In iOS 7 resume lives in __NSCFLocalSessionTask
        // In iOS 8 resume lives in NSURLSessionTask
        // In iOS 9 resume lives in __NSCFURLSessionTask
        Class class = nil;
        if (![[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)]) {
            // iOS 7
            class = NSClassFromString(@"__NSCFLocalSessionTask");
        } else if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 9) {
            // iOS 8
            class = [NSURLSession class];
        } else {
            class = NSClassFromString(@"__NSCFURLSessionTask");
        }
        
        SEL selector = @selector(resume);
        SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
        
        typedef void(^ResumeBlock)(NSURLSessionTask *task);
        ResumeBlock block = ^(NSURLSessionTask *task){
            [[HBLNetworkObserver shared] URLSessionTaskWillResume:task];
            ((void(*)(id, SEL))objc_msgSend)(task, swizzledSelector);
        };
        
        [HBLNetworkUtility replaceImpOfOriginSelector:selector Class:class swizzledBlock:block swizzledSelector:swizzledSelector];
    });
}

+ (void)injectIntoNSURLConnectionAsynchronousClassMethod
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 类方法获取元类
        Class class = objc_getMetaClass(class_getName([NSURLConnection class]));
        
        SEL selector = @selector(sendAsynchronousRequest:queue:completionHandler:);
        SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
        
        typedef void(^CompletionBlock)(NSURLResponse *response, NSData *data, NSError *error);
        typedef void(^SendAsynchronousBlock)(Class slf, NSURLRequest *request, NSOperationQueue *queue, CompletionBlock completion);
        
        SendAsynchronousBlock sendBlock = ^(Class slf, NSURLRequest *request, NSOperationQueue *queue, CompletionBlock completion){
            
            NSString *requestID = [HBLNetworkUtility getUniqueRequestID];
            
            [[HBLNetworkRecorder shared] beforeAsyncExecCreateTransactionWithRequestID:requestID];
            
            [[HBLNetworkRecorder shared] recordRequestWillBeSentWithRequestID:requestID request:request redirectResponse:nil];
            
            NSString *mechanism = [HBLNetworkUtility mechansimFromClassMethod:selector Class:class];
            [[HBLNetworkRecorder shared] recordMechanism:mechanism forRequestID:requestID];
            
            // completionBlock ＝ 统计代码＋原先 block 该执行内容
            CompletionBlock completionBlock = ^(NSURLResponse *response, NSData *data, NSError *error){
                [[HBLNetworkRecorder shared] recordDidReceivedResponseWithRequestID:requestID response:response];
                [[HBLNetworkRecorder shared] recordDidReceivedDataWithRequestID:requestID dataLength:[data length]];
                
                if (error) {
                    NSString *errorCode = [HBLNetworkUtility getErrorCodeFromData:data];
                    [[HBLNetworkRecorder shared] recordDidFailedLoadingWithRequestID:requestID HBLErrorCode:errorCode error:error];
                } else {
                    NSDate *endTime = [NSDate date];
                    [[HBLNetworkRecorder shared] recordDidFinishedLoadingWithRequestID:requestID responseBody:data endTime:endTime];
                }
                
                if (completion) {
                    completion(response, data, error);
                }
            };
            
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, request, queue, completionBlock);
        };
        
        [HBLNetworkUtility replaceImpOfOriginSelector:selector Class:class swizzledBlock:sendBlock swizzledSelector:swizzledSelector];
        
    });
}

// sendSynchronousRequest:returningResponse:error: 类方法
+ (void)injectIntoNSURLConnectionSynchronousClassMethod
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = objc_getMetaClass(class_getName([NSURLConnection class]));
        SEL selector = @selector(sendSynchronousRequest:returningResponse:error:);
        SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
        
        //
        typedef NSData *(^SendSynchronousRequestBlock)(Class slf, NSURLRequest *request, NSURLResponse **response, NSError **error);
        
        SendSynchronousRequestBlock sendSyncBlock = ^NSData *(Class slf, NSURLRequest *request, NSURLResponse **response, NSError **error) {
            NSString *requestID = [HBLNetworkUtility getUniqueRequestID];
            
            [[HBLNetworkRecorder shared] beforeAsyncExecCreateTransactionWithRequestID:requestID];
            [[HBLNetworkRecorder shared] recordRequestWillBeSentWithRequestID:requestID request:request redirectResponse:nil];
            
            NSString *mechanism = [HBLNetworkUtility mechansimFromClassMethod:selector Class:class];
            [[HBLNetworkRecorder shared] recordMechanism:mechanism forRequestID:requestID];
            
            NSError *tempError = nil;
            NSURLResponse *tempResponse = nil;
            
            NSData *data = ((id(*)(id, SEL, id, NSURLResponse **, NSError **))objc_msgSend)(slf, swizzledSelector, request, &tempResponse, &tempError);
            
            [[HBLNetworkRecorder shared] recordDidReceivedResponseWithRequestID:requestID response:tempResponse];
            [[HBLNetworkRecorder shared] recordDidReceivedDataWithRequestID:requestID dataLength:[data length]];
            
            if (tempError) {
                NSString *errorCode = [HBLNetworkUtility getErrorCodeFromData:data];
                [[HBLNetworkRecorder shared] recordDidFailedLoadingWithRequestID:requestID HBLErrorCode:errorCode error:tempError];
            } else {
                NSDate *endTime = [NSDate date];
                
                [[HBLNetworkRecorder shared] recordDidFinishedLoadingWithRequestID:requestID responseBody:data endTime:endTime];
            }
            
            if (error) {
                *error = tempError;
            }
            if (response) {
                *response = tempResponse;
            }
            
            return data;
            
        };
        
        [HBLNetworkUtility replaceImpOfOriginSelector:selector Class:class swizzledBlock:sendSyncBlock swizzledSelector:swizzledSelector];
    });
}

+ (void)injectIntoNSURLSessionAsyncDataAndDownloadTaskMethods
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [NSURLSession class];
        
        const SEL selectors[] = {
            @selector(dataTaskWithRequest:completionHandler:),
            @selector(dataTaskWithURL:completionHandler:),
            @selector(downloadTaskWithRequest:completionHandler:),
            @selector(downloadTaskWithResumeData:completionHandler:),
            @selector(downloadTaskWithURL:completionHandler:)
        };
        
        const int numSelectors = sizeof(selectors) / sizeof(SEL);
        
        for (int idx = 0; idx < numSelectors; idx++) {
            SEL selector = selectors[idx];
            SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
            
            if ([HBLNetworkUtility instanceRespondsButDoesNotImplementSelector:selector Class:class]) {
                // iOS7 并没有在类 NSURLSession 中实现这些方法。我们实际上是想要 swizzle __NSCFURLSession，如下获取
                class = [[NSURLSession sharedSession] class];
            }
            
            NSURLSessionTask *(^asyncDataOrDownloadSwizzleBlock)(Class slf, id argument, NSURLSessionAsyncCompletion completion) =^NSURLSessionTask *(Class slf, id argument, NSURLSessionAsyncCompletion completion){
                
                NSURLSessionTask *task = nil;
                // 如果没有提供 completion，则拿不到结果。
                if (completion) {
                    NSString *requestID = [HBLNetworkUtility getUniqueRequestID];
                    NSString *mechanism = [HBLNetworkUtility mechansimFromClassMethod:selector Class:class];
                    
                    NSURLSessionAsyncCompletion completionBlock = [self asyncCompletionBlockForRequestID:requestID mechanism:mechanism completion:completion];
                    
                    task = ((id(*)(id, SEL, id, id))objc_msgSend)(slf, swizzledSelector, argument, completionBlock);
                    
                    [HBLNetworkUtility setRequestID:requestID forConnectionTask:task];
                    
                } else {
                    task = ((id(*)(id, SEL, id, id))objc_msgSend)(slf, swizzledSelector, argument, completion);
                    
                }
                
                return task;
            };
            
            [HBLNetworkUtility replaceImpOfOriginSelector:selector Class:class swizzledBlock:asyncDataOrDownloadSwizzleBlock swizzledSelector:swizzledSelector];
        }
        
    });
}

+ (void)injectIntoNSURLSessionAsyncUploadTaskMethods
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [NSURLSession class];
        
        const SEL selectors[] = {
            @selector(uploadTaskWithRequest:fromData:completionHandler:),
            @selector(uploadTaskWithRequest:fromFile:completionHandler:)
        };
        
        const int numSelectors = sizeof(selectors) / sizeof(SEL);
        
        for (int idx = 0 ; idx < numSelectors; idx++) {
            
            SEL selector = selectors[idx];
            SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
            
            if (![HBLNetworkUtility instanceRespondsButDoesNotImplementSelector:selector Class:class]) {
                class = [[NSURLSession sharedSession] class];
            }
            
            typedef NSURLSessionUploadTask *(^AsyncUploadTaskBlock)(Class slf, NSURLRequest *request, id argument, NSURLSessionAsyncCompletion completion);
            
            AsyncUploadTaskBlock taskBlock = ^NSURLSessionUploadTask *(Class slf, NSURLRequest *request, id argument, NSURLSessionAsyncCompletion completion){
                
                NSURLSessionUploadTask *task = nil;
                
                NSString *requestID = [HBLNetworkUtility getUniqueRequestID];
                NSString *mechanism = [HBLNetworkUtility mechansimFromClassMethod:selector Class:class];
                
                NSURLSessionAsyncCompletion completionBlock = [self asyncCompletionBlockForRequestID:requestID mechanism:mechanism completion:completion];
                
                task = ((id(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, request, argument, completionBlock);
                
                [HBLNetworkUtility setRequestID:requestID forConnectionTask:task];
                
                return task;
            };
            
            [HBLNetworkUtility replaceImpOfOriginSelector:selector Class:class swizzledBlock:taskBlock swizzledSelector:swizzledSelector];
            
        }
        
    });
}


#pragma mark - NSURLConnection
// URL 重定向（delegate 中方法）
// 需要注意点：1. 非系统调用，开发者手动调用，不需要统计；2.开发者没有实现这个方法，需要统计；3.开发者实现这个方法，需要统计
+ (void)injectWillSendRequestIntoDelegateClass:(Class)class
{
    SEL selector = @selector(connection:willSendRequest:redirectResponse:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLConnectionDataDelegate);
    if (!protocol) {
        protocol = @protocol(NSURLConnectionDelegate);
    }
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef NSURLRequest *(^NSURLConnectionWillSendRequestBlock)(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSURLRequest *request, NSURLResponse *response);
    
    NSURLConnectionWillSendRequestBlock undefinedBlock = ^NSURLRequest*(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSURLRequest *request, NSURLResponse *response) {
        
        [[HBLNetworkObserver shared] connection:connection willSendRequest:request redirectResponse:response delegate:slf];
        return request;
    };
    
    NSURLConnectionWillSendRequestBlock implementationBlock = ^NSURLRequest *(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSURLRequest *request, NSURLResponse *response) {
        __block NSURLRequest *returnValue = nil;
        
        [self sniffWithoutDuplicationForObject:connection selector:selector sniffingBlock:^{
            undefinedBlock(slf, connection, request, response);
            
        } originalImplementationBlock:^{
            returnValue = ((id(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, connection, request, response);
        }];
        return returnValue;
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
    
}

+ (void)injectDidReceiveDataIntoDelegateClass:(Class)class
{
    SEL selector = @selector(connection:didReceiveData:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLConnectionDataDelegate);
    if (!protocol) {
        protocol = @protocol(NSURLConnectionDelegate);
    }
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void(^NSURLConnectionDidReceiveDataBlock)(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSData *data);
    
    NSURLConnectionDidReceiveDataBlock undefinedBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSData *data) {
        [[HBLNetworkObserver shared] connection:connection didReceiveData:data delegate:slf];
    };
    
    NSURLConnectionDidReceiveDataBlock implementationBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSData *data) {
        [self sniffWithoutDuplicationForObject:connection selector:selector sniffingBlock:^{
            undefinedBlock(slf, connection, data);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id))objc_msgSend)(slf, swizzledSelector, connection, data);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

+ (void)injectDidReceiveResponseIntoDelegateClass:(Class)class
{
    SEL selector = @selector(connection:didReceiveResponse:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLConnectionDataDelegate);
    if (!protocol) {
        protocol = @protocol(NSURLConnectionDelegate);
    }
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void(^NSURLConnectionDidReceiveResponseBlock)(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSURLResponse *response);
    
    NSURLConnectionDidReceiveResponseBlock undefinedBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSURLResponse *response){
        [[HBLNetworkObserver shared] connection:connection didReceiveResponse:response delegate:slf];
    };
    
    NSURLConnectionDidReceiveResponseBlock implementationBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSURLResponse *response){
        [self sniffWithoutDuplicationForObject:connection selector:selector sniffingBlock:^{
            undefinedBlock(slf, connection, response);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id))objc_msgSend)(slf, swizzledSelector, connection, response);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
    
}

+ (void)injectDidFinishLoadingIntoDelegateClass:(Class)class
{
    SEL selector = @selector(connectionDidFinishLoading:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLConnectionDataDelegate);
    if (!protocol) {
        protocol = @protocol(NSURLConnectionDelegate);
    }
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void(^NSURLConnectionDidFinishLoadingBlock)(id <NSURLConnectionDelegate> slf, NSURLConnection *connection);
    
    // undefinedBlock 用于流量统计的代码
    NSURLConnectionDidFinishLoadingBlock undefinedBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection) {
        [[HBLNetworkObserver shared] connectionDidFinishLoading:connection delegate:slf];
    };
    
    NSURLConnectionDidFinishLoadingBlock implementationBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection) {
        [self sniffWithoutDuplicationForObject:connection selector:selector sniffingBlock:^{
            undefinedBlock(slf, connection);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id))objc_msgSend)(slf, swizzledSelector, connection);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

+ (void)injectDidFailWithErrorIntoDelegateClass:(Class)class
{
    SEL selector = @selector(connection:didFailWithError:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLConnectionDelegate);
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLConnectionDidFailWithErrorBlock)(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSError *error);
    
    NSURLConnectionDidFailWithErrorBlock undefinedBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSError *error) {
        [[HBLNetworkObserver shared] connection:connection didFailWithError:error delegate:slf];
    };
    
    NSURLConnectionDidFailWithErrorBlock implementationBlock = ^(id <NSURLConnectionDelegate> slf, NSURLConnection *connection, NSError *error) {
        [self sniffWithoutDuplicationForObject:connection selector:selector sniffingBlock:^{
            undefinedBlock(slf, connection, error);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id))objc_msgSend)(slf, swizzledSelector, connection, error);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

#pragma mark - NSURLSessionTask

+ (void)injectTaskWillPerformHTTPRedirectionIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionTaskDelegate);
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionWillPerformHTTPRedirectionBlock)(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionTask *task, NSHTTPURLResponse *response, NSURLRequest *newRequest, void(^completionHandler)(NSURLRequest *));
    
    NSURLSessionWillPerformHTTPRedirectionBlock undefinedBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionTask *task, NSHTTPURLResponse *response, NSURLRequest *newRequest, void(^completionHandler)(NSURLRequest *)) {
        [[HBLNetworkObserver shared] URLSession:session task:task willPerformHTTPRedirection:response newRequest:newRequest completionHandler:completionHandler delegate:slf];
    };
    
    NSURLSessionWillPerformHTTPRedirectionBlock implementationBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionTask *task, NSHTTPURLResponse *response, NSURLRequest *newRequest, void(^completionHandler)(NSURLRequest *)) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, task, response, newRequest, completionHandler);
        } originalImplementationBlock:^{
            ((id(*)(id, SEL, id, id, id, id, void(^)()))objc_msgSend)(slf, swizzledSelector, session, task, response, newRequest, completionHandler);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}


#pragma mark - dataTask
+ (void)injectTaskDidReceiveDataIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:dataTask:didReceiveData:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionDataDelegate);
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionDidReceiveDataBlock)(id <NSURLSessionDataDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data);
    
    NSURLSessionDidReceiveDataBlock undefinedBlock = ^(id <NSURLSessionDataDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data) {
        [[HBLNetworkObserver shared] URLSession:session dataTask:dataTask didReceiveData:data delegate:slf];
    };
    
    NSURLSessionDidReceiveDataBlock implementationBlock = ^(id <NSURLSessionDataDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, dataTask, data);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, session, dataTask, data);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

+ (void)injectTaskDidReceiveResponseIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:dataTask:didReceiveResponse:completionHandler:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionDataDelegate);
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionDidReceiveResponseBlock)(id <NSURLSessionDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response, void(^completionHandler)(NSURLSessionResponseDisposition disposition));
    
    NSURLSessionDidReceiveResponseBlock undefinedBlock = ^(id <NSURLSessionDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response, void(^completionHandler)(NSURLSessionResponseDisposition disposition)) {
        [[HBLNetworkObserver shared] URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler delegate:slf];
    };
    
    NSURLSessionDidReceiveResponseBlock implementationBlock = ^(id <NSURLSessionDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response, void(^completionHandler)(NSURLSessionResponseDisposition disposition)) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, dataTask, response, completionHandler);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id, id, void(^)()))objc_msgSend)(slf, swizzledSelector, session, dataTask, response, completionHandler);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

+ (void)injectTaskDidCompleteWithErrorIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:task:didCompleteWithError:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionTaskDelegate);
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionTaskDidCompleteWithErrorBlock)(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionTask *task, NSError *error);
    
    NSURLSessionTaskDidCompleteWithErrorBlock undefinedBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
        [[HBLNetworkObserver shared] URLSession:session task:task didCompleteWithError:error delegate:slf];
    };
    
    NSURLSessionTaskDidCompleteWithErrorBlock implementationBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, task, error);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, session, task, error);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

#pragma mark - downloadTask
// dataTask 转 downloadTask
+ (void)injectDataTaskDidBecomeDownloadTaskIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:dataTask:didBecomeDownloadTask:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionDataDelegate);
    
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionDidBecomeDownloadTaskBlock)(id <NSURLSessionDataDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask);
    
    NSURLSessionDidBecomeDownloadTaskBlock undefinedBlock = ^(id <NSURLSessionDataDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask) {
        [[HBLNetworkObserver shared] URLSession:session dataTask:dataTask didBecomeDownloadTask:downloadTask delegate:slf];
    };
    
    NSURLSessionDidBecomeDownloadTaskBlock implementationBlock = ^(id <NSURLSessionDataDelegate> slf, NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, dataTask, downloadTask);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, session, dataTask, downloadTask);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
    
}

+ (void)injectDownloadTaskDidWriteDataIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionDownloadDelegate);
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionDownloadTaskDidWriteDataBlock)(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionDownloadTask *task, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite);
    
    NSURLSessionDownloadTaskDidWriteDataBlock undefinedBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionDownloadTask *task, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        [[HBLNetworkObserver shared] URLSession:session downloadTask:task didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite delegate:slf];
    };
    
    NSURLSessionDownloadTaskDidWriteDataBlock implementationBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionDownloadTask *task, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, task, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id, int64_t, int64_t, int64_t))objc_msgSend)(slf, swizzledSelector, session, task, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
    
}

+ (void)injectDownloadTaskDidFinishDownloadingIntoDelegateClass:(Class)class
{
    SEL selector = @selector(URLSession:downloadTask:didFinishDownloadingToURL:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Protocol *protocol = @protocol(NSURLSessionDownloadDelegate);
    struct objc_method_description methodDesc = protocol_getMethodDescription(protocol, selector, NO, YES);
    
    typedef void (^NSURLSessionDownloadTaskDidFinishDownloadingBlock)(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionDownloadTask *task, NSURL *location);
    
    NSURLSessionDownloadTaskDidFinishDownloadingBlock undefinedBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionDownloadTask *task, NSURL *location) {
        NSData *data = [NSData dataWithContentsOfFile:location.relativePath];
        [[HBLNetworkObserver shared] URLSession:session task:task didFinishDownloadingToURL:location data:data delegate:slf];
    };
    
    NSURLSessionDownloadTaskDidFinishDownloadingBlock implementationBlock = ^(id <NSURLSessionTaskDelegate> slf, NSURLSession *session, NSURLSessionDownloadTask *task, NSURL *location) {
        [self sniffWithoutDuplicationForObject:session selector:selector sniffingBlock:^{
            undefinedBlock(slf, session, task, location);
        } originalImplementationBlock:^{
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(slf, swizzledSelector, session, task, location);
        }];
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

#pragma mark - respondsToSelector
// Used for overriding AFNetworking behavior
+ (void)injectRespondsToSelectorIntoDelegateClass:(Class)class
{
    SEL selector = @selector(respondsToSelector:);
    SEL swizzledSelector = [HBLNetworkUtility swizzledSelectorForSelector:selector];
    
    Method method = class_getInstanceMethod(class, selector);
    struct objc_method_description methodDesc = *method_getDescription(method);
    
    BOOL (^undefinedBlock)(id <NSURLSessionTaskDelegate>, SEL) = ^(id slf, SEL sel) {
        return YES;
    };
    
    BOOL (^implementationBlock)(id <NSURLSessionTaskDelegate>, SEL) = ^(id <NSURLSessionTaskDelegate> slf, SEL sel) {
        if (sel == @selector(URLSession:dataTask:didReceiveResponse:completionHandler:)) {
            return undefinedBlock(slf, sel);
        }
        return ((BOOL(*)(id, SEL, SEL))objc_msgSend)(slf, swizzledSelector, sel);
    };
    
    [HBLNetworkUtility replaceImpOfOriginSelector:selector swizzledSelector:swizzledSelector Class:class methodDescription:methodDesc swizzledBlock:implementationBlock undefinedBlock:undefinedBlock];
}

#pragma mark - private
+ (NSURLSessionAsyncCompletion)asyncCompletionBlockForRequestID:(NSString *)requestID mechanism:(NSString *)mechanism completion:(NSURLSessionAsyncCompletion)completion
{
    NSURLSessionAsyncCompletion block = ^(id fileURLOrData, NSURLResponse *response, NSError *error){
        [[HBLNetworkRecorder shared] recordMechanism:mechanism forRequestID:requestID];
        [[HBLNetworkRecorder shared] recordDidReceivedResponseWithRequestID:requestID response:response];
        
        NSData *data = nil;
        if ([fileURLOrData isKindOfClass:[NSURL class]]) {
            data = [NSData dataWithContentsOfURL:fileURLOrData];
        } else if ([fileURLOrData isKindOfClass:[NSData class]]) {
            data = fileURLOrData;
        }
        
        [[HBLNetworkRecorder shared] recordDidReceivedDataWithRequestID:requestID dataLength:data.length];
        if (error) {
            NSString *errorCode = [HBLNetworkUtility getErrorCodeFromData:data];
            [[HBLNetworkRecorder shared] recordDidFailedLoadingWithRequestID:requestID HBLErrorCode:errorCode error:error];
        } else {
            NSDate *endTime = [NSDate date];
            [[HBLNetworkRecorder shared] recordDidFinishedLoadingWithRequestID:requestID responseBody:data endTime:endTime];
        }
        
        if (completion) {
            completion(fileURLOrData, response, error);
        }
        
    };
    
    return block;
}

+ (void)sniffWithoutDuplicationForObject:(NSObject *)object selector:(SEL)selector sniffingBlock:(void (^)(void))sniffingBlock originalImplementationBlock:(void (^)(void))originalImplementationBlock
{
    // 当开发者直接调用这个 delegate 方法，而不是由系统调用，则不插入流量统计信息
    if (!object) {
        originalImplementationBlock();
        return;
    }
    
    if (!objc_getAssociatedObject(object, selector)) {
        sniffingBlock();
    }
    
    objc_setAssociatedObject(object, selector, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    originalImplementationBlock();
    objc_setAssociatedObject(object, selector, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}


@end

