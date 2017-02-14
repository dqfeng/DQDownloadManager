//
//  DQDownloadManager.m
//  DQDownloadManager
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import "DQDownloadManager.h"
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#include <sys/param.h>
#include <sys/mount.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

@interface NSString (md5)

- (NSString *)md5;

@end

@implementation NSString (md5)

- (NSString *) md5
{
  const char *cStr = [self UTF8String];
  unsigned char result[16];
  CC_MD5( cStr, (unsigned int) strlen(cStr), result);
  return [NSString stringWithFormat:
          @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
          result[0], result[1], result[2], result[3],
          result[4], result[5], result[6], result[7],
          result[8], result[9], result[10], result[11],
          result[12], result[13], result[14], result[15]
          ];
}

@end

/////////////////////////////////////////////////////////////////////

@interface DQDownloadItem : NSObject<DQDownloadItemProtocol>

@property (nonatomic,strong) NSString                   * downloadUrl;
@property (nonatomic,strong) NSString                   * targetPath;
@property (nonatomic,strong) NSURLSessionDownloadTask   * downloadTask;
@property (nonatomic,strong) NSDictionary               * downloadExtrasData;
@property (nonatomic,assign) DQDownloadState              downloadState;
@property (nonatomic,assign) long long                    totalLength;
@property (nonatomic,assign) long long                    downloadedLength;
@property (nonatomic,assign) double                       downloadProgress;
@property (nonatomic,strong) NSString                   * downloadSpeed;
@property (nonatomic,strong) NSDate                     * date;
@property (nonatomic,assign) long long                    bytesOfOneSecondDownload;
@property (nonatomic,strong) NSData                     * resumeData;
@property (nonatomic,strong) NSURLRequest               * request;
@property (nonatomic,assign) BOOL                         canceling;

@end

@implementation DQDownloadItem

@end

////////////////////////////////////////////////////////////////////

NSString *const kDQDownloading            = @"DQDwonloading";
NSString *const kDQDownloaded             = @"DQDownloaded";
NSString *const kDownloadUrl              = @"DownloadUrl";
NSString *const kDownloadState            = @"DownloadState";
NSString *const kDownloadExtrasData       = @"DownloadExtrasData";
NSString *const kDownloadProgress         = @"DownloadProgress";
NSString *const kTargetPath               = @"TargetPath";
NSString *const kTotalLength              = @"TotalLength";
NSString *const kDownloadedLength         = @"DownloadedLength";
NSString *const kResumeData               = @"ResumeData";

@interface DQDownloadManager ()<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic,strong) NSMutableArray             *downloadingInfo;
@property (nonatomic,strong) NSMutableDictionary        *downloadedInfoDic;
@property (nonatomic,strong) NSMutableArray<id<DQDownloadItemProtocol>>    *downloaded_items;
@property (nonatomic,strong) NSMutableArray<id<DQDownloadItemProtocol>>    *downloading_items;
@property (nonatomic,strong) NSMutableDictionary        *downloadersDic;
@property (nonatomic,strong) NSURLSession               *session;
@property (nonatomic,assign) NSInteger                   currentDownloadingCount;
@property (nonatomic,copy)   NSString                   * tempDirectory;
@property (nonatomic,assign) SCNetworkReachabilityRef     reachabilityRef;


- (void)networkReachableChangedWith:(SCNetworkReachabilityFlags)flags;

@end

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info)
{
  @autoreleasepool
  {
    DQDownloadManager* manager = (__bridge DQDownloadManager*)info;
    [manager networkReachableChangedWith:flags];
  }
}

@implementation DQDownloadManager

+ (void)load
{
  __block id observer =
  [[NSNotificationCenter defaultCenter]
   addObserverForName:UIApplicationDidFinishLaunchingNotification
   object:nil
   queue:nil
   usingBlock:^(NSNotification *note) {
     [DQDownloadManager sharedManager];
     [[NSNotificationCenter defaultCenter] removeObserver:observer];
   }];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSURLSession *)backgroundSession
{
  static NSURLSession * session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration *configuration = nil;
    if ([UIDevice currentDevice].systemVersion.floatValue >= 8.0) {
      configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.dqfeng.DQDownload.backgroundSession"];
    }
    else {
      configuration = [NSURLSessionConfiguration backgroundSessionConfiguration:@"com.dqfeng.DQDownload.backgroundSession"];
    }
    NSOperationQueue *queue            = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount  = 1;
    configuration.allowsCellularAccess = false;
    session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
  });
  return session;
}

+ (instancetype)sharedManager
{
  static DQDownloadManager *manager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    manager = [[DQDownloadManager alloc] init];
    manager.downloaded_items       = [NSMutableArray array];
    manager.downloading_items      = [NSMutableArray array];
    manager.session               = [manager backgroundSession];
    manager.downloadersDic        = [NSMutableDictionary dictionary];
    NSUserDefaults *userDefaults  = [NSUserDefaults standardUserDefaults];
    if ([userDefaults objectForKey:kDQDownloaded]) {
      manager.downloadedInfoDic = [NSMutableDictionary dictionaryWithDictionary:[userDefaults objectForKey:kDQDownloaded]];
      for (NSDictionary *dic in [manager.downloadedInfoDic allValues]) {
        DQDownloadItem *downloadedItem = [[DQDownloadItem alloc] init];
        downloadedItem.downloadUrl          =   dic[kDownloadUrl];
        downloadedItem.downloadState        =   [dic[kDownloadState] integerValue];
        downloadedItem.downloadExtrasData   =   dic[kDownloadExtrasData];
        downloadedItem.downloadProgress     =   [dic[kDownloadProgress] floatValue];
        downloadedItem.targetPath           =   dic[kTargetPath];
        downloadedItem.totalLength          =   [dic[kTotalLength] longLongValue];
        downloadedItem.downloadedLength     =   [dic[kDownloadedLength] longLongValue];
        [manager.downloaded_items addObject:downloadedItem];
      }
    }
    else {
      manager.downloadedInfoDic     = [NSMutableDictionary dictionary];
    }
    if ([userDefaults objectForKey:kDQDownloading]) {
      manager.downloadingInfo = [NSMutableArray arrayWithArray:[userDefaults objectForKey:kDQDownloading]];
      for (NSDictionary *dic in manager.downloadingInfo) {
        DQDownloadItem *downloadingItem    = [[DQDownloadItem alloc] init];
        downloadingItem.downloadUrl        =   dic[kDownloadUrl];
        downloadingItem.downloadProgress   =   [dic[kDownloadProgress] floatValue];
        downloadingItem.downloadState      =   DQDownloadStatePaused;
        downloadingItem.downloadExtrasData =   dic[kDownloadExtrasData];
        downloadingItem.downloadState      =   DQDownloadStatePaused;
        downloadingItem.targetPath         =   dic[kTargetPath];
        downloadingItem.totalLength        =   [dic[kTotalLength] longLongValue];
        downloadingItem.downloadedLength   =   [dic[kDownloadedLength] longLongValue];
        if ([dic objectForKey:kResumeData]) {
          downloadingItem.resumeData = dic[kResumeData];
        }
        manager.downloadersDic[[downloadingItem.downloadUrl md5]] = downloadingItem;
        [manager.downloading_items addObject:downloadingItem];
      }
    }
    else {
      manager.downloadingInfo   = [NSMutableArray array];
    }
    [manager.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
      dispatch_async(dispatch_get_main_queue(), ^{
        for (NSURLSessionDownloadTask *task in downloadTasks) {
          if (!task.error) {
            [task cancelByProducingResumeData:^(NSData *resumeData) {
              NSString *url        = task.currentRequest.URL.absoluteString;
              DQDownloadItem *item = manager.downloadersDic[[url md5]];
              item.resumeData = resumeData ?: nil;
            }];
          }
        }
      });
    }];
    manager.concurrentDownloadingCount                = kDQDownloadDefaultConcurrentDownloadingCount;
    manager.allowedBackgroundDownload                 = YES;
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    manager.reachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)&zeroAddress);
    
    [[NSNotificationCenter defaultCenter] addObserver:manager selector:@selector(didEnterBackgroundHandle) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:manager selector:@selector(willTerminateHandle) name:UIApplicationWillTerminateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:manager selector:@selector(willEnterForegroundHandle) name:UIApplicationWillEnterForegroundNotification object:nil];
    [manager startNotifierOnRunLoop:[NSRunLoop currentRunLoop]];
  });
  return manager;
}

#pragma mark-
#pragma mark Application Notification Handle
- (void)willEnterForegroundHandle
{
  for (DQDownloadItem *item in self.downloading_items) {
    if (item.downloadState == DQDownloadStateDownloading) {
      if (self.currentDownloadingCount < self.concurrentDownloadingCount) {
        ++self.currentDownloadingCount;
      }
      else {
        if (item.downloadTask.state != NSURLSessionTaskStateCompleted) {
          [self cancelDownloadTaskWithItem:item];
        }
        item.downloadState = DQDownloadStateWaiting;
      }
      [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
    }
  }
}

- (void)didEnterBackgroundHandle
{
  for (DQDownloadItem *item in self.downloading_items) {
    
    if (self.allowedBackgroundDownload) {
      if (item.downloadState == DQDownloadStateWaiting) {
        if (item.downloadState != NSURLSessionTaskStateCompleted) {
          BOOL suc = [self resumeDownloadWithItem:item];
          if (!suc) {
            item.downloadState = DQDownloadStateFailed;
            [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
            continue;
          }
          item.downloadState = DQDownloadStateDownloading;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
        }
      }
    }
    else {
      if (item.downloadState == DQDownloadStateDownloading) {
        [self cancelDownloadTaskWithItem:item];
      }
      if (item.downloadState != DQDownloadStatePaused && item.downloadState != DQDownloadStateFailed) {
        item.downloadState  = DQDownloadStatePaused;
        [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
      }
    }
  }
  self.currentDownloadingCount = 0;
  [self saveDownloadInfo];
}

- (void)willTerminateHandle
{
  for (DQDownloadItem *item in self.downloading_items) {
    if (item.downloadTask.state == NSURLSessionTaskStateRunning) {
      [self cancelDownloadTaskWithItem:item];
      item.downloadState = DQDownloadStatePaused;
    }
  }
  if (self.downloading_items.count == 0) {
    [self.session invalidateAndCancel];
  }
  [self saveDownloadInfo];
}

- (void)saveDownloadInfo
{
  [self.downloadingInfo removeAllObjects];
  for (DQDownloadItem *downloadItem in self.downloading_items) {
    NSDictionary *itemInfo = @{kDownloadUrl       :downloadItem.downloadUrl,
                               kDownloadExtrasData:downloadItem.downloadExtrasData,
                               kDownloadState     :@(downloadItem.downloadState),
                               kDownloadProgress  :@(downloadItem.downloadProgress),
                               kTotalLength       :@(downloadItem.totalLength),
                               kDownloadedLength  :@(downloadItem.downloadedLength)};
    NSMutableDictionary *mutableItemInfo = [NSMutableDictionary dictionaryWithDictionary:itemInfo];
    if (downloadItem.resumeData) {
      mutableItemInfo[kResumeData] = downloadItem.resumeData;
    }
    [self.downloadingInfo addObject:mutableItemInfo];
  }
  
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
  [userDefaults setObject:self.downloadedInfoDic forKey:kDQDownloaded];
  [userDefaults setObject:self.downloadingInfo   forKey:kDQDownloading];
  [userDefaults synchronize];
}

#pragma mrak-
#pragma mark setter

- (void)setConcurrentDownloadingCount:(NSInteger)concurrentDownloadingCount
{
  _concurrentDownloadingCount = concurrentDownloadingCount > 3?3:concurrentDownloadingCount;
}

- (void)setAllowedDownloadOnWWAN:(BOOL)allowedDownloadOnWWAN
{
  _allowedDownloadOnWWAN = allowedDownloadOnWWAN;
  self.session.configuration.allowsCellularAccess = allowedDownloadOnWWAN;
}

#pragma mark- getter
- (NSArray *)downloadedItems
{
    return self.downloaded_items;
}

- (NSArray *)downloadingItems
{
    return self.downloading_items;
}

#pragma mark-
#pragma mark start download
- (void)setHttpheadersWithRequest:(NSMutableURLRequest *)request
{
  if (self.httpHeader) {
    [self.httpHeader enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
      [request setValue:obj forHTTPHeaderField:key];
    }];
  }
}

- (DQDownloadError)startDownloadWithUrl:(NSString *)url
                             extrasData:(NSDictionary *)extrasData
{
  NSURL *requestUrl = [NSURL URLWithString:url];
  if (!requestUrl) {
    return DQDownloadErrorUrlError;
  }
  NSMutableURLRequest *request   = [[NSMutableURLRequest alloc] initWithURL:requestUrl cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:15];
  [self setHttpheadersWithRequest:request];
  if (extrasData == nil) {
    extrasData = @{};
  }
  return [self startDownloadWithRequest:request  extrasData:extrasData];
}

- (DQDownloadError)startDownloadWithRequest:(NSURLRequest *)urlRequest
                                 extrasData:(NSDictionary *)extrasData
{
  if ([self.downloadedInfoDic objectForKey:[urlRequest.URL.absoluteString md5]]) {
    return DQDownloadErrorDownloaded;
  }
  else if ([self.downloadersDic objectForKey:[urlRequest.URL.absoluteString md5]]) {
    return DQDownloadErrorExisting;
  }
  DQDownloadItem *downloadItem    = [[DQDownloadItem alloc] init];
  downloadItem.downloadUrl        = urlRequest.URL.absoluteString;
  downloadItem.request            = urlRequest;
  downloadItem.downloadExtrasData = extrasData;
  if ([self isReachable]) {
    if (self.currentDownloadingCount < self.concurrentDownloadingCount) {
      downloadItem.downloadTask = [self.session downloadTaskWithRequest:urlRequest];
      if (!downloadItem.downloadTask.currentRequest) {
        [downloadItem.downloadTask cancel];
        return DQDownloadErrorUrlError;
      }
      [downloadItem.downloadTask resume];
      downloadItem.downloadState = DQDownloadStateDownloading;
      ++self.currentDownloadingCount;
    }
    else {
      downloadItem.downloadState = DQDownloadStateWaiting;
    }
  }
  else {
    downloadItem.downloadState    = DQDownloadStatePaused;
    if ([self isReachableViaWWAN]) {
      return DQDownloadErrorWifiNotReachable;
    }
    else {
      return DQDownloadErrorNetworkNotReachable;
    }
  }
  [self.downloading_items addObject:downloadItem];
  self.downloadersDic[[urlRequest.URL.absoluteString md5]] = downloadItem;
  return DQDownloadErrorNone;
}

#pragma mark-
#pragma mark download control

- (void)cancelDownloadTaskWithItem:(DQDownloadItem *)item
{
  BOOL notCancelable = (item.canceling || (item.downloadTask == nil) || (item.downloadTask.state == NSURLSessionTaskStateCompleted) || (item.downloadTask.state == NSURLSessionTaskStateCanceling));
  if (notCancelable) {return;}
  item.canceling = YES;
  dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, DISPATCH_TIME_FOREVER);

  dispatch_semaphore_t seamphore = dispatch_semaphore_create(0);
  [item.downloadTask cancelByProducingResumeData:^(NSData *resumeData) {
    item.resumeData = resumeData;
    dispatch_semaphore_signal(seamphore);
  }];
  dispatch_semaphore_wait(seamphore, waitTime);
  item.canceling = NO;
  item.downloadTask = nil;
}

- (void)pauseDownloadTaskWithUrl:(NSString *)url
{
  if ([self.downloadersDic objectForKey:[url md5]]) {
    DQDownloadItem *item = self.downloadersDic[[url md5]];
    [self cancelDownloadTaskWithItem:item];
    item.downloadState   = DQDownloadStatePaused;
    --self.currentDownloadingCount;
    [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
    [self resumeAWaitingItemWithIndex:[self.downloading_items indexOfObject:item]];
  }
}

- (BOOL)resumeDownloadWithItem:(DQDownloadItem *)item
{
  if (item.resumeData) {
    item.downloadTask = [self.session downloadTaskWithResumeData:item.resumeData];
  }
  else {
    if (item.request) {
      item.downloadTask = [self.session downloadTaskWithRequest:item.request];
    }
    else {
      NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:item.downloadUrl]];
      [self setHttpheadersWithRequest:request];
      item.request = request;
      item.downloadTask = [self.session downloadTaskWithRequest:request];
    }
  }
  if (!item.downloadTask.currentRequest) {
    [item.downloadTask cancel];
    return NO;
  }
  [item.downloadTask resume];
  return YES;
}

- (void)resumeAWaitingItemWithIndex:(NSInteger)index
{
  BOOL success = NO;
  for (NSInteger i= (index + 1); i<self.downloading_items.count;++i) {
    DQDownloadItem *item = self.downloading_items[i];
    if (item.downloadState == DQDownloadStateWaiting && self.currentDownloadingCount < self.concurrentDownloadingCount) {
      if (item.downloadTask.state != NSURLSessionTaskStateCompleted) {
        BOOL suc = [self resumeDownloadWithItem:item];
        if (!suc) {
          item.downloadState = DQDownloadStateFailed;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
          continue;
        }
        item.downloadState = DQDownloadStateDownloading;
        ++self.currentDownloadingCount;
        success = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
        break;
      }
    }
  }
  
  if (!success) {
    for (int i=0; i<self.downloading_items.count; ++i) {
      DQDownloadItem *item = self.downloading_items[i];
      if (item.downloadState == DQDownloadStateWaiting && self.currentDownloadingCount < self.concurrentDownloadingCount) {
        if (item.downloadTask.state != NSURLSessionTaskStateCompleted) {
          BOOL suc = [self resumeDownloadWithItem:item];
          if (!suc) {
            item.downloadState = DQDownloadStateFailed;
            [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
            continue;
          }
          item.downloadState = DQDownloadStateDownloading;
          ++self.currentDownloadingCount;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
          break;
        }
      }
    }
  }
}

- (DQDownloadError)resumeDownloadTaskWithUrl:(NSString *)url
{
  if (![self isReachable]) {
    if ([self isReachableViaWWAN]) {
      return DQDownloadErrorWifiNotReachable;
    }
    else {
      return DQDownloadErrorNetworkNotReachable;
    }
  }
  DQDownloadItem *item = self.downloadersDic[[url md5]];
  if ([self.downloadersDic objectForKey:[url md5]]) {
    switch (item.downloadState) {
      case DQDownloadStatePaused:
      {
        if (self.currentDownloadingCount < self.concurrentDownloadingCount) {
          BOOL success = [self resumeDownloadWithItem:item];
          if (!success) {
            item.downloadState = DQDownloadStateFailed;
            [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
            return DQDownloadErrorUrlError;
          }
          item.downloadState = DQDownloadStateDownloading;
          ++self.currentDownloadingCount;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
          
        }
        else {
          item.downloadState = DQDownloadStateWaiting;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
        }
      }
        break;
      case DQDownloadStateWaiting:
      {
        item.downloadState = DQDownloadStatePaused;
        [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
      }
        break;
      case DQDownloadStateFailed:
      {
        if (self.currentDownloadingCount < self.concurrentDownloadingCount) {
          BOOL success = [self resumeDownloadWithItem:item];
          if (!success) {
            return DQDownloadErrorUrlError;
          }
          item.downloadState = DQDownloadStateDownloading;
          ++self.currentDownloadingCount;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
        }
        else {
          item.downloadState = DQDownloadStateWaiting;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
        }
      }
        break;
      default:
        break;
    }
  }
  return DQDownloadErrorNone;
}

- (void)deleteDownloadWithUrl:(NSString *)url
{
    if ([self.downloadersDic objectForKey:[url md5]]) {
        DQDownloadItem *item = self.downloadersDic[[url md5]];
        if (item.downloadState == DQDownloadStateDownloading) {
            --self.currentDownloadingCount;
            [self resumeAWaitingItemWithIndex:[self.downloaded_items indexOfObject:item]];
        }
        item.downloadState = DQDownloadStateFinished;
        [item.downloadTask cancel];
        item.downloadTask = nil;
        [self.downloading_items removeObject:item];
        [self.downloadersDic   removeObjectForKey:[url md5]];
        [self.downloadingInfo  removeObject:item];
    }
    else if ([self.downloadedInfoDic objectForKey:[url md5]]) {
        [self.downloadedInfoDic removeObjectForKey:[url md5]];
        for (DQDownloadItem *item in self.downloaded_items) {
            if ([item.downloadUrl isEqualToString:url]) {
                [self.downloaded_items removeObject:item];
                break;
            }
        }
    
        NSString *filePath = [self downloadPathWithUrl:url];
        BOOL fileExist     = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
        NSError *error     = nil;
        if (fileExist) {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        }
        if (error) {
            NSLog(@"%s:删除文件失败：%@",__FUNCTION__,error);
        }
    }
}

- (void)pauseAllDownloadTask
{
  for (DQDownloadItem *item in self.downloading_items) {
    if (item.downloadState == DQDownloadStateFailed || item.downloadState == DQDownloadStateWaiting) {
      item.downloadState = DQDownloadStatePaused;
      [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
    }
    else if (item.downloadState == DQDownloadStateDownloading) {
      [self cancelDownloadTaskWithItem:item];
      item.downloadState = DQDownloadStatePaused;
      [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
    }
  }
  self.currentDownloadingCount = 0;
}

- (DQDownloadError)resumeAllDownloadTask
{
  if (![self isReachable]) {
    if ([self isReachableViaWWAN]) {
      return DQDownloadErrorWifiNotReachable;
    }
    return DQDownloadErrorNetworkNotReachable;
  }
  for (DQDownloadItem *item in self.downloading_items) {
    if (self.currentDownloadingCount < self.concurrentDownloadingCount) {
      if (item.downloadState != DQDownloadStateDownloading) {
        BOOL suc = [self resumeDownloadWithItem:item];
        if (!suc) {
          item.downloadState = DQDownloadStateFailed;
          continue;
        }
        item.downloadState = DQDownloadStateDownloading;
        ++self.currentDownloadingCount;
      }
    }
    else {
      if (item.downloadState != DQDownloadStateDownloading) {
        item.downloadState = DQDownloadStateWaiting;
      }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
  }
  return DQDownloadErrorNone;
}

- (void)deleteAllDownloadingTask
{
  [self.downloadersDic removeAllObjects];
  [self.downloadingInfo removeAllObjects];
  for (DQDownloadItem *item in self.downloading_items) {
    item.downloadState = DQDownloadStateFinished;
    [item.downloadTask cancel];
    item.downloadTask = nil;
  }
  self.currentDownloadingCount = 0;
  [self.downloading_items removeAllObjects];
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  [self.session resetWithCompletionHandler:^{dispatch_semaphore_signal(semaphore);}];
  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
  if (self.tempDirectory) {
    NSError *error = nil;
    NSArray *directoryContents = [[NSFileManager defaultManager]
                                  contentsOfDirectoryAtPath:self.tempDirectory error:&error];
    if (error){NSLog(@"%s--error:%@",__func__,error);}
    error = nil;
    for(NSString *fileName in directoryContents) {
      NSString *path = [self.tempDirectory stringByAppendingPathComponent:fileName];
      BOOL fileExit = [[NSFileManager defaultManager] fileExistsAtPath:path];
      if (!fileExit) {
        return;
      }
      [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
      if(error) {
        NSLog(@"%s--delete downloadedFile error:%@",__func__,error);
      }
    }
  }
  [self saveDownloadInfo];
}

- (void)deleteAllDownloadedFile
{
  [self.downloaded_items removeAllObjects];
  [self.downloadedInfoDic removeAllObjects];
  NSError *error = nil;
  NSArray *directoryContents = [[NSFileManager defaultManager]
                                contentsOfDirectoryAtPath:[self downloadDirectory] error:&error];
  if (error) NSLog(@"%s--error:%@",__func__,error);
  error = nil;
  for(NSString *fileName in directoryContents) {
    NSString *path = [[self downloadDirectory] stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if(error) {
      NSLog(@"%s--delete downloadedFile error:%@",__func__,error);
    }
  }
}

#pragma mark-
#pragma mark   session delegate
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
  NSHTTPURLResponse *response =  (NSHTTPURLResponse*)downloadTask.response;
  if (response.statusCode == 404) return;
  double progress = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
  NSString *key = [downloadTask.currentRequest.URL.absoluteString md5];
  dispatch_async(dispatch_get_main_queue(), ^{
    DQDownloadItem *item  = self.downloadersDic[key];
    if (item.downloadTask == nil) {
      [downloadTask cancelByProducingResumeData:^(NSData *resumeData) {
        item.resumeData = resumeData;
      }];
      return ;
    }
    item.downloadProgress = progress;
    item.downloadedLength = totalBytesWritten;
    if (!item.date) {
      item.date = [NSDate date];
    }
    if (!item.totalLength) {
      item.totalLength  = totalBytesExpectedToWrite;
    }
    
    item.bytesOfOneSecondDownload += bytesWritten;
    NSDate *currentDate = [NSDate date];
    double time = [currentDate timeIntervalSinceDate:item.date];
    if (time >= 1) {
      long long speed                  = item.bytesOfOneSecondDownload/time;
      item.downloadSpeed               = [NSByteCountFormatter stringFromByteCount:speed countStyle:NSByteCountFormatterCountStyleFile];
      item.bytesOfOneSecondDownload    = 0.0;
      item.date                        = currentDate;
    }
    if (time > 0.5) {
      [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadProgressChangedNotification object:item];
    }
  });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)downloadURL
{
  
  if (!self.tempDirectory) {
    NSString *lastPathComponent = [downloadURL absoluteString].lastPathComponent;
    NSMutableString *tempUrlStr = [NSMutableString stringWithString:[downloadURL absoluteString]];
    [tempUrlStr deleteCharactersInRange:[tempUrlStr rangeOfString:lastPathComponent]];
    [tempUrlStr deleteCharactersInRange:[tempUrlStr rangeOfString:@"file://"]];
    self.tempDirectory = [NSString stringWithString:tempUrlStr];
  }
  NSString *url              = downloadTask.currentRequest.URL.absoluteString;
  NSFileManager *fileManager = [NSFileManager defaultManager];
  BOOL fileExists = [fileManager fileExistsAtPath:[self downloadPathWithUrl:url]];
  if (fileExists) return;
  NSError *errorMove;
  NSURL *destinationURL      = [NSURL fileURLWithPath:[self downloadPathWithUrl:url]];
  BOOL success               = [fileManager moveItemAtURL:downloadURL toURL:destinationURL error:&errorMove];
  if (!success)
  {
    NSLog(@"%s--move file error :%@",__func__,errorMove);
  }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  dispatch_async(dispatch_get_main_queue(), ^{
    NSString *url = task.currentRequest.URL.absoluteString;
    DQDownloadItem *downloadItem = self.downloadersDic[[url md5]];
    if (!downloadItem) {
      [task cancel];
      return;
    }
    if (error == nil) {
      downloadItem.targetPath = [self downloadPathWithUrl:url];
      NSDictionary *itemInfo = @{kDownloadUrl       :downloadItem.downloadUrl,
                                 kDownloadState     :@(DQDownloadStateFinished),
                                 kDownloadProgress  :@(downloadItem.downloadProgress),
                                 kDownloadExtrasData:downloadItem.downloadExtrasData,
                                 kTargetPath        :downloadItem.targetPath,
                                 kTotalLength       :@(downloadItem.totalLength),
                                 kDownloadedLength  :@(downloadItem.totalLength)};
      self.downloadedInfoDic[[downloadItem.downloadUrl md5]] = itemInfo;
      [self.downloaded_items addObject:downloadItem];
      NSInteger index = [self.downloading_items indexOfObject:downloadItem];
      if (downloadItem.downloadState == DQDownloadStateDownloading && self.currentDownloadingCount > 0) {
        --self.currentDownloadingCount;
        downloadItem.downloadState = DQDownloadStateFinished;
        [self resumeAWaitingItemWithIndex:index];
      }
      downloadItem.downloadState = DQDownloadStateFinished;
      downloadItem.downloadTask  = nil;
      [self.downloadersDic removeObjectForKey:[downloadItem.downloadUrl md5]];
      [self.downloading_items removeObject:downloadItem];
      if (index != NSNotFound) {
        [[NSNotificationCenter defaultCenter]
         postNotificationName:DQDownloadStateChangedNotification
         object:downloadItem
         userInfo:@{@"index":@(index)}];
      }
    }
    else {
        
      if (downloadItem.downloadState == DQDownloadStateFinished) return ;
      
      downloadItem.downloadTask = nil;
      NSData *resumeData = nil;
      if (!([[error.userInfo objectForKey:@"NSLocalizedDescription"] isEqualToString:@"cancelled"] && error.code == NSURLErrorCancelled)) {
        resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
        if (resumeData) {
          downloadItem.resumeData = resumeData;
          double progress = (double)task.countOfBytesReceived / (double)task.countOfBytesExpectedToReceive;
          if (!((progress >= 1) || (task.countOfBytesExpectedToReceive == 0) || (task.countOfBytesReceived == 0))) {
            downloadItem.downloadProgress = progress;
            downloadItem.downloadedLength = task.countOfBytesReceived;
            downloadItem.totalLength      = task.countOfBytesExpectedToReceive;
            [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadProgressChangedNotification object:downloadItem];
          }
        }
        if (downloadItem.downloadState == DQDownloadStateDownloading && error.code != NSURLErrorCancelled) {
          NSLog(@"%s--downloadError:%@",__func__,error);
          downloadItem.downloadState = DQDownloadStateFailed;
          --self.currentDownloadingCount;
          [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:downloadItem];
          [self resumeAWaitingItemWithIndex:[self.downloading_items indexOfObject:downloadItem]];
        }
      }
    }
  });
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
  id appDelegate = [[UIApplication sharedApplication] delegate];
  if ([appDelegate respondsToSelector:@selector(backgroundSessionCompletionHandler)]) {
    if ([appDelegate performSelector:@selector(backgroundSessionCompletionHandler)]) {
      void (^completionHandler)() = [appDelegate performSelector:@selector(backgroundSessionCompletionHandler)];
      [appDelegate performSelector:@selector(setBackgroundSessionCompletionHandler:) withObject:nil];
      completionHandler();
    }
  }
#pragma clang diagnostic pop
  if (self.downloadAllCompleteInbackground) {
    self.downloadAllCompleteInbackground();
  }
  NSLog(@"All tasks are finished");
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
  NSLog(@"resume");
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
  if (self.receiveChallengeHandle) {
    self.receiveChallengeHandle(session,task,challenge,completionHandler);
  }
}

#pragma mark-
#pragma mark download path

- (NSString *)downloadDirectory
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *cachesDirectory     = paths[0];
  NSString *downloadedDirectory = [cachesDirectory stringByAppendingPathComponent:kDQDownloadDirectory];
  BOOL isDirectory  = YES;
  BOOL folderExists = [[NSFileManager defaultManager] fileExistsAtPath:downloadedDirectory isDirectory:&isDirectory] && isDirectory;
  if (!folderExists)
  {
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:downloadedDirectory withIntermediateDirectories:YES attributes:nil error:&error];
  }
  return downloadedDirectory;
}

- (NSString *)downloadPathWithUrl:(NSString *)url
{
  NSString *filePath = [self.downloadDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",[url md5],url.pathExtension]];
  return filePath;
}

#pragma mark-
#pragma mark notifier networkReachability

-(BOOL) startNotifierOnRunLoop:(NSRunLoop*)runLoop
{
  BOOL retVal = NO;
  SCNetworkReachabilityContext context = { 0, (__bridge  void *)(self), NULL, NULL, NULL };
  
  if (SCNetworkReachabilitySetCallback(self.reachabilityRef, ReachabilityCallback, &context)) {
    if(SCNetworkReachabilityScheduleWithRunLoop(self.reachabilityRef, runLoop.getCFRunLoop, kCFRunLoopDefaultMode)) {
      retVal = YES;
    }
  }
  return retVal;
}

-(void) stopNotifier
{
  if (self.reachabilityRef != NULL)
  {
    SCNetworkReachabilitySetCallback(self.reachabilityRef, NULL, NULL);
    SCNetworkReachabilityUnscheduleFromRunLoop(self.reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
  }
}

- (void)networkReachableChangedWith:(SCNetworkReachabilityFlags)flags
{
  //327683  gprs/edg
  BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
  BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
  BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
  BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
  BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
  
  dispatch_async(dispatch_get_main_queue(), ^{
    if (isNetworkReachable == NO) {
      [self performSelector:@selector(networkNotReachableHandle) withObject:nil afterDelay:3.5];
    }
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
      //viawwan
      if (!self.allowedDownloadOnWWAN) {
        [self performSelector:@selector(networkChangedToWWANHandle) withObject:nil afterDelay:3.5];
      }
    }
    else {
      //wifi
    }
  });
}

-(void)networkChangedToWWANHandle
{
  if (![self isReachableViaWiFi] && [self isReachableViaWWAN]) {
    [self pauseAllDownloadTask];
  }
  else if (![self isReachableViaWiFi] && ![self isReachableViaWWAN]) {
    [self networkNotReachableHandle];
  }
}

- (void)networkNotReachableHandle
{
  if ([self isReachableViaWiFi]) {
    return;
  }
  else if ([self isReachableViaWWAN]
           ) {
    [self networkChangedToWWANHandle];
    return;
  }
  for (DQDownloadItem *item in self.downloading_items) {
    if (item.downloadState != DQDownloadStatePaused) {
      if (item.downloadTask) {
        [self cancelDownloadTaskWithItem:item];
      }
      if (item.downloadState != DQDownloadStateFailed) {
        item.downloadState = DQDownloadStateFailed;
        [[NSNotificationCenter defaultCenter] postNotificationName:DQDownloadStateChangedNotification object:item];
      }
    }
  }
  self.currentDownloadingCount = 0;
}

-(BOOL)isReachableViaWWAN
{
  SCNetworkReachabilityFlags flags = 0;
  if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
  {
    // check we're REACHABLE
    if(flags & kSCNetworkReachabilityFlagsReachable)
    {
      // now, check we're on WWAN
      if(flags & kSCNetworkReachabilityFlagsIsWWAN)
      {
        return YES;
      }
    }
  }
  return NO;
}

-(BOOL)isReachableViaWiFi
{
  SCNetworkReachabilityFlags flags = 0;
  
  if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
  {
    // check we're reachable
    if((flags & kSCNetworkReachabilityFlagsReachable))
    {
      // check we're NOT on WWAN
      if((flags & kSCNetworkReachabilityFlagsIsWWAN))
      {
        return NO;
      }
      return YES;
    }
  }
  return NO;
}

#define testcase (kSCNetworkReachabilityFlagsConnectionRequired | kSCNetworkReachabilityFlagsTransientConnection)

-(BOOL)isReachableWithFlags:(SCNetworkReachabilityFlags)flags
{
  BOOL connectionUP = YES;
  
  if(!(flags & kSCNetworkReachabilityFlagsReachable))
    connectionUP = NO;
  
  if( (flags & testcase) == testcase )
    connectionUP = NO;
  if(flags & kSCNetworkReachabilityFlagsIsWWAN)
  {
    // we're on 3G
    if(!self.allowedDownloadOnWWAN)
    {
      //
      // we dont want to connect when on 3G
      connectionUP = NO;
    }
  }
  return connectionUP;
}

-(BOOL)isReachable
{
  SCNetworkReachabilityFlags flags;
  
  if(!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
    return NO;
  
  return [self isReachableWithFlags:flags];
}

#pragma mark-
#pragma mark tool  --  get disk space

+ (float)totalDiskSpaceInBytes {
  
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  
  struct statfs tStats;
  
  statfs([[paths lastObject] cStringUsingEncoding:NSUTF8StringEncoding], &tStats);
  
  float totalSpace = (float)(tStats.f_blocks * tStats.f_bsize);
  
  return totalSpace;
  
}

+ (float)freeDiskSpaceInBytes{
  struct statfs buf;
  long long freespace = -1;
  if(statfs("/var", &buf) >= 0){
    freespace = (long long)(buf.f_bsize * buf.f_bfree);
  }
  return freespace;
}

@end


NSString * const DQDownloadProgressChangedNotification  = @"DQDownloadProgressChangedNotification";

NSString * const DQDownloadStateChangedNotification     = @"DQDownloadStateChangedNotification";
