#import "Services/Memory/AIAnalysisService.h"
#import "Services/LogService.h"

#define kAIAnalysisAPIKey @"AIAnalysisAPIKey"
#define kAIAnalysisBaseURL @"AIAnalysisBaseURL"
#define kAIAnalysisModel @"AIAnalysisModel"

@interface AIAnalysisService ()
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *model;
@end

@implementation AIAnalysisService

+ (instancetype)sharedInstance {
    static AIAnalysisService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AIAnalysisService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _apiKey = [defaults stringForKey:kAIAnalysisAPIKey] ?: @"";
        _baseURL = [defaults stringForKey:kAIAnalysisBaseURL] ?: @"https://api.openai.com/v1";
        _model = [defaults stringForKey:kAIAnalysisModel] ?: @"gpt-3.5-turbo";
    }
    return self;
}

- (void)setApiKey:(NSString *)apiKey {
    _apiKey = [apiKey copy];
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:kAIAnalysisAPIKey];
}

- (void)setBaseURL:(NSString *)baseURL {
    if (!baseURL || baseURL.length == 0) return;
    _baseURL = [baseURL copy];
    [[NSUserDefaults standardUserDefaults] setObject:_baseURL forKey:kAIAnalysisBaseURL];
}

- (void)setModel:(NSString *)model {
    if (!model || model.length == 0) return;
    _model = [model copy];
    [[NSUserDefaults standardUserDefaults] setObject:_model forKey:kAIAnalysisModel];
}

- (void)analyzeAssembly:(NSString *)assemblyCode 
                context:(NSString *)context
             completion:(void(^)(NSString * _Nullable, NSError * _Nullable))completion {
    
    if (!_apiKey || _apiKey.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"AIAnalysisService" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"请先配置 API Key"}]);
        }
        return;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/chat/completions", _baseURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", _apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSString *prompt = [NSString stringWithFormat:@"请分析以下 ARM64 汇编代码的功能和逻辑:\n\n```assembly\n%@\n```\n\n如果提供了上下文，请结合上下文分析:\n%@", assemblyCode, context ?: @"无上下文"];
    
    NSDictionary *body = @{
        @"model": _model,
        @"messages": @[
            @{@"role": @"system", @"content": @"你是一个专业的逆向工程助手，擅长分析 ARM64 汇编代码。请用简洁明了的语言解释代码的功能。"},
            @{@"role": @"user", @"content": prompt}
        ],
        @"temperature": @0.7
    };
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    if (error) {
        if (completion) completion(nil, error);
        return;
    }
    [request setHTTPBody:jsonData];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        
        if (!data) {
            if (completion) completion(nil, [NSError errorWithDomain:@"AIAnalysisService" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"无数据返回"}]);
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            if (completion) completion(nil, jsonError);
            return;
        }
        
        if (json[@"error"]) {
            NSString *msg = json[@"error"][@"message"] ?: @"未知错误";
            if (completion) completion(nil, [NSError errorWithDomain:@"AIAnalysisService" code:-3 userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }
        
        NSArray *choices = json[@"choices"];
        if (choices && choices.count > 0) {
            NSString *content = choices[0][@"message"][@"content"];
            if (completion) completion(content, nil);
        } else {
            if (completion) completion(nil, [NSError errorWithDomain:@"AIAnalysisService" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"未找到回复内容"}]);
        }
    }];
    [task resume];
}

@end
