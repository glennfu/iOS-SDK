//
//  SinglyAppDelegate.m
//  SinglySDK Example
//
//  Copyright (c) 2012-2013 Singly, Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//

#import <SinglySDK/SinglySDK.h>
#import "SinglyAppDelegate.h"

@implementation SinglyAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{

    // Initialize Defaults
    [self initializeDefaults];

    // Initialize TestFlight
    #ifdef TESTFLIGHT_TOKEN
        [TestFlight takeOff:TESTFLIGHT_TOKEN];
    #endif

    // Confirm that the Client ID and Client Secret have been configured
    if (CLIENT_ID.length == 0 || CLIENT_SECRET.length == 0)
        [NSException raise:@"Missing Singly credentials" format:@"You must configure your Singly client id and client secret in SinglyConfiguration.h"];
    
    // Configure Shared SinglySession
    SinglySession *session = SinglySession.sharedSession;
    session.clientID = CLIENT_ID;
    session.clientSecret = CLIENT_SECRET;

    // Set the Base URL (You don't need to do this in your own app)
    session.baseURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"SinglyApiLocation"];

    [[NSNotificationCenter defaultCenter] addObserverForName:kSinglySessionProfilesUpdatedNotification
                                                      object:self
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        NSLog(@"**** Profiles were updated");
    }];
    
    [session startSessionWithCompletion:^(BOOL isReady, NSError *error) {
        if (isReady)
            NSLog(@"Singly Session\n  - Account: %@\n  - Access Token: %@)", session.accountID, session.accessToken);
    }];

    return YES;

}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
    return [SinglySession.sharedSession handleOpenURL:url];
}

#pragma mark - Defaults

- (void)initializeDefaults
{
    NSString *defaultsFile = [[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"];
    NSDictionary *defaults = [NSDictionary dictionaryWithContentsOfFile:defaultsFile];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

@end
