//
//  ZQChatMenuView.m
//  ZQChatTableView
//
//  Created by zzq on 2018/7/5.
//  Copyright © 2018年 zzq. All rights reserved.
//

#import "ZQChatMenuView.h"
#import "ZQMenuCell.h"
#import "ZQChatDefault.h"
#import "ZQMenuCollectionLayout.h"

#define margin  15
#define padding  15

static NSString *cellIdentify = @"ZQMenuCell";

@interface ZQChatMenuView() <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
{
    UIView *_lineView;
}

@property (nonatomic, strong) UICollectionView *collectionView;

@end

@implementation ZQChatMenuView

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self configUI];
    }
    return self;
}

- (void)configUI {
    ZQMenuCollectionLayout *layout = [[ZQMenuCollectionLayout alloc] init];
    layout.minimumLineSpacing = margin;
    layout.minimumInteritemSpacing = margin;
    layout.sectionInset = UIEdgeInsetsMake(padding, padding, padding, padding);
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    collectionView.delegate = self;
    collectionView.dataSource = self;
    collectionView.bounces = YES;
    collectionView.showsHorizontalScrollIndicator = NO;
    collectionView.pagingEnabled = YES;
    collectionView.scrollEnabled = YES;
    collectionView.backgroundColor = [UIColor groupTableViewBackgroundColor];
    [collectionView registerClass:[ZQMenuCell class] forCellWithReuseIdentifier:cellIdentify];

    [self addSubview:collectionView];
    self.collectionView = collectionView;
    
    UIView *lineView = [[UIView alloc] init];
    lineView.backgroundColor = [UIColor lightGrayColor];
    [self addSubview:lineView];
    
    _lineView = lineView;
}


- (void)layoutSubviews {
    [super layoutSubviews];
    self.collectionView.frame = self.bounds;
    _lineView.frame = CGRectMake(0, 0, self.bounds.size.width, 1);
}

- (void)reloadMenu {
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.menus.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ZQMenuCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellIdentify forIndexPath:indexPath];
    cell.item = self.menus[indexPath.row];
    return cell;
}

#pragma mark - UICollectionViewDelegate
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"tap cell");
    if (self.delegate && [self.delegate respondsToSelector:@selector(MenuViewDidSelectItem:)]) {
        [self.delegate MenuViewDidSelectItem:indexPath];
    }
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake((ZQScreenWidth - padding *2 - margin *3)/4, (self.bounds.size.height - padding *2 - margin)/2);
}

@end
