#import "EpsonEposSdkBridge.h"

#if __has_include(<libepos2/ePOS2.h>)
#import <libepos2/ePOS2.h>
#define BTP_HAS_EPSON_EPOS 1
#elif __has_include(<ePOS2.h>)
#import <ePOS2.h>
#define BTP_HAS_EPSON_EPOS 1
#elif __has_include("ePOS2.h")
#import "ePOS2.h"
#define BTP_HAS_EPSON_EPOS 1
#else
#define BTP_HAS_EPSON_EPOS 0
#endif

#if BTP_HAS_EPSON_EPOS

@interface EpsonEposSdkBridge () <Epos2DiscoveryDelegate, Epos2PtrReceiveDelegate>
@property(nonatomic, copy, nullable) EpsonEposEventSink callback;
@property(nonatomic, strong) NSMutableDictionary<NSString *, Epos2DeviceInfo *> *devices;
@property(nonatomic, strong, nullable) Epos2Printer *printer;
@property(nonatomic, copy, nullable) NSString *connectedTarget;
@end

#endif

@implementation EpsonEposSdkBridge

- (instancetype)init {
  self = [super init];
  if (self) {
#if BTP_HAS_EPSON_EPOS
    _devices = [NSMutableDictionary dictionary];
#endif
  }
  return self;
}

- (NSDictionary<NSString *, id> *)handle:(NSDictionary<NSString *, id> *)args
                                callback:(EpsonEposEventSink)callback {
#if !BTP_HAS_EPSON_EPOS
  return [self result:NO
                 code:@"sdk_missing"
              message:@"Epson ePOS SDK não encontrado. Copie libepos2.xcframework para ios/Frameworks/libepos2.xcframework e rode pod install."];
#else
  self.callback = callback;

  NSString *action = [self stringValue:args[@"action"] fallback:@""];
  if ([action isEqualToString:@"startDiscovery"]) {
    return [self startDiscoveryWithArgs:args];
  }
  if ([action isEqualToString:@"stopDiscovery"]) {
    return [self stopDiscovery];
  }
  if ([action isEqualToString:@"connect"]) {
    return [self connectWithArgs:args];
  }
  if ([action isEqualToString:@"disconnect"]) {
    return [self disconnectPrinter];
  }
  if ([action isEqualToString:@"printRaw"]) {
    return [self printRawWithArgs:args];
  }
  if ([action isEqualToString:@"snapshot"]) {
    return [self result:YES extra:@{@"devices": [self snapshotDevices]}];
  }
  if ([action isEqualToString:@"sdkVersion"]) {
    return [self result:YES extra:@{@"version": [Epos2Log getSdkVersion] ?: @""}];
  }

  return [self result:NO code:@"bad_action" message:@"Ação Epson desconhecida."];
#endif
}

#if BTP_HAS_EPSON_EPOS

- (NSDictionary<NSString *, id> *)startDiscoveryWithArgs:(NSDictionary<NSString *, id> *)args {
  [self.devices removeAllObjects];
  [Epos2Discovery stop];

  Epos2FilterOption *filter = [[Epos2FilterOption alloc] init];
  filter.portType = [self portTypeForString:[self stringValue:args[@"portType"] fallback:@"all"]];
  filter.deviceType = EPOS2_TYPE_PRINTER;
  filter.deviceModel = EPOS2_MODEL_ALL;

  int code = [Epos2Discovery start:filter delegate:self];
  return [self resultForEposCode:code successMessage:@"Epson ePOS: discovery iniciado"];
}

- (NSDictionary<NSString *, id> *)stopDiscovery {
  int code = [Epos2Discovery stop];
  return [self resultForEposCode:code successMessage:@"Epson ePOS: discovery parado"];
}

- (NSDictionary<NSString *, id> *)connectWithArgs:(NSDictionary<NSString *, id> *)args {
  NSString *target = [self stringValue:args[@"target"] fallback:@""];
  if (target.length == 0) {
    return [self result:NO code:@"bad_args" message:@"Target Epson vazio."];
  }

  [self disconnectPrinter];

  int series = [self printerSeriesForString:[self stringValue:args[@"printerSeries"] fallback:@"tmP80ii"]];
  int lang = [self modelLangForString:[self stringValue:args[@"modelLang"] fallback:@"ank"]];
  long timeout = [self longValue:args[@"connectTimeoutMs"] fallback:10000];

  Epos2Printer *printer = [[Epos2Printer alloc] initWithPrinterSeries:series lang:lang];
  if (printer == nil) {
    return [self result:NO code:@"init_failed" message:@"Falha ao criar Epos2Printer."];
  }

  [printer setReceiveEventDelegate:self];

  int code = [printer connect:target timeout:timeout];
  if (code != EPOS2_SUCCESS) {
    [printer setReceiveEventDelegate:nil];
    return [self resultForEposCode:code successMessage:nil];
  }

  self.printer = printer;
  self.connectedTarget = target;
  return [self result:YES extra:@{@"target": target}];
}

- (NSDictionary<NSString *, id> *)disconnectPrinter {
  int code = EPOS2_SUCCESS;
  if (self.printer != nil) {
    [self.printer setReceiveEventDelegate:nil];
    code = [self.printer disconnect];
  }
  self.printer = nil;
  self.connectedTarget = nil;
  return [self resultForEposCode:code successMessage:@"Epson ePOS: desconectado"];
}

- (NSDictionary<NSString *, id> *)printRawWithArgs:(NSDictionary<NSString *, id> *)args {
  NSData *data = args[@"data"];
  if (![data isKindOfClass:[NSData class]] || data.length == 0) {
    return [self result:NO code:@"bad_args" message:@"Dados Epson vazios."];
  }
  if (self.printer == nil) {
    return [self result:NO code:@"not_connected" message:@"Epson ePOS: impressora não conectada."];
  }

  int code = [self.printer clearCommandBuffer];
  if (code != EPOS2_SUCCESS) {
    return [self resultForEposCode:code successMessage:nil];
  }

  code = [self.printer addCommand:data];
  if (code != EPOS2_SUCCESS) {
    return [self resultForEposCode:code successMessage:nil];
  }

  long timeout = [self longValue:args[@"sendTimeoutMs"] fallback:10000];
  code = [self.printer sendData:timeout];
  return [self resultForEposCode:code successMessage:@"Epson ePOS: dados enviados"];
}

- (void)onDiscovery:(Epos2DeviceInfo *)deviceInfo {
  if (deviceInfo == nil || deviceInfo.target.length == 0) {
    return;
  }

  self.devices[deviceInfo.target] = deviceInfo;
  if (self.callback != nil) {
    self.callback(@{
      @"type": @"deviceFound",
      @"device": [self deviceMap:deviceInfo],
      @"target": deviceInfo.target ?: @"",
      @"ipAddress": deviceInfo.ipAddress ?: @"",
      @"bdAddress": deviceInfo.bdAddress ?: @"",
      @"leBdAddress": deviceInfo.leBdAddress ?: @""
    });
  }
}

- (void)onPtrReceive:(Epos2Printer *)printerObj
                code:(int)code
              status:(Epos2PrinterStatusInfo *)status
          printJobId:(NSString *)printJobId {
  if (self.callback == nil) {
    return;
  }

  NSMutableDictionary<NSString *, id> *event = [@{
    @"type": code == EPOS2_CODE_SUCCESS ? @"status" : @"error",
    @"message": [NSString stringWithFormat:@"Epson ePOS: print callback %@ (%d)", [self callbackCodeName:code], code],
    @"code": @(code),
    @"printJobId": printJobId ?: @""
  } mutableCopy];

  if (status != nil) {
    event[@"status"] = @{
      @"connection": @([status getConnection]),
      @"online": @([status getOnline]),
      @"coverOpen": @([status getCoverOpen]),
      @"paper": @([status getPaper]),
      @"batteryLevel": @([status getBatteryLevel])
    };
  }

  self.callback(event);
}

- (NSArray<NSDictionary<NSString *, id> *> *)snapshotDevices {
  NSMutableArray<NSDictionary<NSString *, id> *> *list = [NSMutableArray array];
  NSArray<Epos2DeviceInfo *> *sorted = [self.devices.allValues sortedArrayUsingComparator:^NSComparisonResult(Epos2DeviceInfo *a, Epos2DeviceInfo *b) {
    NSString *left = a.deviceName.length > 0 ? a.deviceName : a.target;
    NSString *right = b.deviceName.length > 0 ? b.deviceName : b.target;
    return [left localizedCaseInsensitiveCompare:right];
  }];

  for (Epos2DeviceInfo *device in sorted) {
    [list addObject:[self deviceMap:device]];
  }
  return list;
}

- (NSDictionary<NSString *, id> *)deviceMap:(Epos2DeviceInfo *)deviceInfo {
  NSString *target = deviceInfo.target ?: @"";
  NSString *name = deviceInfo.deviceName.length > 0 ? deviceInfo.deviceName : target;
  return @{
    @"id": target,
    @"name": name.length > 0 ? name : @"Epson Printer",
    @"target": target,
    @"ipAddress": deviceInfo.ipAddress ?: @"",
    @"bdAddress": deviceInfo.bdAddress ?: @"",
    @"leBdAddress": deviceInfo.leBdAddress ?: @""
  };
}

- (int)portTypeForString:(NSString *)value {
  NSString *v = value.lowercaseString;
  if ([v isEqualToString:@"tcp"]) return EPOS2_PORTTYPE_TCP;
  if ([v isEqualToString:@"bluetooth"]) return EPOS2_PORTTYPE_BLUETOOTH;
  if ([v isEqualToString:@"usb"]) return EPOS2_PORTTYPE_USB;
  if ([v isEqualToString:@"ble"] || [v isEqualToString:@"bluetoothle"]) return EPOS2_PORTTYPE_BLUETOOTH_LE;
  return EPOS2_PORTTYPE_ALL;
}

- (int)printerSeriesForString:(NSString *)value {
  NSString *v = value.lowercaseString;
  if ([v isEqualToString:@"tmp80"] || [v isEqualToString:@"tm-p80"]) return EPOS2_TM_P80;
  if ([v isEqualToString:@"tmp80ii"] || [v isEqualToString:@"tm-p80ii"]) return EPOS2_TM_P80II;
  return EPOS2_TM_P80II;
}

- (int)modelLangForString:(NSString *)value {
  NSString *v = value.lowercaseString;
  if ([v isEqualToString:@"japanese"] || [v isEqualToString:@"ja"]) return EPOS2_MODEL_JAPANESE;
  if ([v isEqualToString:@"chinese"] || [v isEqualToString:@"zh"]) return EPOS2_MODEL_CHINESE;
  if ([v isEqualToString:@"taiwan"] || [v isEqualToString:@"zh_tw"]) return EPOS2_MODEL_TAIWAN;
  if ([v isEqualToString:@"korean"] || [v isEqualToString:@"ko"]) return EPOS2_MODEL_KOREAN;
  if ([v isEqualToString:@"thai"] || [v isEqualToString:@"th"]) return EPOS2_MODEL_THAI;
  if ([v isEqualToString:@"southasia"] || [v isEqualToString:@"south_asia"]) return EPOS2_MODEL_SOUTHASIA;
  return EPOS2_MODEL_ANK;
}

- (NSDictionary<NSString *, id> *)resultForEposCode:(int)code successMessage:(NSString *)successMessage {
  if (code == EPOS2_SUCCESS) {
    return [self result:YES extra:successMessage != nil ? @{@"message": successMessage, @"eposCode": @(code)} : @{@"eposCode": @(code)}];
  }

  return [self result:NO
                 code:[self errorCodeName:code]
              message:[NSString stringWithFormat:@"Epson ePOS erro %@ (%d)", [self errorCodeName:code], code]
                extra:@{@"eposCode": @(code)}];
}

- (NSString *)errorCodeName:(int)code {
  switch (code) {
    case EPOS2_SUCCESS: return @"EPOS2_SUCCESS";
    case EPOS2_ERR_PARAM: return @"EPOS2_ERR_PARAM";
    case EPOS2_ERR_CONNECT: return @"EPOS2_ERR_CONNECT";
    case EPOS2_ERR_TIMEOUT: return @"EPOS2_ERR_TIMEOUT";
    case EPOS2_ERR_MEMORY: return @"EPOS2_ERR_MEMORY";
    case EPOS2_ERR_ILLEGAL: return @"EPOS2_ERR_ILLEGAL";
    case EPOS2_ERR_PROCESSING: return @"EPOS2_ERR_PROCESSING";
    case EPOS2_ERR_NOT_FOUND: return @"EPOS2_ERR_NOT_FOUND";
    case EPOS2_ERR_IN_USE: return @"EPOS2_ERR_IN_USE";
    case EPOS2_ERR_DISCONNECT: return @"EPOS2_ERR_DISCONNECT";
    case EPOS2_ERR_DEVICE_BUSY: return @"EPOS2_ERR_DEVICE_BUSY";
    default: return @"EPOS2_ERR_FAILURE";
  }
}

- (NSString *)callbackCodeName:(int)code {
  switch (code) {
    case EPOS2_CODE_SUCCESS: return @"EPOS2_CODE_SUCCESS";
    case EPOS2_CODE_ERR_TIMEOUT: return @"EPOS2_CODE_ERR_TIMEOUT";
    case EPOS2_CODE_ERR_NOT_FOUND: return @"EPOS2_CODE_ERR_NOT_FOUND";
    case EPOS2_CODE_ERR_COVER_OPEN: return @"EPOS2_CODE_ERR_COVER_OPEN";
    case EPOS2_CODE_ERR_EMPTY: return @"EPOS2_CODE_ERR_EMPTY";
    case EPOS2_CODE_ERR_PORT: return @"EPOS2_CODE_ERR_PORT";
    case EPOS2_CODE_ERR_CONNECT: return @"EPOS2_CODE_ERR_CONNECT";
    case EPOS2_CODE_ERR_DISCONNECT: return @"EPOS2_CODE_ERR_DISCONNECT";
    case EPOS2_CODE_ERR_PARAM: return @"EPOS2_CODE_ERR_PARAM";
    default: return @"EPOS2_CODE_OTHER";
  }
}

#endif

- (NSDictionary<NSString *, id> *)result:(BOOL)ok
                                    code:(NSString *)code
                                 message:(NSString *)message {
  return [self result:ok code:code message:message extra:@{}];
}

- (NSDictionary<NSString *, id> *)result:(BOOL)ok extra:(NSDictionary<NSString *, id> *)extra {
  return [self result:ok code:ok ? @"ok" : @"error" message:extra[@"message"] ?: @"" extra:extra];
}

- (NSDictionary<NSString *, id> *)result:(BOOL)ok
                                    code:(NSString *)code
                                 message:(NSString *)message
                                   extra:(NSDictionary<NSString *, id> *)extra {
  NSMutableDictionary<NSString *, id> *result = [@{
    @"ok": @(ok),
    @"code": code ?: @"",
    @"message": message ?: @""
  } mutableCopy];
  [result addEntriesFromDictionary:extra ?: @{}];
  return result;
}

- (NSString *)stringValue:(id)value fallback:(NSString *)fallback {
  return [value isKindOfClass:[NSString class]] ? (NSString *)value : fallback;
}

- (long)longValue:(id)value fallback:(long)fallback {
  if ([value respondsToSelector:@selector(longValue)]) {
    return [value longValue];
  }
  return fallback;
}

@end
