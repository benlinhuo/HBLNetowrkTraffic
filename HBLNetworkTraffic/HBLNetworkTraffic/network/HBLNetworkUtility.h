//
//  HBLNetworkUtility.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/13.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <UIkit/UIkit.h>

@interface HBLNetworkUtility : NSObject

+ (SEL)swizzledSelectorForSelector:(SEL)selector;

+ (NSString *)mechansimFromClassMethod:(SEL)selector Class:(Class)class;

+ (NSString *)getUniqueRequestID;

+ (UIImage *)thumbnailedImageWithMaxPixelDimension:(NSInteger)dimension fromImageData:(NSData *)data;

+ (void)replaceImpOfOriginSelector:(SEL)originSelector Class:(Class)class swizzledBlock:(id)block swizzledSelector:(SEL)swizzledSelector;

+ (void)replaceImpOfOriginSelector:(SEL)originSelector swizzledSelector:(SEL)swizzledSelector Class:(Class)class methodDescription:(struct objc_method_description)methodDesc swizzledBlock:(id)swizzledBlock undefinedBlock:(id)undefinedBlock;

+ (BOOL)instanceRespondsButDoesNotImplementSelector:(SEL)selector Class:(Class)class;

+ (void)setRequestID:(NSString *)requestID forConnectionTask:(id)connectionOrTask;

+ (NSString *)requestIDforConnectionOrTask:(id)connectionOrTask;

+ (NSString *)getNetworkStatus;

+ (NSString *)getIp;

+ (NSString *)getErrorCodeFromData:(NSData *)data;


@end
