//
//  HBLNetworkUtility.m
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import "HBLNetworkUtility.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <ImageIO/ImageIO.h>

#include <sys/socket.h> // Per msqr
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

@implementation HBLNetworkUtility

+ (SEL)swizzledSelectorForSelector:(SEL)selector
{
    return NSSelectorFromString([NSString stringWithFormat:@"HBL_swizzled_%@", NSStringFromSelector(selector)]);
}

+ (NSString *)mechansimFromClassMethod:(SEL)selector Class:(Class)class
{
    return [NSString stringWithFormat:@"+[%@ %@]", NSStringFromClass(class), NSStringFromSelector(selector)];
}

+ (NSString *)getUniqueRequestID
{
    return [[NSUUID UUID] UUIDString];
}

+ (UIImage *)thumbnailedImageWithMaxPixelDimension:(NSInteger)dimension fromImageData:(NSData *)data
{
    UIImage *thumbnail = nil;
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, 0);
    if (imageSource) {
        NSDictionary *options = @{ (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
                                   (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
                                   (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(dimension) };
        
        CGImageRef scaledImageRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
        if (scaledImageRef) {
            thumbnail = [UIImage imageWithCGImage:scaledImageRef];
            CFRelease(scaledImageRef);
        }
        CFRelease(imageSource);
    }
    return thumbnail;
}

// 使用 swizzle 的 block 实现替换已有方法 originSelector 的实现
+ (void)replaceImpOfOriginSelector:(SEL)originSelector Class:(Class)class swizzledBlock:(id)block swizzledSelector:(SEL)swizzledSelector
{
    Method originMethod = class_getInstanceMethod(class, originSelector);
    if (!originMethod) {
        return;
    }
    
    IMP implementation = imp_implementationWithBlock(block);
    class_addMethod(class, swizzledSelector, implementation, method_getTypeEncoding(originMethod));
    
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    method_exchangeImplementations(originMethod, swizzledMethod);
}

// delegate 中方法 swizzle
+ (void)replaceImpOfOriginSelector:(SEL)originSelector swizzledSelector:(SEL)swizzledSelector Class:(Class)class methodDescription:(struct objc_method_description)methodDesc swizzledBlock:(id)swizzledBlock undefinedBlock:(id)undefinedBlock
{
    if ([self instanceRespondsButDoesNotImplementSelector:originSelector Class:class]) {
        return;
    }
    
    IMP implementation = nil;
    if ([class instancesRespondToSelector:originSelector]) {
        implementation = imp_implementationWithBlock(swizzledBlock);
    } else {
        implementation = imp_implementationWithBlock(undefinedBlock);
    }
    
    Method originMethod = class_getInstanceMethod(class, originSelector);
    if (originMethod) {
        class_addMethod(class, swizzledSelector, implementation, methodDesc.types);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        method_exchangeImplementations(originMethod, swizzledMethod);
    } else {
        class_addMethod(class, originSelector, implementation, methodDesc.types);
    }
}

// 判断当前类的该方法有无被实现
+ (BOOL)instanceRespondsButDoesNotImplementSelector:(SEL)selector Class:(Class)class
{
    if ([class instancesRespondToSelector:selector]) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(class, &methodCount);
        
        BOOL implementsSelector = NO;
        for (int idx = 0; idx < methodCount; idx++) {
            if (method_getName(methods[idx]) == selector) {
                implementsSelector = YES;
                break;
            }
        }
        
        free(methods);
        
        if (!implementsSelector) {
            return YES;
        }
    }
    return NO;
}

// 如果此处不判断是否主线程，直接使用 dispatch_sync ，则当获取该方法是在主线程执行，会造成主线程 block
+ (NSString *)getNetworkStatus
{
    __block NSString *networkStatus = @"";
    
    if ([[NSThread currentThread] isMainThread]) {
        networkStatus = [self innerNetworkStatus];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            networkStatus = [self innerNetworkStatus];
        });
    }
    
    return networkStatus;
}

+ (NSString *)innerNetworkStatus
{
    NSString *networkStatus = @"";
    NSArray *subviews = [[[[UIApplication sharedApplication] valueForKey:@"statusBar"] valueForKey:@"foregroundView"]subviews];
    NSNumber *dataNetworkItemView = nil;
    
    if (subviews) {
        for (id subview in subviews) {
            if([subview isKindOfClass:[NSClassFromString(@"UIStatusBarDataNetworkItemView") class]]) {
                dataNetworkItemView = subview;
                break;
            }
        }
    }
    
    if (!dataNetworkItemView) {
        networkStatus = @"";
    }
    
    switch ([[dataNetworkItemView valueForKey:@"dataNetworkType"] integerValue]) {
        case 0:
            networkStatus = @"";
            break;
        case 1:
            networkStatus = @"2G";
            break;
        case 2:
            networkStatus = @"3G";
            break;
        case 3:
            networkStatus = @"4G";
            break;
        case 4:
            networkStatus = @"LTE";
            break;
        case 5:
            networkStatus = @"WIFI";
            break;
        default:
            break;
    }
    
    return networkStatus;
}

+ (NSString *)getIp
{
    return [self CFL_localIPAddress];
}

+ (NSString *)CFL_localIPAddress
{
    NSString *address = @"0.0.0.0";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;
}

static char kHBLNetworkObserverRequestIDKey;

// 关联 task 和 requestID
+ (void)setRequestID:(NSString *)requestID forConnectionTask:(id)connectionOrTask
{
    objc_setAssociatedObject(connectionOrTask, &kHBLNetworkObserverRequestIDKey, requestID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 为 HBLNetworkObserver 的 category 提供获取 requestID 的方法
+ (NSString *)requestIDforConnectionOrTask:(id)connectionOrTask
{
    NSString *requestID = objc_getAssociatedObject(connectionOrTask, &kHBLNetworkObserverRequestIDKey);
    if (!requestID) {
        requestID = [self getUniqueRequestID];
        [self setRequestID:requestID forConnectionTask:connectionOrTask];
    }
    return requestID;
}

+ (NSString *)getErrorCodeFromData:(NSData *)data
{
    if (data) {
        id content = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if ([content isKindOfClass:[NSDictionary class]]) {
            if (content[@"code"]) {
                return content[@"code"];
            }
            
        }
    }
    return @"";
}

@end
