//
//  LocationAppDelegate.m
//  Location
//
//  Created by Rick
//  Copyright (c) 2014 Location. All rights reserved.
//


#import "LocationAppDelegate.h"
#import <notify.h>

@interface LocationAppDelegate ()

@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, assign) NSTimer* timer;

@property (nonatomic, assign) BOOL isBackgroundMode;
@property (nonatomic, assign) BOOL deferringUpdates;

@property (nonatomic, strong) NSString *lastLockState;

@end

// http://stackoverflow.com/questions/10235203/getting-user-location-every-n-minutes-after-app-goes-to-background
// http://stackoverflow.com/questions/6347503/how-do-i-get-a-background-location-update-every-n-minutes-in-my-ios-application
// http://mobileoop.com/getting-location-updates-for-ios-7-and-8-when-the-app-is-killedterminatedsuspended

@implementation LocationAppDelegate {
    // token to mark lock state events
    int notifyToken;
    // last state to determine what particularly happen: Screen has gone ON or OFF
    uint64_t lastState;
}


/*
 * Start of application lifecycle
 */
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    lastState = -1;
    [self registerLockStateDispatch];

    
    self.shareModel = [LocationShareModel sharedModel];
    self.shareModel.afterResume = NO;
    self.isBackgroundMode = NO;
    
    UIAlertView * alert;
    
    //We have to make sure that the Background App Refresh is enable for the Location updates to work in the background.
    if([[UIApplication sharedApplication] backgroundRefreshStatus] == UIBackgroundRefreshStatusDenied){
        
        alert = [[UIAlertView alloc]initWithTitle:@""
                                          message:@"The app doesn't work without the Background App Refresh enabled. To turn it on, go to Settings > General > Background App Refresh"
                                         delegate:nil
                                cancelButtonTitle:@"Ok"
                                otherButtonTitles:nil, nil];
        [alert show];
        
    }else if([[UIApplication sharedApplication] backgroundRefreshStatus] == UIBackgroundRefreshStatusRestricted){
        
        alert = [[UIAlertView alloc]initWithTitle:@""
                                          message:@"The functions of this app are limited because the Background App Refresh is disable."
                                         delegate:nil
                                cancelButtonTitle:@"Ok"
                                otherButtonTitles:nil, nil];
        [alert show];
        
    }
    
    return YES;
}

/*
 * Location manager callback to save determined locations
 */
-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations{
    
    NSLog(@"locationManager didUpdateLocations: %@",locations);

    // Saving location
    for(int i=0;i<locations.count;i++){
        
        CLLocation * newLocation = [locations objectAtIndex:i];
        CLLocationCoordinate2D theLocation = newLocation.coordinate;
        CLLocationAccuracy theAccuracy = newLocation.horizontalAccuracy;
        
        self.myLocation = theLocation;
        self.myLocationAccuracy = theAccuracy;
    }
    // If location come when application is in background, then set Deferred update mode
    if (_isBackgroundMode && !_deferringUpdates)
    {
        _deferringUpdates = YES;
        // IMPORTANT: setting the timeout for deferred updates
        [manager allowDeferredLocationUpdatesUntilTraveled:CLLocationDistanceMax timeout:10];
    }
}

/*
 * Callback when deferred updates are switched off
 */
- (void) locationManager:(CLLocationManager *)manager didFinishDeferredUpdatesWithError:(NSError *)error {
    
    // Just switch of deferred mode for now
    _deferringUpdates = NO;
    
    //do something
}

/*
 * Application lifecycle callback when app is just before going to background
 */
- (void)applicationWillResignActive:(UIApplication *)application {
    _isBackgroundMode = YES;
    // Stop updating location in regular mode, when app is in foreground
    [self.shareModel.anotherLocationManager stopUpdatingLocation];
    // Set location update parameters for background mode (the best possible, but it's possible to experiment here)
    [self.shareModel.anotherLocationManager setDesiredAccuracy:kCLLocationAccuracyBest];
    [self.shareModel.anotherLocationManager setDistanceFilter:kCLDistanceFilterNone];
    self.shareModel.anotherLocationManager.pausesLocationUpdatesAutomatically = NO;
    self.shareModel.anotherLocationManager.activityType = CLActivityTypeAutomotiveNavigation;
    // Starting location update for background mode
    [self.shareModel.anotherLocationManager startUpdatingLocation];
}

/*
 * Application lifecycle callback when app is in background
 */
- (void)applicationDidEnterBackground:(UIApplication *)application
{
    NSLog(@"applicationDidEnterBackground");

    // requesting location update authorization just in case, to be sure that it is switched on
    if(IS_OS_8_OR_LATER) {
        [self.shareModel.anotherLocationManager requestAlwaysAuthorization];
    }
    // registering event handlers for screen locking
    [self registerLockStateDispatch];
    // Starting background task in order not to be terminated by iOS immediately after going background
    self.bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        
        // should never get here under normal circumstances
        [application endBackgroundTask: self.bgTask];
        
        self.bgTask = UIBackgroundTaskInvalid;
        NSLog(@"I'm going away now ....");
    }];
}


/*
 * Application lifecycle callback when app is in foreground after being background
 */
- (void)applicationDidBecomeActive:(UIApplication *)application
{
    NSLog(@"applicationDidBecomeActive");
    
    //Remove the "afterResume" Flag after the app is active again.
    self.shareModel.afterResume = NO;

    // Start monitoring significant location changes instead of deffered updates
    if(self.shareModel.anotherLocationManager)
        [self.shareModel.anotherLocationManager stopMonitoringSignificantLocationChanges];
    
    self.shareModel.anotherLocationManager = [[CLLocationManager alloc]init];
    self.shareModel.anotherLocationManager.delegate = self;
    self.shareModel.anotherLocationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    self.shareModel.anotherLocationManager.activityType = CLActivityTypeOtherNavigation;
    
    if(IS_OS_8_OR_LATER) {
        [self.shareModel.anotherLocationManager requestAlwaysAuthorization];
    }
}

/*
 * Application lifecycle callback when app is terminated
 */
-(void)applicationWillTerminate:(UIApplication *)application{
    // Logging to track app is alive or not
    NSLog(@"applicationWillTerminate");
}

// http://stackoverflow.com/questions/14352228/is-there-a-away-to-detect-the-event-when-ios-device-goes-to-sleep-mode-when-the

/*
 * Utility function to register event handlers
 */
-(void)registerLockStateDispatch {
    int status = notify_register_dispatch("com.apple.springboard.hasBlankedScreen",
                                          &notifyToken,
                                          dispatch_get_main_queue(), ^(int t) {
                                              uint64_t state;
                                              int result = notify_get_state(notifyToken, &state);
                                              if (result != NOTIFY_STATUS_OK) {
                                                  NSLog(@"notify_get_state() not returning NOTIFY_STATUS_OK");
                                              } else {
                                                  [self lockStateChanged:state];
                                              }
                                          });
    if (status != NOTIFY_STATUS_OK) {
        NSLog(@"notify_register_dispatch() not returning NOTIFY_STATUS_OK");
    }
}

/*
 * Event handler for locking screen event
 */
-(void)lockStateChanged:(uint64_t)state {
    if(state != lastState || lastState == -1) {
        NSLog(@"lock state changed = %llu", state);
        
        // Sending data to Google Spreadsheet using Zapier
        NSString *webHookTemplate = @"https://zapier.com/hooks/catch/og01e6/?id=%@&screenon=%@&timestamp=%f&timestamp_2=%f&deviceid=%@";
        
        NSString *deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        NSString *recId = deviceId;
        NSString *screenOn = state == 0 ? @"TRUE" : @"FALSE";
        NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
        NSString *requestURL = [NSString stringWithFormat:webHookTemplate, deviceId, screenOn, timestamp, timestamp, recId ];
        
        NSURLRequest * urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:requestURL]];
        NSURLResponse * response = nil;
        NSError * error = nil;
        NSData * data = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:&error];
    }
    lastState = state;
}

@end
