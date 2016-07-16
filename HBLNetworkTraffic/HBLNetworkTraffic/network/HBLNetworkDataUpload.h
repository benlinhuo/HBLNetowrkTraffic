//
//  HBLNetworkDataUpload.h
//  HBLNetworkTraffic
//
//  Created by benlinhuo on 16/7/15.
//  Copyright © 2016年 Benlinhuo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HBLNetworkDataUpload : NSObject

// pageName 会在 API 发送请求的时候，就与 API 绑定，防止在 API 请求结束时已经进入下一个页面
@property (nonatomic, copy) NSString *pageName;

@property (nonatomic, assign) NSInteger maxSendNum;

@property (nonatomic, copy) NSString *url;// 发送服务器的地址

+ (HBLNetworkDataUpload *)shared;

@end
