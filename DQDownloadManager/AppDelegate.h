//
//  AppDelegate.h
//  DQDownload
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (copy) void (^backgroundSessionCompletionHandler)();

@end

