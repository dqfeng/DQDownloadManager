//
//  DownloadCell.h
//  DQDownloadManager
//
//  Created by dqfeng   on 15/6/23.
//  Copyright (c) 2015年 dqfeng. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DQDownloadManager.h"
@interface DownloadCell : UITableViewCell
@property (weak, nonatomic,readonly) UIProgressView *progressView;

@property (weak, nonatomic,readonly) UILabel *progressLabel;
@property (weak, nonatomic,readonly) UILabel *speedLabel;

@property (nonatomic,strong) id<DQDownloadItemProtocol> item;

@end
