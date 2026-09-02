#import "HoneywellPrinterSdkBridge.h"

#import <ExternalAccessory/ExternalAccessory.h>

#if __has_include(<HoneywellPrinterSDK/HoneywellPrinterSDK.h>)
#import <HoneywellPrinterSDK/HoneywellPrinterSDK.h>
#define BTP_HAS_HONEYWELL_PRINTER_SDK 1
#else
#define BTP_HAS_HONEYWELL_PRINTER_SDK 0
#endif

#if BTP_HAS_HONEYWELL_PRINTER_SDK
@interface HoneywellPrinterSdkBridge () <ConnectionDelegate>
#else
@interface HoneywellPrinterSdkBridge ()
#endif
@property(nonatomic, copy, nullable) HoneywellPrinterEventSink callback;
#if BTP_HAS_HONEYWELL_PRINTER_SDK
@property(nonatomic, strong, nullable) Connection_BluetoothEA *connection;
#endif
@property(nonatomic, copy, nullable) NSString *deviceId;
@property(nonatomic, copy, nullable) NSString *deviceName;
@property(nonatomic) NSInteger pendingWrites;
@property(nonatomic, strong) dispatch_queue_t writeQueue;
- (void)completeOperation:(HoneywellPrinterOperationCompletion)completion
                    result:(NSDictionary<NSString *, id> *)result;
@end

@implementation HoneywellPrinterSdkBridge

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _writeQueue = dispatch_queue_create("br.com.bluethermal.honeywell.write", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

+ (BOOL)isSdkAvailable {
#if BTP_HAS_HONEYWELL_PRINTER_SDK
  return YES;
#else
  return NO;
#endif
}

- (NSDictionary<NSString *, id> *)handle:(NSDictionary<NSString *, id> *)args
                                callback:(HoneywellPrinterEventSink)callback {
#if !BTP_HAS_HONEYWELL_PRINTER_SDK
  return [self result:NO
                 code:@"sdk_missing"
              message:@"Honeywell PrinterSDK não encontrado. Copie HoneywellPrinterSDK.xcframework para ios/Frameworks e rode pod install novamente."];
#else
  NSString *action = [self stringValue:args[@"action"] fallback:@""];

  if ([action isEqualToString:@"connect"]) {
    return [self connectWithArgs:args callback:callback];
  }
  if ([action isEqualToString:@"disconnect"]) {
    return [self disconnectPrinter];
  }
  if ([action isEqualToString:@"sdkAvailable"]) {
    return [self result:YES extra:@{@"available": @YES}];
  }

  return [self result:NO code:@"bad_action" message:@"Ação Honeywell desconhecida."];
#endif
}

- (void)printRawData:(NSData *)data
 timeoutMilliseconds:(NSInteger)timeoutMilliseconds
          completion:(HoneywellPrinterOperationCompletion)completion {
#if !BTP_HAS_HONEYWELL_PRINTER_SDK
  [self completeOperation:completion
                    result:[self result:NO
                                      code:@"sdk_missing"
                                   message:@"Honeywell PrinterSDK não encontrado."]];
#else
  if (![data isKindOfClass:[NSData class]] || data.length == 0) {
    [self completeOperation:completion
                    result:[self result:NO
                                      code:@"bad_args"
                                   message:@"Dados de impressão Honeywell ausentes."]];
    return;
  }

  Connection_BluetoothEA *connection = self.connection;
  if (connection == nil || !connection.isOpen || connection.isClosing) {
    [self completeOperation:completion
                    result:[self result:NO
                                      code:@"not_connected"
                                   message:@"Honeywell SDK: impressora não conectada."]];
    return;
  }

  NSInteger safeTimeout = MAX(1000, MIN(timeoutMilliseconds, 120000));
  @synchronized(self) {
    self.pendingWrites += 1;
  }

  dispatch_async(self.writeQueue, ^{
    NSDictionary<NSString *, id> *result;

    if (connection != self.connection || !connection.isOpen || connection.isClosing) {
      result = [self result:NO
                       code:@"connection_closed"
                    message:@"Honeywell SDK: conexão encerrada durante a impressão."];
    } else {
      @try {
        [connection writeData:data];
        BOOL drained = [connection waitForEmptyBuffer:(int)safeTimeout];

        if (drained) {
          // The SDK documents that an empty send queue does not necessarily
          // mean the printer has processed the last bytes. Give the RP4f a
          // small guard interval before allowing callers to disconnect.
          [NSThread sleepForTimeInterval:2.0];
          result = [self result:YES
                          extra:@{
                            @"bytes": @(data.length),
                            @"queueDrained": @YES
                          }];
        } else {
          result = [self result:NO
                           code:@"write_timeout"
                        message:@"Honeywell SDK: tempo esgotado aguardando o envio completo dos dados."];
        }
      } @catch (NSException *exception) {
        result = [self result:NO
                         code:@"write_exception"
                      message:exception.reason ?: @"Falha ao enviar dados para a impressora Honeywell."];
      }
    }

    @synchronized(self) {
      self.pendingWrites = MAX(0, self.pendingWrites - 1);
    }
    [self completeOperation:completion result:result];
  });
#endif
}

#if BTP_HAS_HONEYWELL_PRINTER_SDK

- (NSDictionary<NSString *, id> *)connectWithArgs:(NSDictionary<NSString *, id> *)args
                                          callback:(HoneywellPrinterEventSink)callback {
  EAAccessory *accessory = args[@"accessory"];
  NSString *protocolString = [self stringValue:args[@"protocol"] fallback:@""];

  if (![accessory isKindOfClass:[EAAccessory class]] || protocolString.length == 0) {
    return [self result:NO
                   code:@"bad_args"
                message:@"Acessório ou protocolo Honeywell inválido."];
  }

  @synchronized(self) {
    if (self.pendingWrites > 0) {
      return [self result:NO
                       code:@"print_in_progress"
                    message:@"Honeywell SDK: aguarde a impressão terminar antes de reconectar."];
    }
  }

  if (![accessory.protocolStrings containsObject:protocolString]) {
    return [self result:NO
                   code:@"unsupported_protocol"
                message:@"O acessório Honeywell não anuncia o protocolo solicitado."];
  }

  [self closeCurrentConnection];
  self.callback = callback;
  self.deviceId = [self stringValue:args[@"deviceId"]
                                  fallback:[NSString stringWithFormat:@"%lu", (unsigned long)accessory.connectionID]];
  self.deviceName = [self stringValue:args[@"deviceName"] fallback:accessory.name ?: @"Honeywell"];

  @try {
    Connection_BluetoothEA *connection = [[Connection_BluetoothEA alloc] initWithDelegate:self];
    connection.connTimeout = 10;
    [connection setupConnectionForAccessory:accessory withProtocolString:protocolString];
    self.connection = connection;
    [connection open];
  } @catch (NSException *exception) {
    self.connection = nil;
    return [self result:NO
                   code:@"connect_exception"
                message:exception.reason ?: @"Falha ao iniciar a conexão Honeywell."];
  }

  return [self result:YES message:@"Honeywell SDK: conexão iniciada"];
}

- (NSDictionary<NSString *, id> *)disconnectPrinter {
  @synchronized(self) {
    if (self.pendingWrites > 0) {
      return [self result:NO
                       code:@"print_in_progress"
                    message:@"Honeywell SDK: impressão em andamento; desconexão adiada."];
    }
  }

  BOOL wasConnected = self.connection != nil;
  [self closeCurrentConnection];
  self.callback = nil;
  self.deviceId = nil;
  self.deviceName = nil;

  return [self result:YES
              message:wasConnected ? @"Honeywell SDK: desconectado" : @"Honeywell SDK: já desconectado"];
}

- (void)closeCurrentConnection {
  Connection_BluetoothEA *connection = self.connection;
  self.connection = nil;
  if (connection == nil) {
    return;
  }

  // Manual disconnect is reported by the Swift transport, avoiding duplicate
  // `disconnected` events from the asynchronous SDK delegate.
  connection.delegate = nil;
  if (!connection.isClosing) {
    [connection close];
  }
}

- (void)connectionDidOpen:(id)connection {
  if (connection != self.connection) {
    return;
  }

  NSDictionary<NSString *, id> *device = @{
    @"id": self.deviceId ?: @"",
    @"name": self.deviceName ?: @"Honeywell"
  };
  [self emit:@{@"type": @"connected", @"device": device}];
  [self emit:@{@"type": @"ready", @"message": @"Honeywell SDK: pronto para imprimir"}];
}

- (void)connectionFailed:(id)connection withError:(NSError *)error {
  if (connection != self.connection) {
    return;
  }

  self.connection = nil;
  [self emit:@{
    @"type": @"error",
    @"message": error.localizedDescription ?: @"Honeywell SDK: falha na conexão"
  }];
}

- (void)connectionDidClosed:(id)connection {
  if (connection != self.connection) {
    return;
  }

  self.connection = nil;
  [self emit:@{@"type": @"disconnected", @"message": @"Honeywell SDK: conexão encerrada"}];
}

- (void)emit:(NSDictionary<NSString *, id> *)event {
  HoneywellPrinterEventSink callback = self.callback;
  if (callback != nil) {
    callback(event);
  }
}

#endif

- (void)completeOperation:(HoneywellPrinterOperationCompletion)completion
                    result:(NSDictionary<NSString *, id> *)result {
  if (completion == nil) {
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    completion(result);
  });
}

- (NSString *)stringValue:(id)value fallback:(NSString *)fallback {
  return [value isKindOfClass:[NSString class]] ? value : fallback;
}

- (NSDictionary<NSString *, id> *)result:(BOOL)ok
                                     code:(NSString *)code
                                  message:(NSString *)message {
  return @{ @"ok": @(ok), @"code": code, @"message": message };
}

- (NSDictionary<NSString *, id> *)result:(BOOL)ok message:(NSString *)message {
  return @{ @"ok": @(ok), @"message": message };
}

- (NSDictionary<NSString *, id> *)result:(BOOL)ok
                                    extra:(NSDictionary<NSString *, id> *)extra {
  NSMutableDictionary<NSString *, id> *result = [@{@"ok": @(ok)} mutableCopy];
  [result addEntriesFromDictionary:extra];
  return result;
}

@end
