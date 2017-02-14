//
//  DownloadCell.m
//  DQDownload
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import "DownloadCell.h"

@interface DownloadCell ()

@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

@property (weak, nonatomic) IBOutlet UILabel        *progressLabel;

@property (weak, nonatomic) IBOutlet UILabel *speedLabel;


@end

@implementation DownloadCell

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(progressDidChange:)
                                                 name:DQDownloadProgressChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadStateDidChange:) name:DQDownloadStateChangedNotification object:nil];
}

- (void)setItem:(id<DQDownloadItemProtocol>)item
{
    _item = item;
    self.progressView.progress = [item downloadProgress];
    if ([item downloadSpeed]) {
        self.speedLabel.text       = [NSString stringWithFormat:@"%@/s",[item downloadSpeed]];
    }
    self.progressLabel.text    =  [NSString stringWithFormat:@"%.1fMB/%.1fMB",[item downloadedLength]/(1024*1024.0),[item totalLength]/(1024*1024.0)];
    self.textLabel.text = [item downloadUrl];
    switch ([item downloadState]) {
        case DQDownloadStateDownloading:
        {
            self.detailTextLabel.text = @"正在下载..";
        }
            break;
        case DQDownloadStatePaused:
        {
            self.detailTextLabel.text = @"暂停";
            self.speedLabel.text      = @"0kb/s";
        }
            break;
        case DQDownloadStateWaiting:
        {
            self.detailTextLabel.text = @"等待";
            self.speedLabel.text      = @"0kb/s";
        }
            break;
        case DQDownloadStateFailed:
        {
            self.detailTextLabel.text = @"下载失败";
            self.speedLabel.text      = @"0kb/s";
        }
            break;
        default:
            break;
    }
    if ([item downloadState] != DQDownloadStateDownloading) {
        self.speedLabel.hidden = YES;
    }
    else {
        self.speedLabel.hidden = NO;
    }

    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];
    self.detailTextLabel.textAlignment = NSTextAlignmentCenter;
    self.textLabel.frame       = CGRectMake(10, 10, [UIScreen mainScreen].bounds.size.width - 130, 20);
    self.detailTextLabel.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 80, 10, 70, 20);
    self.progressView.frame    = CGRectMake(10, 40, [UIScreen mainScreen].bounds.size.width - 160, 10);
    self.progressLabel.frame   = CGRectMake(20, 40, 120, 20);
    self.speedLabel.frame      = CGRectMake(CGRectGetMaxX(self.progressLabel.frame) + 30, 40, 100, 20);
}

- (void)downloadStateDidChange:(NSNotification *)notification
{
    id<DQDownloadItemProtocol> item = notification.object;
    if (![item isEqual:self.item]) {
        return;
    }
    switch ([item downloadState]) {
        case DQDownloadStateDownloading:
        {
            self.detailTextLabel.text = @"正在下载..";
        }
            break;
        case DQDownloadStatePaused:
        {
            self.detailTextLabel.text = @"暂停";
            self.speedLabel.text      = @"0kb/s";
        }
            break;
        case DQDownloadStateWaiting:
        {
            self.detailTextLabel.text = @"等待";
            self.speedLabel.text      = @"0kb/s";
        }
            break;
        case DQDownloadStateFailed:
        {
            self.detailTextLabel.text = @"下载失败";
            self.speedLabel.text      = @"0kb/s";
        }
            break;
        default:
            break;
    }
    
    if ([item downloadState] != DQDownloadStateDownloading) {
        self.speedLabel.hidden = YES;
    }
    else {
        self.speedLabel.hidden = NO;
    }
}

- (void)progressDidChange:(NSNotification *)notification
{
    id<DQDownloadItemProtocol> item = notification.object;
    if ([item isEqual:self.item]){
        self.progressView.progress = [item downloadProgress];
        if ([item downloadSpeed]) {
            self.speedLabel.text       = [NSString stringWithFormat:@"%@/s",[item downloadSpeed]];
        }
        self.progressLabel.text    =  [NSString stringWithFormat:@"%@/%@",[NSByteCountFormatter stringFromByteCount:[item downloadedLength] countStyle:NSByteCountFormatterCountStyleFile],[NSByteCountFormatter stringFromByteCount:[item totalLength] countStyle:NSByteCountFormatterCountStyleFile]];
    }
}

@end
