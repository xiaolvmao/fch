/*
 * App 主界面：填一条通话记录，点「添加记录」直接写进系统通话记录库。
 *
 * 约定：
 * 1. 控件（分段控件、日期选择器、按钮）都是常驻实例，任何控件的动作里都不重建表格。
 * 2. 结果用底部横幅提示，系统绿／系统红，不弹对话框打断操作。
 * 3. 随机时长范围显示成小胶囊（10 – 20），点数字时滚轮以气泡形式从点的地方弹出。
 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>
#import <ContactsUI/ContactsUI.h>

#include "pkgid.h"
#import "FCLRootController.h"
#import "FCLStore.h"

typedef NS_ENUM(NSInteger, FCLDirection) {
    FCLDirectionOutgoing = 0,
    FCLDirectionIncoming,
    FCLDirectionMissed,
};

static const NSInteger FCLSecondsUpperBound = 3600;
static const NSInteger FCLSecondsLowerBound = 1;

#pragma mark - 收藏的存储

/* App 没有数据容器，收藏放在偏好目录下一个自己的 plist 里。 */
static NSString *FCLFavoritesPath(void) {
    return @"/var/mobile/Library/Preferences/" FCL_PACKAGE_ID ".favorites.plist";
}

static NSArray *FCLLoadFavorites(void) {
    NSArray *items = [NSArray arrayWithContentsOfFile:FCLFavoritesPath()];
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

static void FCLSaveFavorites(NSArray *items) {
    [items writeToFile:FCLFavoritesPath() atomically:YES];
}

#pragma mark - 数值滚轮（气泡里只有这一个滚轮）

@interface FCLNumberWheelController : UIViewController <UIPickerViewDataSource, UIPickerViewDelegate>
@property (nonatomic, assign) NSInteger value;
@property (nonatomic, copy) void (^onChange)(NSInteger value);
@end

@implementation FCLNumberWheelController {
    UIPickerView *_picker;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    _picker = [[UIPickerView alloc] initWithFrame:self.view.bounds];
    _picker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _picker.dataSource = self;
    _picker.delegate = self;
    [self.view addSubview:_picker];

    NSInteger value = MAX(FCLSecondsLowerBound, MIN(self.value, FCLSecondsUpperBound));
    [_picker selectRow:value - FCLSecondsLowerBound inComponent:0 animated:NO];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return FCLSecondsUpperBound - FCLSecondsLowerBound + 1;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return [NSString stringWithFormat:@"%ld", (long)(row + FCLSecondsLowerBound)];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (self.onChange) self.onChange(row + FCLSecondsLowerBound);
}

@end

#pragma mark - 收藏列表

@interface FCLFavoritesController : UITableViewController
@property (nonatomic, copy) NSArray *favorites;
@property (nonatomic, copy) NSString *currentName;
@property (nonatomic, copy) NSString *currentNumber;
@property (nonatomic, copy) void (^onPick)(NSString *name, NSString *number);
@property (nonatomic, copy) void (^onFavoritesChanged)(NSArray *favorites);
@end

@implementation FCLFavoritesController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"收藏";
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.favorites.count ? (NSInteger)self.favorites.count : 1;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"已收藏" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"点一条填入号码；向左滑可以删除。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"FCLFavCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    }
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textAlignment = NSTextAlignmentNatural;

    if (indexPath.section == 0) {
        if (self.favorites.count == 0) {
            cell.textLabel.text = @"还没有收藏";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.detailTextLabel.text = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        NSDictionary *item = self.favorites[indexPath.row];
        NSString *name = item[@"name"];
        NSString *number = item[@"number"];
        cell.textLabel.text = name.length ? name : number;
        cell.detailTextLabel.text = name.length ? number : nil;
        return cell;
    }

    BOOL canAdd = self.currentNumber.length > 0;
    cell.textLabel.text = canAdd ? @"把当前号码加入收藏" : @"先填写电话号码再收藏";
    cell.textLabel.textColor = canAdd ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = canAdd ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (self.favorites.count == 0) return;
        NSDictionary *item = self.favorites[indexPath.row];
        if (self.onPick) self.onPick(item[@"name"] ?: @"", item[@"number"] ?: @"");
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    if (self.currentNumber.length == 0) return;
    NSMutableArray *items = [self.favorites mutableCopy] ?: [NSMutableArray array];
    for (NSDictionary *existing in items) {
        if ([existing[@"number"] isEqualToString:self.currentNumber]) return; /* 已经收过了 */
    }
    [items insertObject:@{@"name": self.currentName ?: @"", @"number": self.currentNumber} atIndex:0];
    self.favorites = items;
    FCLSaveFavorites(items);
    if (self.onFavoritesChanged) self.onFavoritesChanged(items);
    [tableView reloadData];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 || self.favorites.count == 0) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                title:@"删除"
                                              handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        (void)action; (void)sourceView;
        FCLFavoritesController *strongSelf = weakSelf;
        if (!strongSelf) { completion(NO); return; }
        NSMutableArray *items = [strongSelf.favorites mutableCopy];
        if (indexPath.row < (NSInteger)items.count) [items removeObjectAtIndex:indexPath.row];
        strongSelf.favorites = items;
        FCLSaveFavorites(items);
        if (strongSelf.onFavoritesChanged) strongSelf.onFavoritesChanged(items);
        [strongSelf.tableView deleteRowsAtIndexPaths:@[indexPath]
                                    withRowAnimation:UITableViewRowAnimationAutomatic];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

@end

#pragma mark - 主界面

@interface FCLRootController () <UITableViewDataSource, UITableViewDelegate, CNContactPickerDelegate,
                                 UIPopoverPresentationControllerDelegate>
@end

@implementation FCLRootController {
    UITableView *_tableView;
    UITextField *_addressField;
    UITextField *_durationField;
    UIButton *_rangeMinButton;
    UIButton *_rangeMaxButton;
    UIView *_rangeAccessory;
    UIDatePicker *_datePicker;
    UISegmentedControl *_directionControl;
    UIView *_banner;
    UILabel *_bannerLabel;
    __weak UITableViewCell *_submitCell;
    __weak UITableViewCell *_durationCell;
    __weak UITableViewCell *_rangeCell;
    __weak UITableViewCell *_favoritesCell;
    NSString *_address;
    NSString *_contactName;
    NSDate *_callDate;
    NSInteger _rangeMinimum;
    NSInteger _rangeMaximum;
    BOOL _submitting;
    NSInteger _bannerToken;
}

- (instancetype)init {
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.title = @"添加通话记录";
        _callDate = [NSDate date];
        _rangeMinimum = 10;
        _rangeMaximum = 20;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:_tableView];

    [self setupBanner];
}

#pragma mark 横幅提示

- (void)setupBanner {
    _banner = [[UIView alloc] init];
    _banner.translatesAutoresizingMaskIntoConstraints = NO;
    _banner.layer.cornerRadius = 12;
    _banner.alpha = 0;
    _banner.hidden = YES;
    _banner.userInteractionEnabled = NO;

    _bannerLabel = [[UILabel alloc] init];
    _bannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerLabel.numberOfLines = 0;
    _bannerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _bannerLabel.textColor = [UIColor whiteColor];
    _bannerLabel.textAlignment = NSTextAlignmentCenter;
    [_banner addSubview:_bannerLabel];
    [self.view addSubview:_banner];

    [NSLayoutConstraint activateConstraints:@[
        [_banner.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [_banner.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [_banner.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [_bannerLabel.leadingAnchor constraintEqualToAnchor:_banner.leadingAnchor constant:14],
        [_bannerLabel.trailingAnchor constraintEqualToAnchor:_banner.trailingAnchor constant:-14],
        [_bannerLabel.topAnchor constraintEqualToAnchor:_banner.topAnchor constant:10],
        [_bannerLabel.bottomAnchor constraintEqualToAnchor:_banner.bottomAnchor constant:-10],
    ]];
}

- (void)showBanner:(NSString *)text success:(BOOL)success {
    _bannerToken++;
    NSInteger token = _bannerToken;

    _bannerLabel.text = text;
    _banner.backgroundColor = success ? [UIColor systemGreenColor] : [UIColor systemRedColor];
    _banner.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{
        self->_banner.alpha = 1;
    }];

    __weak typeof(self) weakSelf = self;
    int64_t delay = (int64_t)((success ? 2.5 : 4.0) * NSEC_PER_SEC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_bannerToken != token) return;
        [UIView animateWithDuration:0.25 animations:^{
            strongSelf->_banner.alpha = 0;
        } completion:^(BOOL finished) {
            if (strongSelf->_bannerToken == token) strongSelf->_banner.hidden = YES;
        }];
    });
}

#pragma mark 常驻控件

- (UITextField *)addressField {
    if (!_addressField) {
        _addressField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 190, 30)];
        _addressField.placeholder = @"手机号或座机";
        _addressField.textAlignment = NSTextAlignmentRight;
        _addressField.keyboardType = UIKeyboardTypePhonePad;
        _addressField.adjustsFontSizeToFitWidth = YES;
    }
    return _addressField;
}

- (UITextField *)durationField {
    if (!_durationField) {
        _durationField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 110, 30)];
        _durationField.placeholder = @"留空则随机";
        _durationField.textAlignment = NSTextAlignmentRight;
        _durationField.keyboardType = UIKeyboardTypeNumberPad;
    }
    return _durationField;
}

- (UIButton *)rangeButtonWithFrame:(CGRect)frame minimum:(BOOL)isMinimum {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    button.tag = isMinimum ? 0 : 1;
    [button addTarget:self action:@selector(rangeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/* 行内的小胶囊：10 – 20，点哪个数字就在哪个数字旁边弹出滚轮。 */
- (UIView *)rangeAccessoryView {
    if (_rangeAccessory) return _rangeAccessory;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 128, 30)];
    container.backgroundColor = [UIColor tertiarySystemFillColor];
    container.layer.cornerRadius = 8;

    _rangeMinButton = [self rangeButtonWithFrame:CGRectMake(2, 0, 48, 30) minimum:YES];
    _rangeMaxButton = [self rangeButtonWithFrame:CGRectMake(78, 0, 48, 30) minimum:NO];

    UILabel *dash = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 28, 30)];
    dash.text = @"–";
    dash.textAlignment = NSTextAlignmentCenter;
    dash.textColor = [UIColor secondaryLabelColor];
    dash.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];

    [container addSubview:_rangeMinButton];
    [container addSubview:dash];
    [container addSubview:_rangeMaxButton];

    [self refreshRangeButtons];
    _rangeAccessory = container;
    return container;
}

- (void)refreshRangeButtons {
    [_rangeMinButton setTitle:[NSString stringWithFormat:@"%ld", (long)_rangeMinimum] forState:UIControlStateNormal];
    [_rangeMaxButton setTitle:[NSString stringWithFormat:@"%ld", (long)_rangeMaximum] forState:UIControlStateNormal];
}

- (void)rangeButtonTapped:(UIButton *)sender {
    BOOL isMinimum = (sender.tag == 0);
    FCLNumberWheelController *wheel = [FCLNumberWheelController new];
    wheel.value = isMinimum ? _rangeMinimum : _rangeMaximum;
    wheel.preferredContentSize = CGSizeMake(160, 216);

    __weak typeof(self) weakSelf = self;
    wheel.onChange = ^(NSInteger value) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (isMinimum) {
            strongSelf->_rangeMinimum = value;
            if (strongSelf->_rangeMaximum < value) strongSelf->_rangeMaximum = value;
        } else {
            strongSelf->_rangeMaximum = value;
            if (strongSelf->_rangeMinimum > value) strongSelf->_rangeMinimum = value;
        }
        [strongSelf refreshRangeButtons];
    };

    wheel.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *popover = wheel.popoverPresentationController;
    popover.sourceView = sender;
    popover.sourceRect = sender.bounds;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    popover.delegate = self;
    [self presentViewController:wheel animated:YES completion:nil];
}

/* 手机上也让它是气泡，不要变成整屏的弹出页 */
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    (void)controller;
    return UIModalPresentationNone;
}

- (UIDatePicker *)datePicker {
    if (!_datePicker) {
        _datePicker = [[UIDatePicker alloc] init];
        _datePicker.datePickerMode = UIDatePickerModeDateAndTime;
        _datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
        _datePicker.date = _callDate;
        [_datePicker addTarget:self action:@selector(dateChanged:) forControlEvents:UIControlEventValueChanged];
        [_datePicker sizeToFit];
    }
    return _datePicker;
}

- (UISegmentedControl *)directionControl {
    if (!_directionControl) {
        _directionControl = [[UISegmentedControl alloc] initWithItems:@[@"呼出", @"呼入", @"未接"]];
        _directionControl.selectedSegmentIndex = FCLDirectionOutgoing;
        [_directionControl addTarget:self action:@selector(directionChanged:)
                    forControlEvents:UIControlEventValueChanged];
    }
    return _directionControl;
}

- (FCLDirection)direction {
    NSInteger index = _directionControl ? _directionControl.selectedSegmentIndex : 0;
    if (index < 0 || index > 2) index = 0;
    return (FCLDirection)index;
}

- (void)dateChanged:(UIDatePicker *)picker {
    _callDate = picker.date;
}

/* 只改控件本身，不碰表格。 */
- (void)directionChanged:(UISegmentedControl *)seg {
    (void)seg;
    BOOL enabled = ([self direction] != FCLDirectionMissed);
    _durationField.enabled = enabled;
    _rangeMinButton.enabled = enabled;
    _rangeMaxButton.enabled = enabled;
    UIColor *color = enabled ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    _durationCell.textLabel.textColor = color;
    _rangeCell.textLabel.textColor = color;
}

/* 用户填了就用填的；留空就在选定范围里取随机整数秒。未接来电恒为 0。 */
- (double)resolvedDuration {
    if ([self direction] == FCLDirectionMissed) return 0.0;

    NSString *typed = [_durationField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (typed.length > 0) {
        double value = typed.doubleValue;
        return value > 0 ? value : 0.0;
    }

    NSInteger minimum = MAX(FCLSecondsLowerBound, _rangeMinimum);
    NSInteger maximum = MAX(minimum, _rangeMaximum);
    NSInteger span = maximum - minimum + 1;
    return (double)(minimum + (NSInteger)arc4random_uniform((uint32_t)span));
}

#pragma mark 收藏

- (void)pushFavorites {
    [self.view endEditing:YES];
    FCLFavoritesController *list = [FCLFavoritesController new];
    list.favorites = FCLLoadFavorites();
    list.currentName = _contactName;
    list.currentNumber = _addressField.text;

    __weak typeof(self) weakSelf = self;
    list.onPick = ^(NSString *name, NSString *number) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_contactName = name.length ? name : nil;
        strongSelf->_address = number;
        strongSelf->_addressField.text = number;
        [strongSelf->_tableView reloadData];
    };
    list.onFavoritesChanged = ^(NSArray *favorites) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_favoritesCell.detailTextLabel.text = [strongSelf favoritesText];
    };
    [self.navigationController pushViewController:list animated:YES];
}

- (NSString *)favoritesText {
    NSUInteger count = FCLLoadFavorites().count;
    return count ? [NSString stringWithFormat:@"%lu 个", (unsigned long)count] : @"无";
}

#pragma mark 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : (section == 1 ? 4 : 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"联系人";
    if (section == 1) return @"通话信息";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"通话时长留空时，按「随机范围」里的秒数随机生成。";
    if (section == 2) return @"写入后可在「电话」App 的最近通话里看到这条记录。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"FCLCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"联系人";
            cell.detailTextLabel.text = _contactName.length ? _contactName : @"未选择";
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"电话号码";
            cell.accessoryView = [self addressField];
        } else {
            _favoritesCell = cell;
            cell.textLabel.text = @"收藏";
            cell.detailTextLabel.text = [self favoritesText];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }

    if (indexPath.section == 1) {
        BOOL enabled = ([self direction] != FCLDirectionMissed);
        UIColor *color = enabled ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"时间";
            cell.accessoryView = [self datePicker];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            [_datePicker setDate:_callDate animated:NO];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"类型";
            cell.accessoryView = [self directionControl];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            _durationCell = cell;
            cell.textLabel.text = @"通话时长";
            cell.accessoryView = [self durationField];
            _durationField.enabled = enabled;
            cell.textLabel.textColor = color;
        } else {
            _rangeCell = cell;
            cell.textLabel.text = @"随机范围";
            cell.textLabel.textColor = color;
            cell.accessoryView = [self rangeAccessoryView];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            _rangeMinButton.enabled = enabled;
            _rangeMaxButton.enabled = enabled;
        }
        return cell;
    }

    _submitCell = cell;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    [self updateSubmitCell];
    return cell;
}

- (void)updateSubmitCell {
    UITableViewCell *cell = _submitCell;
    if (!cell) return;
    cell.textLabel.text = _submitting ? @"正在写入…" : @"添加记录";
    cell.textLabel.textColor = _submitting ? [UIColor secondaryLabelColor] : [UIColor systemBlueColor];
    cell.selectionStyle = _submitting ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            [self presentContactPicker];
        } else if (indexPath.row == 1) {
            [[self addressField] becomeFirstResponder];
        } else {
            [self pushFavorites];
        }
        return;
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 3 && [self direction] != FCLDirectionMissed) {
            [self rangeButtonTapped:_rangeMinButton];
        }
        return;
    }

    [self submit];
}

#pragma mark 选择联系人

- (void)presentContactPicker {
    [self.view endEditing:YES];
    CNContactPickerViewController *picker = [CNContactPickerViewController new];
    picker.delegate = self;
    picker.predicateForEnablingContact = [NSPredicate predicateWithFormat:@"phoneNumbers.@count > 0"];
    picker.predicateForSelectionOfProperty = [NSPredicate predicateWithFormat:@"key == 'phoneNumbers'"];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContactProperty:(CNContactProperty *)property {
    id value = property.value;
    NSString *number = nil;
    if ([value isKindOfClass:[CNPhoneNumber class]]) {
        number = [(CNPhoneNumber *)value stringValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        number = value;
    }

    NSMutableString *cleaned = [number mutableCopy] ?: [NSMutableString string];
    for (NSString *junk in @[@" ", @"-", @"(", @")", @"\u00a0"]) {
        [cleaned replaceOccurrencesOfString:junk withString:@"" options:0 range:NSMakeRange(0, cleaned.length)];
    }
    if (cleaned.length) {
        _address = cleaned;
        _addressField.text = cleaned;
    }

    NSString *name = [CNContactFormatter stringFromContact:property.contact style:CNContactFormatterStyleFullName];
    if (name.length) _contactName = name;

    /* 选择器完全关掉之后再刷新，避免在它的回调里动表格 */
    [picker dismissViewControllerAnimated:YES completion:^{
        [self->_tableView reloadData];
    }];
}

- (void)contactPickerDidCancel:(CNContactPickerViewController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark 提交

- (void)submit {
    if (_submitting) return;
    [self.view endEditing:YES];

    NSString *address = [_addressField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (address.length == 0) {
        [self showBanner:@"先填个电话号码，或从联系人里选一个" success:NO];
        return;
    }
    _address = address;

    BOOL originated = ([self direction] == FCLDirectionOutgoing);
    BOOL answered = ([self direction] != FCLDirectionMissed);
    double duration = [self resolvedDuration];
    NSString *name = [_contactName copy];
    NSDate *date = _datePicker.date ?: [_callDate copy];

    _submitting = YES;
    [self updateSubmitCell];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *failure = FCLInsertCallRecord(address, name, date, originated, answered, duration);
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishSubmitWithFailure:failure duration:duration];
        });
    });
}

- (void)finishSubmitWithFailure:(NSString *)failure duration:(double)duration {
    _submitting = NO;
    [self updateSubmitCell];
    if (failure) {
        [self showBanner:failure success:NO];
        return;
    }
    NSString *text = duration > 0
        ? [NSString stringWithFormat:@"已添加 · 时长 %.0f 秒，去「电话」的最近通话看看", duration]
        : @"已添加，去「电话」的最近通话看看";
    [self showBanner:text success:YES];
}

@end
