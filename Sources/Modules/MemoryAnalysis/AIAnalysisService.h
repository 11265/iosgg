#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AIAnalysisService : NSObject

+ (instancetype)sharedInstance;

// Set API Configuration
- (void)setApiKey:(NSString *)apiKey;
- (void)setBaseURL:(NSString *)baseURL;
- (void)setModel:(NSString *)model;

// Analyze Assembly
- (void)analyzeAssembly:(NSString *)assemblyCode 
                context:(nullable NSString *)context
             completion:(void(^)(NSString * _Nullable analysis, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
