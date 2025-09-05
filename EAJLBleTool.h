//
//  EAJLBleTool.h
//  EAJLBleTool
//
//  Created by Aye on 2025/9/4.
//

#import <Foundation/Foundation.h>
#import <JL_OTALib/JL_OTALib.h>


NS_ASSUME_NONNULL_BEGIN

/// 杰里连接成功，可以通讯了
#define kAppEAJLBleManager_CanCmd           @"AppEAJLBleManager_CanCmd"

/// 需要强制OTA
#define kAppEAJLBleManager_NeedOTA          @"AppEAJLBleManager_NeedOTA"


typedef void(^JlOTACompleteBlock)(BOOL succ, NSError * _Nullable error);
typedef void(^JlOTAProgressBlock)(CGFloat progress);
typedef void(^JlOTAResultBlock)(JL_OTAResult result);


@interface EAJLBleTool : NSObject

@property(nonatomic,strong) NSString        *lastBleMacAddress;


+ (instancetype)defaultManager;


/// 获取杰里表盘名称列表
- (BOOL)jlGetWatchFaceList:(void (^)(NSArray *wfNames,NSError *error))complete;

/// 删除杰里表盘
/// - Parameters:
///   - wfName: 表盘名称
- (BOOL)jiDelWatchFace:(NSString *)wfName complete:(void (^)(BOOL succ,NSError *error))complete;

/// 设置杰里当前表盘
/// - Parameters:
///   - wfName: 表盘名称
- (BOOL)jlSetCurrentWatchFace:(NSString *)wfName complete:(void (^)(BOOL succ,NSError *error))complete;


/// 添加杰里表盘
/// - Parameters:
///   - filePath: 表盘路径
///   - wfName: 表盘名称
///   - otaProgress: 进度
///   - otaComplete: 完成
- (BOOL)jlAddWatchFace:(NSString *)filePath wfName:(NSString *)wfName progress:(JlOTAProgressBlock)otaProgress complete:(JlOTACompleteBlock)otaComplete;




- (BOOL)jlOtaFw:(NSString *)filePath progress:(JlOTAProgressBlock)otaProgress otaStatus:(JlOTAResultBlock)status complete:(JlOTACompleteBlock)otaComplete;

@end

NS_ASSUME_NONNULL_END
