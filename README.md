# DQDownloadManager

## DQDownloadManager是基于NSURLSession的一个简单易用的并发下载组件

## 特点

- 支持在线/离线下载
- 支持断点下载
- 可控下载并发数
- 自动维护下载队列
- 可获取下载速度
- 下载状态：暂停、下载中、等待、下载失败
- 支持设置是否允许蜂窝移动网络下下载

## 示例

```objc
[DQDownloadManager sharedManager].allowedBackgroundDownload = YES;//设置是否允许后台下载 

[DQDownloadManager sharedManager].allowedDownloadOnWWAN = false;//设置是否允许蜂窝移动网络下下载 

[DQDownloadManager sharedManager].concurrentDownloadingCount = 3;//设置下载并发数

NSString *url = @"http://devstreaming.apple.com/videos/wwdc/2014/210xxksa9s9ewsa/210/210_hd_accessibility_on_ios.mov";
NSDictionary *extrasData = @{@"key":@"需要存入的附加信息"}
//开始一个下载任务
DQDownloadError error = [[DQDownloadManager sharedManager] startDownloadWithUrl:url extrasData:extrasData];

//获取正在下载的任务
NSArray<id<DQDownloadItemProtocol>> *currentDownloadingItems = [DQDownloadManager sharedManager].downloadingItems;

//获取已经下载完整的任务
NSArray<id<DQDownloadItemProtocol>> *downloadedItems = [DQDownloadManager sharedManager].downloadedItems;
```
- 详细使用请参照demo

## 安装

拷贝 `DQDownloadManager/` 目录下的两个文件 `DQDownloadManager.m` / `DQDownloadManager.h`  到项目里即可。

## 运行环境

- iOS 7+
- 支持 armv7/armv7s/arm64
