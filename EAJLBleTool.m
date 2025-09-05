//
//  EAJLBleTool.m
//  EAJLBleTool
//
//  Created by Aye on 2025/9/4.
//

#import "EAJLBleTool.h"

#import <JL_HashPair/JL_HashPair.h>
#import <JL_AdvParse/JLAdvParse.h>
#import <JL_BLEKit/JL_BLEKit.h>
#import <JLDialUnit/JLDialUnit.h>
#import <EABluetooth/EABluetooth.h>


#define kJLNeedForcedOTAPath               [kEADocumentsPath stringByAppendingString:@"/JieLi-ota.ufw"]


@interface EAJLBleTool()<EAJLBleManagerDataDelegate>


@property(nonatomic,strong) JL_Assist               *mAssist;
@property(strong,nonatomic) JL_ManagerM             *mCmdManager;   //命令中心
@property(nonatomic,strong) JL_FlashOperateManager  *mFlashManager;
@property(nonatomic,strong) NSString                *lastUUID;
@property(nonatomic,strong) CBPeripheral            *mBlePeripheral;

@property(nonatomic,strong) NSString                *selectedOtaFilePath;

/// 是否可以正常通讯
@property(nonatomic,assign) BOOL                    canCmd;


/// <#name#>
@property(nonatomic,copy) JlOTAResultBlock      jlOTAResultBlock;
@property(nonatomic,copy) JlOTAProgressBlock    jlOTAProgressBlock;
@property(nonatomic,copy) JlOTACompleteBlock    jlOTACompleteBlock;
@end

#define kAppNTF  [NSNotificationCenter defaultCenter]

@implementation EAJLBleTool

static EAJLBleTool *_jlBleManager;
+ (instancetype)defaultManager {
    
    static dispatch_once_t oneToken;
    dispatch_once(&oneToken, ^{
        
        _jlBleManager = [[EAJLBleTool alloc]init];
        
        _jlBleManager.mAssist = [[JL_Assist alloc] init];
        _jlBleManager.mAssist.mLogData = NO;
        [EABleManager defaultManager].jlDelegate = _jlBleManager;
        
    });
    return _jlBleManager;
}

#pragma mark -   获取设备信息
- (void)cmdFirst {
    
    EALog(@"👀 获取设备信息...");
    __weak typeof(self) weakSelf = self;
    [self.mAssist.mCmdManager cmdTargetFeatureResult:^(JL_CMDStatus status, uint8_t sn, NSData * _Nullable data) {
        
        if (status == JL_CMDStatusSuccess) {
            
            weakSelf.canCmd = YES;
            [kAppNTF postNotificationName:kAppEAJLBleManager_CanCmd object:nil];
            
            [EAJLBleTool defaultManager].mCmdManager      = weakSelf.mAssist.mCmdManager;
            [EAJLBleTool defaultManager].mFlashManager    = weakSelf.mAssist.mCmdManager.mFlashManager;
            
            
            JLModel_Device *model = [weakSelf.mAssist.mCmdManager outputDeviceModel];
            JL_OtaStatus upSt = model.otaStatus;
            if (upSt == JL_OtaStatusForce) {
                EALog(@"👀 进入强制升级.");
                if (weakSelf.selectedOtaFilePath) {
                    
                    [weakSelf jlOtaFw:weakSelf.selectedOtaFilePath];
                }
                else
                {
                    [kAppNTF postNotificationName:kAppEAJLBleManager_NeedOTA object:nil];
                }
                return;
            }
            
            EALog(@"👀 设备正常使用...");
            [JL_Tools mainTask:^{
                /*--- 获取公共信息 ---*/
                [weakSelf.mCmdManager cmdGetSystemInfo:JL_FunctionCodeCOMMON Result:^(JL_CMDStatus status, uint8_t sn, NSData * _Nullable data) {
                    
                    EALog(@"👀 获取公共信息");
                }];
            }];
        }
        else {
            
            weakSelf.canCmd = NO;
            EALog(@"👀  ERROR：设备信息获取错误!");
        }
    }];
}


#pragma mark -   获取杰里表盘名称列表
- (BOOL)jlGetWatchFaceList:(void (^)(NSArray *wfNames,NSError *error))complete {
    
    if (!self.canCmd) {
        
        EALog(@"⚠️⚠️⚠️ 暂时不能通讯，请稍后再试");
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    [DialManager listFile:^(DialOperateType type, NSArray * _Nullable array) {
        
        if (type == DialOperateTypeSuccess) {
            
            complete(array,nil);
        }
        else
        {
            complete(nil,[NSError errorWithDomain:[weakSelf getErrorText:type] code:type userInfo:nil]);
        }
    }];
    return YES;
}

#pragma mark -   删除杰里表盘
/// - Parameters:
///   - wfName: 表盘名称
- (BOOL)jiDelWatchFace:(NSString *)wfName complete:(void (^)(BOOL succ,NSError *error))complete {
    
    if (!self.canCmd) {
        
        EALog(@"⚠️⚠️⚠️ 暂时不能通讯，请稍后再试");
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    [DialManager deleteFile:wfName Result:^(DialOperateType type, float progress) {
        
        if (type == DialOperateTypeSuccess) {
            
            complete(YES,nil);
        }
        else
        {
            complete(NO,[NSError errorWithDomain:[weakSelf getErrorText:type] code:type userInfo:nil]);
        }
    }];
    return YES;
}

#pragma mark -   设置杰里当前表盘
/// - Parameters:
///   - wfName: 表盘名称
- (BOOL)jlSetCurrentWatchFace:(NSString *)wfName complete:(void (^)(BOOL succ,NSError *error))complete {
    
    if (!self.canCmd) {
        
        EALog(@"⚠️⚠️⚠️ 暂时不能通讯，请稍后再试");
        return NO;
    }
    [self.mFlashManager cmdWatchFlashPath:wfName Flag:(JL_DialSettingSetDial) Result:^(uint8_t flag, uint32_t size, NSString * _Nullable path, NSString * _Nullable describe) {
        
        if (flag == 0) {
            complete(YES,nil);
            NSLog(@"切换表盘成功~");
        }else{
            complete(NO,[NSError errorWithDomain:describe code:flag userInfo:nil]);
            NSLog(@"切换表盘失败~");
        }
    }];
    return YES;
}

#pragma mark -   添加表盘
- (BOOL)jlAddWatchFace:(NSString *)filePath wfName:(NSString *)wfName progress:(JlOTAProgressBlock)otaProgress complete:(JlOTACompleteBlock)otaComplete {
    
    if (!self.canCmd) {
        
        EALog(@"⚠️⚠️⚠️ 暂时不能通讯，请稍后再试");
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    [DialManager openDialFileSystemWithCmdManager:_mAssist.mCmdManager withResult:^(DialOperateType type, float progress) {
        
        EALog(@"👀杰里OTA状态：%@",[weakSelf getErrorText:type]);
        if (type == DialOperateTypeSuccess) {
            
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (data) {
                
                [DialManager addFile:wfName Content:data Result:^(DialOperateType type, float progress) {
                    
                    if (type == DialOperateTypeSuccess) {
                        
                        otaComplete(YES,nil);
                    }
                    else if (type == DialOperateTypeDoing) {
                        
                        otaProgress(progress);
                    }
                    else
                    {
                        otaComplete(NO,[NSError errorWithDomain:[weakSelf getErrorText:type] code:type userInfo:nil]);
                        
                    }
                }];
            }
        }
    }];
    
    return YES;
}

#define kSave_JL_File 0
#pragma mark - OTA 固件
- (BOOL)jlOtaFw:(NSString *)filePath progress:(JlOTAProgressBlock)otaProgress otaStatus:(JlOTAResultBlock)status complete:(JlOTACompleteBlock)otaComplete {
    
    if (!self.canCmd) {
        
        EALog(@"⚠️⚠️⚠️ 暂时不能通讯，请稍后再试");
        return NO;
    }
    _jlOTAResultBlock       = status;
    _jlOTAProgressBlock     = otaProgress;
    _jlOTACompleteBlock     = otaComplete;
    
    __weak typeof(self) selfWeak = self;
    EADeviceOps *ops = [EADeviceOps eaInitDeviceOpsType:(EADeviceOpsTypeJl707OtaStartRequest)];
    [ops eaSend:^(EARespondCodeType respondCodeType) {
        
        [selfWeak jlOtaFw:filePath];
    }];
    
    return YES;
}

- (void)jlOtaFw:(NSString *)filePath {
    
    self.selectedOtaFilePath = filePath;
    __weak typeof(self) selfWeak = self;
    NSData *otaData = [[NSData alloc] initWithContentsOfFile:filePath];
    [self.mCmdManager.mOTAManager cmdOTAData:otaData Result:^(JL_OTAResult result, float progress) {
        
        if(result == JL_OTAResultPreparing || result == JL_OTAResultPrepared || result == JL_OTAResultUpgrading) {
            
            if (selfWeak.jlOTAResultBlock) {
                selfWeak.jlOTAResultBlock(progress);
            }
        }
        else if (result == JL_OTAResultSuccess) {
            
            if (selfWeak.jlOTACompleteBlock) {
                selfWeak.jlOTACompleteBlock(YES,nil);
            }
        }
        else if (result == JL_OTAResultReboot) {
            
            [selfWeak.mCmdManager.mOTAManager cmdRebootForceDevice];
            if (selfWeak.jlOTAResultBlock) {
                selfWeak.jlOTAResultBlock(result);
            }
        }
        else if (result == JL_OTAResultReconnectWithMacAddr) {
            
            [[EABleManager defaultManager] reConnectToPeripheral:selfWeak.lastBleMacAddress];
            if (selfWeak.jlOTAResultBlock) {
                selfWeak.jlOTAResultBlock(result);
            }
        }
        else if (result == JL_OTAResultReconnect ) {
            
            if (selfWeak.jlOTAResultBlock) {
                selfWeak.jlOTAResultBlock(result);
            }
        }
        else
        {
            if (selfWeak.jlOTACompleteBlock) {
                selfWeak.jlOTACompleteBlock(NO,[NSError errorWithDomain:[selfWeak getOtaErrorText:result] code:result userInfo:nil]);
            }
        }
    }];
}


#pragma mark - 杰里OTA错误文本
- (NSString *)getOtaErrorText:(JL_OTAResult)otaResult {
    
    NSDictionary *infos = @{
        
        [self toString:JL_OTAResultSuccess             ]:@"OTA升级成功",
        [self toString:JL_OTAResultFail                ]:@"OTA升级失败",
        [self toString:JL_OTAResultDataIsNull          ]:@"OTA升级数据为空",
        [self toString:JL_OTAResultCommandFail         ]:@"OTA指令失败",
        [self toString:JL_OTAResultSeekFail            ]:@"OTA标示偏移查找失败",
        [self toString:JL_OTAResultInfoFail            ]:@"OTA升级固件信息错误",
        [self toString:JL_OTAResultLowPower            ]:@"OTA升级设备电压低",
        [self toString:JL_OTAResultEnterFail           ]:@"未能进入OTA升级模式",
        [self toString:JL_OTAResultUpgrading           ]:@"OTA升级中",
        [self toString:JL_OTAResultReconnect           ]:@"OTA需重连设备(uuid方式)",
        [self toString:JL_OTAResultReboot              ]:@"OTA需设备重启",
        [self toString:JL_OTAResultPreparing           ]:@"OTA准备中",
        [self toString:JL_OTAResultPrepared            ]:@"OTA准备完成",
        [self toString:JL_OTAResultStatusIsUpdating    ]:@"设备已在升级中",
        [self toString:JL_OTAResultFailedConnectMore   ]:@"当前固件多台设备连接，请手动断开另 一个设备连接",
        [self toString:JL_OTAResultFailSameSN          ]:@"升级数据校验失败，SN 多次重复",
        [self toString:JL_OTAResultCancel              ]:@"升级取消",
        [self toString:JL_OTAResultFailVerification    ]:@"升级数据校验失败",
        [self toString:JL_OTAResultFailCompletely      ]:@"升级失败",
        [self toString:JL_OTAResultFailKey             ]:@"升级数据校验失败，加密Key不对",
        [self toString:JL_OTAResultFailErrorFile       ]:@"升级文件出错",
        [self toString:JL_OTAResultFailUboot           ]:@"uboot不匹配",
        [self toString:JL_OTAResultFailLenght          ]:@"升级过程长度出错",
        [self toString:JL_OTAResultFailFlash           ]:@"升级过程flash读写失败",
        [self toString:JL_OTAResultFailCmdTimeout      ]:@"升级过程指令超时",
        [self toString:JL_OTAResultFailSameVersion     ]:@"相同版本",
        [self toString:JL_OTAResultFailTWSDisconnect   ]:@"TWS耳机未连接",
        [self toString:JL_OTAResultFailNotInBin        ]:@"耳机未在充电仓",
        [self toString:JL_OTAResultReconnectWithMacAddr]:@"OTA需重连设备(mac方式)",
        [self toString:JL_OTAResultDisconnect          ]:@"OTA设备断开",
        [self toString:JL_OTAResultUnknown             ]:@"OTA未知错误",
    };
    
    return [infos objectForKey:[self toString:otaResult]];
}

#pragma mark - 杰里表盘错误文本
- (NSString *)getErrorText:(DialOperateType)otaResult {
    
    NSDictionary *infos = @{
        
        [self toString:DialOperateTypeNoSpace    ]:@"空间不足",
        [self toString:DialOperateTypeDoing      ]:@"正在操作",
        [self toString:DialOperateTypeFail       ]:@"操作失败",
        [self toString:DialOperateTypeSuccess    ]:@"操作成功",
        [self toString:DialOperateTypeUnnecessary]:@"无需重复打开文件系统",
        [self toString:DialOperateTypeResetFial  ]:@"重置文件系统失败",
        [self toString:DialOperateTypeNormal     ]:@"文件系统正常",
        [self toString:DialOperateTypeCmdFail    ]:@"流程命令执行失败",
    };
    return [infos objectForKey:[self toString:otaResult]];
}

- (NSString *)toString:(UInt8)uint8 {
    
    NSString *key = [NSString stringWithFormat:@"%hhu",uint8];
    return key;
}



#pragma mark - EAJLBleManagerDataDelegate
#pragma mark 设备特征回调
- (void)eaPeripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service{
    
    NSLog(@"JLSDK ADD");
    [self.mAssist assistDiscoverCharacteristicsForService:service Peripheral:peripheral];
    
}

#pragma mark 更新通知特征的状态
- (void)eaPeripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(nonnull CBCharacteristic *)characteristic{
    
    NSLog(@"JLSDK ADD");
    __weak typeof(self) weakSelf = self;
    [self.mAssist assistUpdateCharacteristic:characteristic Peripheral:peripheral Result:^(BOOL isPaired) {
        
        EALog(@"👀 已连接设备");
        if (isPaired == YES) {
            
            weakSelf.lastUUID = peripheral.identifier.UUIDString;
            weakSelf.mBlePeripheral = peripheral;
        }
        
        [weakSelf performSelector:@selector(cmdFirst) afterDelay:2];
    }];
}

#pragma mark 设备返回的数据 GET
- (void)eaPeripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic{
    
    NSLog(@"JLSDK ADD");
    [self.mAssist assistUpdateValueForCharacteristic:characteristic];
}

#pragma mark 设备断开连接
- (void)eaCentralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral{
    
    NSLog(@"JLSDK ADD");
    [self.mAssist assistDisconnectPeripheral:peripheral];
    
}

#pragma mark - 蓝牙初始化 Callback
- (void)eaCentralManagerDidUpdateState:(CBCentralManager *)central{
    
    NSLog(@"JLSDK ADD");
    [self.mAssist assistUpdateState:central.state];
}



@end
