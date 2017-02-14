//
//  DownloadViewController.m
//  DQDownload
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import "DownloadViewController.h"
#import "DQDownloadManager.h"
#import "DownloadCell.h"
@interface DownloadViewController ()<UITableViewDelegate,UITableViewDataSource>

@property (weak, nonatomic) IBOutlet UITableView            *tableView;
@property (weak, nonatomic) IBOutlet UISegmentedControl     *segmentedControl;
@property (weak, nonatomic) IBOutlet UIBarButtonItem        *deleteButton;
@property (weak, nonatomic) IBOutlet UIView                 *topView;
@property (weak, nonatomic) IBOutlet UILabel                *diskSpace;


@end

@implementation DownloadViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.diskSpace.text       = self.diskSpaceInfo;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadDidFinish:) name:DQDownloadStateChangedNotification object:nil];
}

#pragma mark- delegate
#pragma mark UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_segmentedControl.selectedSegmentIndex == 0) {
        return DQDownloadManager.sharedManager.downloadingItems.count;
    }
    else {
        return DQDownloadManager.sharedManager.downloadedItems.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *iden = @"ListCell";
    DownloadCell *cell = [tableView dequeueReusableCellWithIdentifier:iden];
    if (!cell) {
        cell = [[[NSBundle mainBundle]loadNibNamed:@"DownloadCell" owner:self options:nil]lastObject];
    }
    id<DQDownloadItemProtocol> item = nil;
    cell.progressView.hidden        = _segmentedControl.selectedSegmentIndex;
    cell.progressLabel.hidden       = _segmentedControl.selectedSegmentIndex;
    cell.speedLabel.hidden          = _segmentedControl.selectedSegmentIndex;
    cell.detailTextLabel.hidden     = _segmentedControl.selectedSegmentIndex;
    if (_segmentedControl.selectedSegmentIndex == 1) {
        if ([DQDownloadManager sharedManager].downloadedItems.count) {
            item = [DQDownloadManager sharedManager].downloadedItems[indexPath.row];
        }
    }
    else {
        if ([DQDownloadManager sharedManager].downloadingItems.count) {
            item = [DQDownloadManager sharedManager].downloadingItems[indexPath.row];
        }
    }
    cell.item = item;
    return cell;
}

#pragma mark UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_segmentedControl.selectedSegmentIndex == 1) {
        return;
    }
    id<DQDownloadItemProtocol> item = [DQDownloadManager sharedManager].downloadingItems[indexPath.row];
    switch ([item downloadState]) {
        case DQDownloadStateDownloading:
            [[DQDownloadManager sharedManager] pauseDownloadTaskWithUrl:[item downloadUrl]];
            break;
        case DQDownloadStateFailed:
        case DQDownloadStateWaiting:
        case DQDownloadStatePaused:
        {
            DQDownloadError  error = [[DQDownloadManager sharedManager] resumeDownloadTaskWithUrl:[item downloadUrl]];
            if (error == DQDownloadErrorNone) {
                return;
            }
            else if (error == DQDownloadErrorNetworkNotReachable) {
                NSLog(@"请检查网络");
            }
            else if (error == DQDownloadErrorWifiNotReachable) {
                NSLog(@"请连接Wifi");
            }
        }
             break;
        default:
            break;
    }
}


- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return  UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    id<DQDownloadItemProtocol> item = nil;
    if (_segmentedControl.selectedSegmentIndex) {
        item = [DQDownloadManager sharedManager].downloadedItems[indexPath.row];
    }
    else {
        item = [DQDownloadManager sharedManager].downloadingItems[indexPath.row];
    }
    [[DQDownloadManager sharedManager] deleteDownloadWithUrl:[item downloadUrl]];
    [tableView beginUpdates];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    [tableView endUpdates];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return @"删除";
}

#pragma mark UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(buttonIndex == 0) {
        return;
    } else {
        if (_segmentedControl.selectedSegmentIndex == 0) {
            [[DQDownloadManager sharedManager] deleteAllDownloadingTask];
            [self.tableView reloadData];
        }
        else {
            [[DQDownloadManager sharedManager] deleteAllDownloadedFile];
            [self.tableView reloadData];
        }
    }
}


#pragma mark- action
- (IBAction)pauseOrResumeAll:(UIButton *)sender
{
    sender.selected = !sender.selected;
    if (sender.selected) {
        [[DQDownloadManager sharedManager] pauseAllDownloadTask];
    }
    else {
        DQDownloadError error = [[DQDownloadManager sharedManager] resumeAllDownloadTask];
        if (error == DQDownloadErrorNetworkNotReachable) {
            NSLog(@"请检查网络");
        } else if (error == DQDownloadErrorWifiNotReachable) {
            NSLog(@"请连接Wifi");
        }
    }
}

- (IBAction)segmentedControlAction:(UISegmentedControl *)sender
{
    _topView.hidden = sender.selectedSegmentIndex;
    [UIView animateWithDuration:.3 animations:^{
        _tableView.frame = CGRectMake(0, sender.selectedSegmentIndex?64:94,[UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height - (sender.selectedSegmentIndex?64:94));
    } completion:^(BOOL finished) {
    }];
    [_tableView reloadData];
}

- (IBAction)deleteAllAction:(UIBarButtonItem *)sender
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"提示" message:@"删除全部" delegate:self cancelButtonTitle:@"关闭" otherButtonTitles:@"确定", nil];
    [alert show];
}

- (void)downloadDidFinish:(NSNotification *)notification
{
    id<DQDownloadItemProtocol> item = notification.object;
    if (item.downloadState == DQDownloadStateFinished) {
        NSInteger index = [notification.userInfo[@"index"] integerValue];
        [self.tableView beginUpdates];
        [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
        [self.tableView endUpdates];
    }
}

#pragma mark- getter
- (NSString *)diskSpaceInfo
{
    NSString *totalSpace = [NSString stringWithFormat:@"可用:%.1fG",[DQDownloadManager totalDiskSpaceInBytes]/1024/1024/1024];
    NSString *freeSpace ;
    float free = [DQDownloadManager freeDiskSpaceInBytes]/1024/1024/1024;
    if (free < 1) {
        freeSpace = [NSString stringWithFormat:@"剩余:%.1fM",[DQDownloadManager freeDiskSpaceInBytes]/1024/1024];
    }
    else {
        freeSpace = [NSString stringWithFormat:@"剩余:%.1fG",free];
    }
    return [NSString stringWithFormat:@"%@/%@",freeSpace,totalSpace];
}

@end
