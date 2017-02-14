//
//  DQDownloadManager.h
//  DQDownload
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import <Foundation/Foundation.h>

// Library/cache/DQDownload
#define kDQDownloadDirectory                           @"DQDownload"

#define kDQDownloadDefaultConcurrentDownloadingCount   3

typedef NS_ENUM(NSInteger, DQDownloadState) {
    DQDownloadStateReady,
    DQDownloadStateDownloading,
    DQDownloadStateWaiting,
    DQDownloadStatePaused,
    DQDownloadStateFinished,
    DQDownloadStateFailed
};

typedef NS_ENUM(NSInteger, DQDownloadError) {
    DQDownloadErrorNone,
    DQDownloadErrorExisting,
    DQDownloadErrorDownloaded,
    DQDownloadErrorUrlError,
    DQDownloadErrorNetworkNotReachable,
    DQDownloadErrorWifiNotReachable
};

@protocol DQDownloadItemProtocol <NSObject>

@property (nonatomic,readonly) NSString              *downloadUrl;
@property (nonatomic,readonly) NSDictionary          *downloadExtrasData;
@property (nonatomic,readonly) NSString              *targetPath;//nil before downloaded
@property (nonatomic,readonly) NSString              *downloadSpeed;
@property (nonatomic,readonly) DQDownloadState        downloadState;
@property (nonatomic,readonly) long long              totalLength;
@property (nonatomic,readonly) long long              downloadedLength;
@property (nonatomic,readonly) double                 downloadProgress;

@end

typedef void(^ChallengeCompletionHandler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential);
typedef void(^ReceiveChallengeHandle)(NSURLSession*session,NSURLSessionTask*task,NSURLAuthenticationChallenge *challenge,ChallengeCompletionHandler completionHandler);


/**
 基于NSURLSession的并发下载组件
 1.支持后台下载
 2.支持断点下载
 3.可控下载并发数
 4.下载状态：暂停、下载中、等待、下载失败
 5.支持设置是否允许蜂窝移动网络下下载
 */
@interface DQDownloadManager : NSObject

///正在下载的任务
@property (nonatomic,readonly) NSArray<id<DQDownloadItemProtocol>>   *downloadedItems;
///已经下载完成的任务
@property (nonatomic,readonly) NSArray<id<DQDownloadItemProtocol>>   *downloadingItems;
///自定义http请求头
@property (nonatomic,copy    ) NSDictionary                    *httpHeader;
@property (nonatomic,assign  ) NSInteger                       concurrentDownloadingCount;//defarlt 2 max 3
@property (nonatomic,assign  ) BOOL                            allowedBackgroundDownload;//default YES
@property (nonatomic,assign  ) BOOL                            allowedDownloadOnWWAN;//default NO
@property (nonatomic,copy    ) ReceiveChallengeHandle          receiveChallengeHandle;
@property (nonatomic,copy    ) void(^downloadAllCompleteInbackground)();

+ (instancetype)sharedManager;


/**
 开始一个下载任务

 @param url url
 @param extrasData 需要保存的附加信息
 @return 错误信息
 */
- (DQDownloadError)startDownloadWithUrl:(NSString *)url
                                 extrasData:(NSDictionary *)extrasData;

- (DQDownloadError)startDownloadWithRequest:(NSURLRequest *)urlRequest
                                     extrasData:(NSDictionary *)extrasData;


/**
 暂停所有下载任务
 */
- (void)pauseAllDownloadTask;

/**
 恢复所有下载任务

 @return 错误信息
 */
- (DQDownloadError)resumeAllDownloadTask;


/**
 删除一个下载中任务或者已下载的文件
 @param url url
 */
- (void)deleteDownloadWithUrl:(NSString *)url;

/**
 暂停一个下载任务

 @param url url
 */
- (void)pauseDownloadTaskWithUrl:(NSString *)url;

/**
 恢复一个下载任务

 @param url url
 @return 错误信息
 */
- (DQDownloadError)resumeDownloadTaskWithUrl:(NSString *)url;

/**
 删除所有下载任务
 */
- (void)deleteAllDownloadingTask;

/**
 删除所有已下载文件
 */
- (void)deleteAllDownloadedFile;

/**
 返回下载目录

 @return 下载目录
 */
- (NSString *)downloadDirectory;

/**
 获取文件下载路径

 @param url url
 @return 文件下载路径
 */
- (NSString *)downloadPathWithUrl:(NSString *)url;

/**
 磁盘总空间

 @return 磁盘总空间
 */
+ (float)totalDiskSpaceInBytes;

/**
 磁盘剩余空间

 @return 磁盘剩余空间
 */
+ (float)freeDiskSpaceInBytes;

@end

///--------------------
/// @name Notifications
/// @ notification.object = id<DQDownloadItemProtocol>
///--------------------

//
extern NSString * const DQDownloadProgressChangedNotification;

//notification.object = id<DQDownloadItemProtocol>
// notification.userInfo = @{@"index":@(/*index in downloadingItems of the downloadedItem*/)}
extern NSString * const DQDownloadStateChangedNotification;

