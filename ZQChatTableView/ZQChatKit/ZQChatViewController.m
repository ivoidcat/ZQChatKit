//
//  ZQChatViewController.m
//  ZQChatTableView
//
//  Created by zzq on 2018/6/29.
//  Copyright © 2018年 zzq. All rights reserved.
//

#import "ZQChatViewController.h"
#import "ZQVideoViewController.h"

#import "ZQMessageCell.h"
#import "ZQTextToolView.h"
#import "ZQChatMenuView.h"
#import "ZQVoiceRecordHUD.h"
#import "ZQRecordHelper.h"
#import "ZQAudioPlayer.h"

#import <Masonry/Masonry.h>
#import <MJRefresh/MJRefresh.h>

#import "UIScrollView+ZQkeyboardControl.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#define TextViewDefualtHeight 40

@interface ZQChatViewController ()
<UITableViewDelegate,
UITableViewDataSource,
UIImagePickerControllerDelegate,
UINavigationControllerDelegate,
ZQMessageInputViewDelegate,
ZQMessageCellDelegate,
ZQChatMenuViewDelegate,
ZQRecordVideoDelegate>

@property (weak, nonatomic) IBOutlet UIView *bottomToolView;

@property (nonatomic, strong) ZQTextToolView *textMessageView;
@property (nonatomic, strong) ZQChatMenuView *menuView;
@property (nonatomic, strong) ZQVoiceRecordHUD *recordHud;
@property (nonatomic, strong) ZQRecordHelper *recordHelper;
@property (nonatomic, strong) NSString *getRecorderPath;


@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolBottomLayout;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolHeightLayout;

@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, weak) ZQMessageCell *selectedTableCell;

@property (nonatomic, assign) ZQChatInputViewType inputViewType;

/**
 *  记录旧的textView contentSize Heigth
 */
@property (nonatomic, assign) CGFloat previousTextViewContentHeight;
/**
 *  判断是不是超出了录音最大时长
 */
@property (nonatomic) BOOL isMaxTimeStop;

@end

@implementation ZQChatViewController

- (void)dealloc {
    NSLog(@"聊天界面已释放");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 设置键盘通知或者手势控制键盘消失
    [self.tableview setupPanGestureControlKeyboardHide:NO];
    
    // KVO 检查contentSize
    [self.textMessageView.inputTextView addObserver:self
                                          forKeyPath:@"contentSize"
                                             options:NSKeyValueObservingOptionNew
                                             context:nil];
    
    [self.textMessageView.inputTextView setEditable:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // remove键盘通知或者手势
    [self.tableview disSetupPanGestureControlKeyboardHide:NO];
    
    // remove KVO
    [self.textMessageView.inputTextView removeObserver:self forKeyPath:@"contentSize"];
    [self.textMessageView.inputTextView setEditable:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self configUI];
    [self addKeyboardAction];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.tableview.backgroundColor = self.backViewColor;
}

#pragma mark - Config UI
- (void)configUI {
    [self configTableView];
    
    [self addRefreshHeader];
    [self addTextView];
    [self addMenuView];
    
    
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewDidTap:)];
    [self.tableview addGestureRecognizer:self.tapGesture];
    
    self.automaticallyAdjustsScrollViewInsets = NO;
}

- (void)configTableView {
    self.delegate = self;
    self.tableview.delegate = self;
    self.tableview.dataSource = self;
    self.tableview.estimatedRowHeight = 0;
    self.tableview.estimatedSectionHeaderHeight = 0;
    self.tableview.estimatedSectionFooterHeight = 0;
    [self.tableview registerClass:[ZQMessageCell class] forCellReuseIdentifier:NSStringFromClass([ZQMessageCell class])];
}

- (void)addRefreshHeader {
    if (self.delegate && [self.delegate respondsToSelector:@selector(shouldLoadMoreMessagesScrollToTop)]) {
        if ([self.delegate shouldLoadMoreMessagesScrollToTop]) {
            WEAKSELF
            MJRefreshNormalHeader *header = [MJRefreshNormalHeader headerWithRefreshingBlock:^{
                if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(loadMoreMessagesScrollTotop)]) {
                    [weakSelf.delegate loadMoreMessagesScrollTotop];
                }
            }];
            header.lastUpdatedTimeLabel.hidden = YES;
            header.stateLabel.hidden = YES;
            self.tableview.mj_header = header;
        }
    }
}

- (void)addTextView {
    ZQTextToolView *textView = [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([ZQTextToolView class]) owner:nil options:nil].firstObject;
    textView.recordButton.alpha = 0;
    textView.delegate = self;
    [self.bottomToolView addSubview:textView];
    [textView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.bottom.right.equalTo(self.bottomToolView);
    }];
    self.textMessageView = textView;
}

- (void)addMenuView {
    ZQChatMenuView *menuView = [ZQChatMenuView new];
    menuView.delegate = self;
    if (self.delegate && [self.delegate respondsToSelector:@selector(loadCustomMenus)]) {
        menuView.menus = [self.delegate loadCustomMenus].copy;
    } else {
        NSArray *titles = @[@"拍照",@"照片",@"视频"];
        NSArray *icons = @[@"sharemore_video",@"sharemore_pic", @"sharemore_myfav"];
        NSMutableArray *menus = [NSMutableArray array];
        for (int i = 0; i < titles.count; ++i) {
            ZQMenuItem *item = [ZQMenuItem new];
            item.title = titles[i];
            item.imgName = icons[i];
            [menus addObject:item];
        }
        menuView.menus = [menus copy];
    }
    menuView.alpha = 0;
    [self.view addSubview:menuView];
    [menuView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.view);
        make.top.equalTo(self.bottomToolView.mas_bottom);
        make.height.mas_equalTo(@200);
    }];
    self.menuView = menuView;
    
    self.inputViewType = ZQChatInputViewTypeNormal;
}


- (void)addKeyboardAction {
    WEAKSELF
    self.tableview.keyboardWillChange = ^(CGRect keyboardRect, UIViewAnimationOptions options, double duration, BOOL showKeyboard) {
        [weakSelf.view layoutIfNeeded];
        [UIView animateWithDuration:duration
                              delay:0.0
                            options:options
                         animations:^{
                             
                             if (weakSelf.inputViewType != ZQChatInputViewTypeTool) {
                                 weakSelf.toolBottomLayout.constant = showKeyboard ? keyboardRect.size.height : 0;
                                 
                                 [weakSelf.view layoutIfNeeded];

                                 if (showKeyboard) {
                                     [weakSelf scrollToBottomAnimated:NO];
                                 }
                             }
                         }
                         completion:nil];
    };
}

#pragma mark - UITableViewDataSource
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.chatModel.dataSource.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZQMessageFrame *frame = self.chatModel.dataSource[indexPath.row];
    return frame.cellHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZQMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([ZQMessageCell class]) forIndexPath:indexPath];
    cell.senderTextColor = self.senderTextColor;
    cell.reciveTextColor = self.reciveTextColor;
    cell.senderBubbleImage = self.senderBubbleImage;
    cell.reciveBubbleImage = self.reciveBubbleImage;
    cell.senderAvatarImage = self.senderAvatarImage;
    cell.reciveAvatarImage = self.reciveAvatarImage;
    cell.delegate = self;
    
    cell.messageFrame = self.chatModel.dataSource[indexPath.row];
    return cell;
}

#pragma mark - UITableViewDelegate
//- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
//    [UIView performWithoutAnimation:^{
//        [cell layoutIfNeeded];
//    }];
//}

#pragma mark - public methods
- (void)reloadChatView {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableview reloadData];
        [self scrollToBottomAnimated:YES];
    });
}

- (void)headerRefreshEnd {
    [self.tableview.mj_header endRefreshing];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    
    NSInteger rows = [self.tableview numberOfRowsInSection:0];
    
    if (rows > 0) {
        [self.tableview scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:0]
                              atScrollPosition:UITableViewScrollPositionBottom
                                      animated:animated];
    }
}

#pragma mark - Key-value Observing

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (object == self.textMessageView.inputTextView && [keyPath isEqualToString:@"contentSize"]) {
        [self layoutAndAnimateMessageInputTextView:object];
    }
}

#pragma mark - UITextView Helper Method

- (CGFloat)getTextViewContentH:(UITextView *)textView {
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0) {
        return [textView sizeThatFits:CGSizeMake(CGRectGetWidth(textView.frame), MAXFLOAT)].height;
    } else {
        return textView.contentSize.height;
    }
}

#pragma mark - Layout Message Input View Helper Method

- (void)layoutAndAnimateMessageInputTextView:(UITextView *)textView {
    
    CGFloat maxHeight = [ZQTextToolView maxHeight];
    
    CGFloat contentH = [self getTextViewContentH:textView];
    
    BOOL isShrinking = contentH < self.previousTextViewContentHeight;
    CGFloat changeInHeight = contentH - self.previousTextViewContentHeight;
    
    if (!isShrinking && (self.previousTextViewContentHeight == maxHeight || contentH <= TextViewDefualtHeight)) {
        changeInHeight = 0;
    }
    else {
        changeInHeight = MIN(changeInHeight, maxHeight - self.previousTextViewContentHeight);
    }
    
    if (changeInHeight != 0.0f) {
        [self.view layoutIfNeeded];
        [UIView animateWithDuration:0.25f
                         animations:^{
                             [self scrollToBottomAnimated:NO];
                             self.toolHeightLayout.constant = MAX(contentH, TextViewDefualtHeight)  + 10;
                             [self.view layoutIfNeeded];
                         }
                         completion:nil];
        
        self.previousTextViewContentHeight = MIN(contentH, maxHeight);
    }
}

- (void)menuViewNeedHide:(BOOL)nHide {
    if (nHide && self.inputViewType == ZQChatInputViewTypeTool) {
        [self.textMessageView.inputTextView becomeFirstResponder];
    } else if (!nHide && self.inputViewType == ZQChatInputViewTypeTool) {
        [self showVoiceView:NO];
        [self.textMessageView.inputTextView resignFirstResponder];
    }
    
    if (nHide) {
        // hide
        [self.view layoutIfNeeded];
        [UIView animateWithDuration:0.25f animations:^{
            self.menuView.alpha = 0;
            if (self.inputViewType == ZQChatInputViewTypeNormal) {
                self.toolBottomLayout.constant = 0;
            }
            [self.view layoutIfNeeded];
        } completion:nil];
    } else {
        // show
        [self.view layoutIfNeeded];
        [UIView animateWithDuration:0.25f animations:^{
            self.menuView.alpha = 1;
            self.toolBottomLayout.constant = CGRectGetHeight(self.menuView.frame);
            [self.view layoutIfNeeded];
            
            [self scrollToBottomAnimated:NO];
        } completion:nil];
    }
}

- (void)showVoiceView:(BOOL)show {
    if (!show && self.inputViewType == ZQChatInputViewTypeVoice) {
        [self.textMessageView.inputTextView becomeFirstResponder];
    }
    
    if (show) {
        [self.textMessageView.inputTextView resignFirstResponder];
        [self menuViewNeedHide:YES];
        
        [self.view layoutIfNeeded];
        [UIView animateWithDuration:0.25 animations:^{
            self.textMessageView.inputTextView.alpha = 0;
            self.textMessageView.recordButton.alpha = 1;
            self.toolBottomLayout.constant = 0;
            [self.view layoutIfNeeded];
        }];
    } else {
        [self.view layoutIfNeeded];
        [UIView animateWithDuration:0.25 animations:^{
            self.textMessageView.inputTextView.alpha = 1;
            self.textMessageView.recordButton.alpha = 0;
            [self.view layoutIfNeeded];
        }];
    }
}

- (void)viewDidTap:(UITapGestureRecognizer *)tap {
    if (self.inputViewType == ZQChatInputViewTypeVoice) {
        return;
    }
    if (self.inputViewType == ZQChatInputViewTypeTool) {
        [self menuViewNeedHide:YES];
    }
    self.inputViewType = ZQInputViewTypeNormal;
    [self.textMessageView.inputTextView resignFirstResponder];
}

- (void)showPhotoWithSourceType:(BOOL)isCamera {
    if (isCamera && ![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        return;
    }
    if (!isCamera && ![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = isCamera ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - ZQMessageInputViewDelegate
- (void)inputTextViewWillBeginEditing:(ZQMessageTextView *)messageInputTextView {
    self.inputViewType = ZQChatInputViewTypeText;
    [self menuViewNeedHide:YES];
}

- (void)inputTextViewDidBeginEditing:(ZQMessageTextView *)messageInputTextView {
    if (!self.previousTextViewContentHeight)
        self.previousTextViewContentHeight = MAX([self getTextViewContentH:messageInputTextView], TextViewDefualtHeight) ;
}

- (void)didSendTextAction:(NSString *)text {
    //发送按钮
    NSLog(@"点击了发送按钮");
    self.textMessageView.inputTextView.text = @"";
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(didSendText:fromSender:onDate:)]) {
        [self.delegate didSendText:text fromSender:self.chatModel.senderName onDate:[NSDate date]];
    }
}

- (void)didSelectedMultipleMediaAction {
    if (self.inputViewType != ZQChatInputViewTypeTool) {
        self.inputViewType = ZQChatInputViewTypeTool;
        [self menuViewNeedHide:NO];
    } else {
        [self menuViewNeedHide:YES];
    }
}

- (void)didSelectedVoiceMediaAction {
    if (self.inputViewType != ZQChatInputViewTypeVoice) {
        self.inputViewType = ZQChatInputViewTypeVoice;
        [self showVoiceView:YES];
    } else {
        [self showVoiceView:NO];
    }
}

- (void)prepareRecordingVoiceActionWithCompletion:(BOOL (^)(void))completion {
    [self prepareRecordWithCompletion:completion];
}

- (void)didStartRecordingVoiceAction {
    [self startRecord];
}

- (void)didCancelRecordingVoiceAction {
    [self cancelRecord];
}

- (void)didFinishRecoingVoiceAction {
    if (self.isMaxTimeStop == NO) {
        [self finishRecorded];
    } else {
        self.isMaxTimeStop = NO;
    }
}

- (void)didDragOutsideAction {
    [self pauseRecord];
}

- (void)didDragInsideAction {
    [self resumeRecord];
}

- (void)viewDidPan {
    [self viewDidTap:nil];
}

#pragma mark - Voice Recording Helper Method

- (void)prepareRecordWithCompletion:(ZQPrepareRecorderCompletion)completion {
    [self.voiceRecordHelper prepareRecordingWithPath:[self getRecorderPath] prepareRecorderCompletion:completion];
}

- (void)startRecord {
    [self.recordHud startRecordingHUDAtView:self.view];
    [self.voiceRecordHelper startRecordingWithStartRecorderCompletion:^{
    }];
}

- (void)finishRecorded {
    WEAKSELF
    [self.recordHud stopRecordCompled:^(BOOL fnished) {
        weakSelf.recordHud = nil;
    }];
    [self.voiceRecordHelper stopRecordingWithStopRecorderCompletion:^{
        if ([weakSelf.delegate respondsToSelector:@selector(didSendVoice:voiceDuration:fromSender:onDate:)]) {
            [weakSelf.delegate didSendVoice:weakSelf.recordHelper.recordPath voiceDuration:weakSelf.recordHelper.recordDuration.intValue fromSender:weakSelf.chatModel.senderName onDate:[NSDate date]];
        }
    }];
}

- (void)pauseRecord {
    [self.recordHud pauseRecord];
}

- (void)resumeRecord {
    [self.recordHud resaueRecord];
}

- (void)cancelRecord {
    WEAKSELF
    [self.recordHud cancelRecordCompled:^(BOOL fnished) {
        weakSelf.recordHud = nil;
    }];
    [self.voiceRecordHelper cancelledDeleteWithCompletion:^{
        
    }];
}


#pragma mark - ZQMessageCellDelegate

- (void)chatCell:(ZQMessageCell *)cell headImageDidClick:(NSString *)userId {
    if (self.delegate && [self.delegate respondsToSelector:@selector(didSelectedAvatar:)]) {
        [self.delegate didSelectedAvatar:cell.messageFrame.message];
    }
}

- (void)chatCell:(ZQMessageCell *)cell contentButtonClick:(NSString *)userId {
    [self.textMessageView.inputView resignFirstResponder];
    NSLog(@"点击了图片内容");
}

- (void)chatCell:(ZQMessageCell *)cell voiceButtonClick:(NSString *)userId {
    //没有选中其他cell
    if (!self.selectedTableCell) {
        self.selectedTableCell = cell;
    //没有播放完，选中了同一个cell
    } else if (self.selectedTableCell && self.selectedTableCell == cell) {
        [[ZQAudioPlayer sharedInstance] stopSound];
        [self.selectedTableCell.btnContent.animationVoiceImageView stopAnimating];
        self.selectedTableCell = nil;
    //没有播放完，选中了其他cell
    } else if (self.selectedTableCell && self.selectedTableCell != cell) {
        [self.selectedTableCell.btnContent.animationVoiceImageView stopAnimating];
        self.selectedTableCell = cell;
    }
}

- (void)chatCell:(ZQMessageCell *)cell voiceDidFinish:(NSString *)userId {
    self.selectedTableCell = nil;
}

- (void)chatCell:(ZQMessageCell *)cell videoButtonClick:(NSString *)userId {
    ZQMessage *message = cell.messageFrame.message;
    NSURL *url = [NSURL fileURLWithPath:message.videoPath];
    
    AVPlayerViewController *vc = [[AVPlayerViewController alloc] init];
    vc.player = [[AVPlayer alloc] initWithURL:url];
    [vc.player play];
    
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)chatCell:(ZQMessageCell *)cell failureButton:(ZQLoadingButton *)button Clicked:(NSString *)userId {
    if (self.delegate && [self.delegate respondsToSelector:@selector(didFailureButton:Clicked:)]) {
        [self.delegate didFailureButton:button Clicked:cell.messageFrame.message];
    }
}

#pragma mark - ZQChatMenuViewDelegate
- (void)MenuViewDidSelectItem:(NSIndexPath *)indexPath {
    if (self.delegate && [self.delegate respondsToSelector:@selector(customMenusDidSelectItem:)]) {
        [self.delegate customMenusDidSelectItem:indexPath];
    } else {
        //默认
        switch (indexPath.item) {
            case 0: {
                //拍照
                NSLog(@"点击了拍照");
                [self showPhotoWithSourceType:YES];
            }
                
                break;
            case 1: {
                //相册
                NSLog(@"点击了相册");
                [self showPhotoWithSourceType:NO];
            }
                
                break;
            case 2: {
                //视频
                NSLog(@"点击了视频");
                [self viewDidTap:nil];
                ZQVideoViewController *vc = [ZQVideoViewController new];
                vc.delegate = self;
                [self presentViewController:vc animated:YES completion:nil];
            }
                break;

            default:
                break;
        }
    }
}

#pragma mark - UIImagePickerViewDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (self.delegate && [self.delegate respondsToSelector:@selector(didSendPhoto:fromSender:onDate:)]) {
        [self.delegate didSendPhoto:image fromSender:self.chatModel.senderName onDate:[NSDate date]];
    }
}

#pragma mark - ZQRecordVideoDelegate
- (void)didRecordVideoFinished:(NSString *)videoPath {
    if (self.delegate && [self.delegate respondsToSelector:@selector(didSendVideoConverPhoto:videoPath:fromSender:onDate:)]) {
        
        [self.delegate didSendVideoConverPhoto:nil videoPath:videoPath fromSender:self.chatModel.senderName onDate:[NSDate date]];
    }
    
}

#pragma mark - getter & setter
- (ZQVoiceRecordHUD *)recordHud {
    if (!_recordHud) {
        _recordHud = [[ZQVoiceRecordHUD alloc] initWithFrame:CGRectMake(0, 0, 140, 140)];
    }
    return _recordHud;
}

- (ZQRecordHelper *)voiceRecordHelper {
    if (!_recordHelper) {
        _isMaxTimeStop = NO;
        
        WEAKSELF
        _recordHelper = [[ZQRecordHelper alloc] init];
        _recordHelper.maxTimeStopRecorderCompletion = ^{
            // Unselect and unhilight the hold down button, and set isMaxTimeStop to YES.
            UIButton *holdDown = weakSelf.textMessageView.recordButton;
            holdDown.selected = NO;
            holdDown.highlighted = NO;
            weakSelf.isMaxTimeStop = YES;
            
            [weakSelf finishRecorded];
        };
        _recordHelper.peakPowerForChannel = ^(float peakPowerForChannel) {
            weakSelf.recordHud.peakPower = peakPowerForChannel;
        };
        _recordHelper.maxRecordTime = 60;
    }
    return _recordHelper;
}

- (NSString *)getRecorderPath {
    NSString *recorderPath = nil;
    recorderPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    NSDate *now = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyyMMddHHmmssSSS"];
    recorderPath = [recorderPath stringByAppendingFormat:@"%@-MySound.m4a", [dateFormatter stringFromDate:now]];
    return recorderPath;
}

- (UIColor *)senderTextColor {
    if (_senderTextColor == nil) {
        return ZQConfigStyle.senderDefualtColor;
    }
    return _senderTextColor;
}

- (UIColor *)reciveTextColor {
    if (_reciveTextColor == nil) {
        return ZQConfigStyle.reciveDefualtColor;
    }
    return _reciveTextColor;
}

- (UIColor *)backViewColor {
    if (_backViewColor == nil) {
        return ZQConfigStyle.backgroudDefualtColor;
    }
    return _backViewColor;
}

- (UIImage *)senderBubbleImage {
    if (_senderBubbleImage == nil) {
        return ZQConfigStyle.senderBubbleDefualtImage;
    }
    return _senderBubbleImage;
}

- (UIImage *)reciveBubbleImage {
    if (_reciveBubbleImage == nil) {
        return ZQConfigStyle.reciveBubbleDefualtImage;
    }
    return _reciveBubbleImage;
}

- (UIImage *)senderAvatarImage {
    if (_senderAvatarImage == nil) {
        return ZQConfigStyle.senderDefualtAvatar;
    }
    return _senderAvatarImage;
}

- (UIImage *)reciveAvatarImage {
    if (_reciveAvatarImage == nil) {
        return ZQConfigStyle.reciveDefualtAvatar;
    }
    return _reciveAvatarImage;
}

@end
