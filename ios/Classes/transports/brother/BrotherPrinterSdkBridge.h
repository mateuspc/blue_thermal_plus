#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C boundary around the optional Brother Print SDK.
///
/// `__has_include` in the implementation keeps the public plugin buildable
/// without redistributing BRLMPrinterKit.xcframework.
@interface BrotherPrinterSdkBridge : NSObject

@property(class, nonatomic, readonly) BOOL isSdkAvailable;

- (NSDictionary<NSString *, id> *)connectWithSerialNumber:(NSString *)serialNumber
                                                  deviceId:(NSString *)deviceId
                                                deviceName:(NSString *)deviceName;

- (NSDictionary<NSString *, id> *)disconnectPrinter;

- (NSDictionary<NSString *, id> *)printRawData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
