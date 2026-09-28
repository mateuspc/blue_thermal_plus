#import "BrotherPrinterSdkBridge.h"

#if __has_include(<BRLMPrinterKit/BRLMPrinterKit.h>)
#import <BRLMPrinterKit/BRLMPrinterKit.h>
#define BTP_HAS_BROTHER_PRINT_SDK 1
#else
#define BTP_HAS_BROTHER_PRINT_SDK 0
#endif

@interface BrotherPrinterSdkBridge ()
#if BTP_HAS_BROTHER_PRINT_SDK
@property(nonatomic, strong, nullable) BRLMPrinterDriver *driver;
#endif
@property(nonatomic, copy, nullable) NSString *deviceId;
@property(nonatomic, copy, nullable) NSString *deviceName;
@end

@implementation BrotherPrinterSdkBridge

+ (BOOL)isSdkAvailable {
#if BTP_HAS_BROTHER_PRINT_SDK
  return YES;
#else
  return NO;
#endif
}

- (NSDictionary<NSString *, id> *)connectWithSerialNumber:(NSString *)serialNumber
                                                  deviceId:(NSString *)deviceId
                                                deviceName:(NSString *)deviceName {
#if !BTP_HAS_BROTHER_PRINT_SDK
  return [self failure:@"sdk_missing"
                message:@"Brother Print SDK não encontrado. Adicione BRLMPrinterKit.xcframework ao app."];
#else
  if (serialNumber.length == 0) {
    return [self failure:@"serial_missing"
                  message:@"Brother SDK: número de série Bluetooth ausente."];
  }

  [self disconnectPrinter];

  BRLMChannel *channel = [[BRLMChannel alloc] initWithBluetoothSerialNumber:serialNumber];
  BRLMPrinterDriverGenerateResult *generateResult =
      [BRLMPrinterDriverGenerator openChannel:channel];

  if (generateResult.error.code != BRLMOpenChannelErrorCodeNoError ||
      generateResult.driver == nil) {
    NSString *message = generateResult.error.description;
    if (message.length == 0) {
      message = @"Brother SDK: não foi possível abrir o canal Bluetooth.";
    }
    return [self failure:[NSString stringWithFormat:@"open_channel_%ld",
                                                     (long)generateResult.error.code]
                  message:message];
  }

  self.driver = generateResult.driver;
  self.deviceId = deviceId;
  self.deviceName = deviceName;
  return [self success:@"Brother SDK: conectado"];
#endif
}

- (NSDictionary<NSString *, id> *)disconnectPrinter {
#if !BTP_HAS_BROTHER_PRINT_SDK
  return [self success:@"Brother SDK: indisponível"];
#else
  BRLMPrinterDriver *current = self.driver;
  self.driver = nil;
  self.deviceId = nil;
  self.deviceName = nil;
  if (current != nil) {
    [current closeChannel];
  }
  return [self success:@"Brother SDK: desconectado"];
#endif
}

- (NSDictionary<NSString *, id> *)printRawData:(NSData *)data {
#if !BTP_HAS_BROTHER_PRINT_SDK
  return [self failure:@"sdk_missing" message:@"Brother Print SDK não encontrado."];
#else
  if (data.length == 0) {
    return [self failure:@"bad_args" message:@"Dados de impressão Brother ausentes."];
  }
  BRLMPrinterDriver *current = self.driver;
  if (current == nil) {
    return [self failure:@"not_connected"
                  message:@"Brother SDK: impressora não conectada."];
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  BRLMPrintError *printError = [current sendRawData:data];
#pragma clang diagnostic pop

  if (printError.code == BRLMPrintErrorCodeNoError) {
    return [self success:[NSString stringWithFormat:@"Brother SDK: enviado %lu bytes",
                                                     (unsigned long)data.length]];
  }

  NSString *message = printError.errorDescription;
  if (message.length == 0) {
    message = [NSString stringWithFormat:@"Brother SDK: falha ao imprimir (%ld).",
                                         (long)printError.code];
  }
  return [self failure:[NSString stringWithFormat:@"print_%ld", (long)printError.code]
                message:message];
#endif
}

- (NSDictionary<NSString *, id> *)success:(NSString *)message {
  return @{ @"ok": @YES, @"code": @"ok", @"message": message };
}

- (NSDictionary<NSString *, id> *)failure:(NSString *)code
                                    message:(NSString *)message {
  return @{ @"ok": @NO, @"code": code, @"message": message };
}

@end
