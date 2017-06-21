//
//  ViewController.m
//  DQDownloadManager
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import "ViewController.h"
#import "DQDownloadManager.h"
@interface ViewController ()<UITableViewDataSource,UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic,strong) NSArray *data;
@end

@implementation ViewController

#pragma mark- view live cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
    NSLog(@"%@",[[DQDownloadManager sharedManager] downloadDirectory]);
    [DQDownloadManager sharedManager].allowedBackgroundDownload = YES;//设置是否允许后台下载
    [DQDownloadManager sharedManager].allowedDownloadOnWWAN = false;//设置是否允许蜂窝移动网络下下载
}

#pragma mark- delegate
#pragma mark UITabelViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return self.data.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  static NSString *iden = @"ListCell";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:iden];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:iden];
  }
  cell.textLabel.text = self.data[indexPath.row];
  return cell;
}

#pragma mark UITabelViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  NSString *url = self.data[indexPath.row];
  DQDownloadError error = [[DQDownloadManager sharedManager] startDownloadWithUrl:url extrasData:@{@"index":@"需要存入的附加信息"}];
  if (error == DQDownloadErrorNone) {
    NSLog(@"已加入下载队列");
  }
  else if (error == DQDownloadErrorExisting) {
    NSLog(@"已经在下载队列");
  }
  else if (error == DQDownloadErrorNetworkNotReachable){
    NSLog(@"请检查网络");
  }
  else if (error == DQDownloadErrorUrlError) {
    NSLog(@"无效的下载地址");
  }
  else if (error == DQDownloadErrorWifiNotReachable) {
    NSLog(@"请连接Wifi");
  }
}

#pragma mark- getter
- (NSArray *)data
{
    if (!_data) {
        _data = @[
                  @"http://s9.knowsky.com/bizhi/l/35001-45000/200952904241438473283.jpg",
                  @"http://devstreaming.apple.com/videos/wwdc/2014/210xxksa9s9ewsa/210/210_sd_accessibility_on_ios.mov",
                  @"http://devstreaming.apple.com/videos/wwdc/2014/229xx77tq0pmkwo/229/229_sd_advanced_ios_architecture_and_patterns.mov",
                  @"http://devstreaming.apple.com/videos/wwdc/2014/404xxdxsstkaqjb/404/404_sd_advanced_swift.mov",
                  @"http://devstreaming.apple.com/videos/wwdc/2014/413xxr7gdc60u2p/413/413_sd_debugging_in_xcode_6.mov"];
    }
    return _data;
}

@end
