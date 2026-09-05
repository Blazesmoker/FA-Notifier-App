#import "BackgroundPluginRegistration.h"
#import "GeneratedPluginRegistrant.h"

@interface FAForwardingRegistration : NSObject
@property(nonatomic, strong) NSObject *target;
@end

@implementation FAForwardingRegistration
- (id)forwardingTargetForSelector:(SEL)selector {
    return self.target;
}
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.target respondsToSelector:selector];
}
- (BOOL)conformsToProtocol:(Protocol *)protocol {
    return [super conformsToProtocol:protocol] || [self.target conformsToProtocol:protocol];
}
@end

@interface FABackgroundNotificationMethods : FAForwardingRegistration
@end

@implementation FABackgroundNotificationMethods
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"show"] &&
        UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
        result([FlutterError errorWithCode:@"background_notification_cancelled"
                                  message:@"The application is entering the foreground"
                                  details:nil]);
        return;
    }
    [(NSObject<FlutterPlugin> *)self.target handleMethodCall:call result:result];
}
@end

@interface FADisplayOnlyRegistrar : FAForwardingRegistration
@end

@implementation FADisplayOnlyRegistrar
- (void)addApplicationDelegate:(NSObject<FlutterPlugin> *)delegate {
}
- (void)addMethodCallDelegate:(NSObject<FlutterPlugin> *)delegate
                     channel:(FlutterMethodChannel *)channel {
    FABackgroundNotificationMethods *methods = [FABackgroundNotificationMethods new];
    methods.target = delegate;
    [(NSObject<FlutterPluginRegistrar> *)self.target addMethodCallDelegate:(id)methods
                                                                 channel:channel];
}
@end

@interface FABackgroundRegistry : FAForwardingRegistration
@end

@implementation FABackgroundRegistry
- (NSObject<FlutterPluginRegistrar> *)registrarForPlugin:(NSString *)pluginKey {
    NSObject<FlutterPluginRegistry> *registry = (id)self.target;
    NSObject<FlutterPluginRegistrar> *registrar = [registry registrarForPlugin:pluginKey];
    if (![pluginKey isEqualToString:@"FlutterLocalNotificationsPlugin"] || registrar == nil) {
        return registrar;
    }
    FADisplayOnlyRegistrar *displayRegistrar = [FADisplayOnlyRegistrar new];
    displayRegistrar.target = registrar;
    return (id)displayRegistrar;
}
@end

void FARegisterBackgroundPlugins(NSObject<FlutterPluginRegistry> *registry) {
    FABackgroundRegistry *backgroundRegistry = [FABackgroundRegistry new];
    backgroundRegistry.target = registry;
    [GeneratedPluginRegistrant registerWithRegistry:(id)backgroundRegistry];
}
