#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^HoneywellPrinterEventSink)(NSDictionary<NSString *, id> *event);
typedef void (^HoneywellPrinterOperationCompletion)(NSDictionary<NSString *, id> *result);

/// Objective-C boundary around HoneywellPrinterSDK.
///
/// Keeping the SDK import behind `__has_include` lets the public plugin build
/// without redistributing Honeywell's proprietary XCFramework.
@interface HoneywellPrinterSdkBridge : NSObject

@property(class, nonatomic, readonly) BOOL isSdkAvailable;

- (NSDictionary<NSString *, id> *)handle:(NSDictionary<NSString *, id> *)args
                                callback:(HoneywellPrinterEventSink)callback;

/// Queues raw bytes, waits for the SDK background sender to drain, and only
/// then reports completion. The callback is always delivered on the main queue.
- (void)printRawData:(NSData *)data
 timeoutMilliseconds:(NSInteger)timeoutMilliseconds
          completion:(HoneywellPrinterOperationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
