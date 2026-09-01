#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^HoneywellPrinterEventSink)(NSDictionary<NSString *, id> *event);

/// Objective-C boundary around HoneywellPrinterSDK.
///
/// Keeping the SDK import behind `__has_include` lets the public plugin build
/// without redistributing Honeywell's proprietary XCFramework.
@interface HoneywellPrinterSdkBridge : NSObject

@property(class, nonatomic, readonly) BOOL isSdkAvailable;

- (NSDictionary<NSString *, id> *)handle:(NSDictionary<NSString *, id> *)args
                                callback:(HoneywellPrinterEventSink)callback;

@end

NS_ASSUME_NONNULL_END
