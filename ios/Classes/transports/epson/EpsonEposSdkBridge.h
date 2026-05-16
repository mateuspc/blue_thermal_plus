#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^EpsonEposEventSink)(NSDictionary<NSString *, id> *event);

@interface EpsonEposSdkBridge : NSObject

- (NSDictionary<NSString *, id> *)handle:(NSDictionary<NSString *, id> *)args
                                callback:(EpsonEposEventSink)callback;

@end

NS_ASSUME_NONNULL_END
