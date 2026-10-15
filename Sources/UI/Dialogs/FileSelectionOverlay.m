#import "UI/Dialogs/FileSelectionOverlay.h"
#import "UI/Components/ThemeConfig.h"

@interface FileSelectionOverlay () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *files;
@end

@implementation FileSelectionOverlay {
    UITableView *_tableView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        
        UIView *container = [[UIView alloc] init];
        container.backgroundColor = IMGUI_BG_COLOR;
        container.layer.cornerRadius = 8;
        container.layer.borderWidth = 1;
        container.layer.borderColor = [UIColor darkGrayColor].CGColor;
        container.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:container];
        
        UILabel *title = [[UILabel alloc] init];
        title.text = @"选择扫描结果文件";
        title.textColor = IMGUI_TEXT;
        title.font = [UIFont boldSystemFontOfSize:16];
        title.textAlignment = NSTextAlignmentCenter;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:title];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:closeBtn];
        
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.separatorColor = [UIColor darkGrayColor];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.translatesAutoresizingMaskIntoConstraints = NO;
        [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"FileCell"];
        [container addSubview:_tableView];
        
        [NSLayoutConstraint activateConstraints:@[
            [container.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [container.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [container.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.85],
            [container.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.7],
            
            [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:10],
            [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [title.heightAnchor constraintEqualToConstant:30],
            
            [closeBtn.topAnchor constraintEqualToAnchor:container.topAnchor constant:5],
            [closeBtn.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10],
            [closeBtn.widthAnchor constraintEqualToConstant:30],
            [closeBtn.heightAnchor constraintEqualToConstant:30],
            
            [_tableView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
            [_tableView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [_tableView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [_tableView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-10]
        ]];
        
        [self loadFiles];
    }
    return self;
}

- (UITableView *)tableView {
    return _tableView;
}

- (void)setTableView:(UITableView *)tableView {
    _tableView = tableView;
}

- (void)loadFiles {
    NSString *tempDir = NSTemporaryDirectory();
    NSArray *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempDir error:nil];
    NSMutableArray *results = [NSMutableArray array];
    
    for (NSString *file in allFiles) {
        if (([file hasPrefix:@"pointer_chain_"] || [file hasPrefix:@"pointer_scan_"]) && [file hasSuffix:@".txt"]) {
            NSString *path = [tempDir stringByAppendingPathComponent:file];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            NSDate *date = attrs[NSFileModificationDate];
            unsigned long long size = [attrs fileSize];
            
            [results addObject:@{
                @"name": file,
                @"path": path,
                @"date": date ?: [NSDate date],
                @"size": @(size)
            }];
        }
    }
    
    [results sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj2[@"date"] compare:obj1[@"date"]];
    }];
    
    self.files = results;
    [self.tableView reloadData];
}

- (void)closeTapped {
    if (self.onClose) self.onClose();
    [self removeFromSuperview];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.files.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FileCell" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = IMGUI_TEXT;
    cell.textLabel.font = [UIFont systemFontOfSize:12];
    cell.textLabel.numberOfLines = 2;
    
    NSDictionary *fileInfo = self.files[indexPath.row];
    NSString *name = fileInfo[@"name"];
    NSDate *date = fileInfo[@"date"];
    NSNumber *size = fileInfo[@"size"];
    
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:[size longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@\n%@ - %@", name, [fmt stringFromDate:date], sizeStr];
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *fileInfo = self.files[indexPath.row];
        NSString *path = fileInfo[@"path"];
        
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        
        if (self.onFileDeleted) {
            self.onFileDeleted(path);
        }
        
        [self loadFiles];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *fileInfo = self.files[indexPath.row];
    if (self.onFileSelected) {
        self.onFileSelected(fileInfo[@"path"]);
    }
    [self removeFromSuperview];
}

@end
