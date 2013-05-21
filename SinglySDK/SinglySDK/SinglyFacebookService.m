//
//  SinglyFacebookService.m
//  SinglySDK
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

#import "NSDictionary+QueryString.h"
#import "NSString+URLEncoding.h"

#import "SinglyActivityIndicatorView.h"
#import "SinglyAlertView.h"
#import "SinglyConnection.h"
#import "SinglyFacebookService.h"
#import "SinglyFacebookService+Internal.h"
#import "SinglyLog.h"
#import "SinglyRequest.h"
#import "SinglyService+Internal.h"
#import "SinglySession.h"
#import "SinglySession+Internal.h"

@implementation SinglyFacebookService

@synthesize accountStore = _accountStore;
@synthesize completionHandler = _completionHandler;
@synthesize isAborted = _isAborted;
@synthesize isAuthorized = _isAuthorized;

- (id)init
{
    if (self = [super init])
    {
        _accountStore = [[ACAccountStore alloc] init];
    }
    return self;
}

- (NSString *)serviceIdentifier
{
    return @"facebook";
}

- (BOOL)isAppAuthorizationConfigured
{
    BOOL isConfigured = NO;

    //
    // Check for the Facebook URL Scheme in Info.plist.
    //
    NSArray *urlTypesArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
    if (urlTypesArray)
    {
        for (NSDictionary *urlTypeDictionary in urlTypesArray)
        {
            NSArray *urlSchemesArray = [urlTypeDictionary valueForKey:@"CFBundleURLSchemes"];
            if (!urlSchemesArray) continue;
            for (NSString *urlScheme in urlSchemesArray)
            {
                if ([urlScheme hasPrefix:@"fb"])
                {
                    isConfigured = YES;
                    break;
                }
            }
            if (isConfigured) break;
        }
    }

    //
    // Check for openURL: delegate method implementation on the application
    // delegate.
    //
    if (isConfigured && ![[UIApplication sharedApplication].delegate respondsToSelector:@selector(application:openURL:sourceApplication:annotation:)])
        isConfigured = NO;

    //
    // Output a useful message to the console stating that application-based
    // authorization is not configured properly for the app.
    //
    if (!isConfigured)
        SinglyLog(@"Authorization via the installed Facebook app is not available"
                  "because this app is not configured to handle Facebook URLs."
                  "Please see http://singly.github.com/iOS-SDK/api/Classes/SinglyFacebookService.html"
                  "for more details.");

    return isConfigured;
}

- (BOOL)isNativeAuthorizationConfigured
{
    BOOL isConfigured = NO;

    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:@"com.apple.facebook"];

    // iOS 6+
    if (accountType)
    {
        NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];

        if ([accounts respondsToSelector:@selector(count)])
            isConfigured = YES;

        if (!isConfigured)
            SinglyLog(@"Native Facebook authorization is not available because this device is not signed into Facebook.");
    }

    return isConfigured;
}

#pragma mark - Authorization

- (void)requestAuthorizationFromViewController:(UIViewController *)viewController
                                    withScopes:(NSArray *)scopes
                                    completion:(SinglyServiceAuthorizationCompletionHandler)completionHandler
{

    _isAborted = NO;
    _isAuthorized = NO;
    _completionHandler = completionHandler;

    dispatch_queue_t authorizationQueue;
    authorizationQueue = dispatch_queue_create("com.singly.AuthorizationQueue", NULL);

    dispatch_async(authorizationQueue, ^{

        //
        // Step 1 - Fetch the Client ID from Singly
        //
        if (!self.clientIdentifier)
            [self fetchClientIdentifier:nil];

        //
        // Step 2 - Attempt Native Authorization (iOS 6+)
        //
        if (self.clientIdentifier && !self.isAuthorized && !self.isAborted && [self isNativeAuthorizationConfigured])
            [self requestNativeAuthorizationFromViewController:viewController withScopes:scopes];

        //
        // Step 3 - Attempt Authorization via Facebook App
        //
        BOOL isAuthorizingViaApplication = NO;
        if (self.clientIdentifier && !self.isAuthorized && !self.isAborted && [self isAppAuthorizationConfigured])
            isAuthorizingViaApplication = [self requestApplicationAuthorization:scopes];

        //
        // Step 4 - Fallback to Singly Authorization
        //
        if (!self.isAuthorized && !self.isAborted && !isAuthorizingViaApplication)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self requestAuthorizationViaSinglyFromViewController:viewController withScopes:scopes];
            });
        }

    });
    
}

- (void)requestNativeAuthorizationFromViewController:(UIViewController *)viewController
                                          withScopes:(NSArray *)scopes
{
    dispatch_semaphore_t authorizationSemaphore = dispatch_semaphore_create(0);

    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:@"com.apple.facebook"];

    if (!accountType)
    {
        SinglyLog(@"Native Facebook authorization is not available because this device is not signed into Facebook.");
        return;
    }

	// need to split read/write permissions into two requests
    __block NSArray *permissions = (scopes != nil) ? scopes : @[ @"email", @"user_location", @"user_birthday" ];
	__block bool hasPublishStream = false;
	
	[permissions indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		if ([(NSString *)obj isEqualToString:@"real_publish_stream"]) {
			hasPublishStream = true;
			NSMutableArray *clone = [permissions mutableCopy];
			[clone replaceObjectAtIndex:idx withObject:@"publish_stream"];
			permissions = clone;
			return YES;
		}
		return NO;
	}];
	
	if (hasPublishStream) {
		hasPublishStream = false;
	}
	else {
		[permissions indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			if ([(NSString *)obj isEqualToString:@"publish_stream"]) {
				hasPublishStream = true;
				NSMutableArray *clone = [permissions mutableCopy];
				[clone removeObjectAtIndex:idx];
				permissions = clone;
				return YES;
			}
			return NO;
		}];
		
		// If publish_stream is the ONLY permission
		if (permissions.count == 0 && hasPublishStream) {
			hasPublishStream = false;
			permissions = @[@"publish_stream"];
		}
	}
	
    NSDictionary *options = @{
        @"ACFacebookAppIdKey": self.clientIdentifier,
        @"ACFacebookPermissionsKey": permissions,
        @"ACFacebookAudienceKey": @"friends"
    };

    //
    // Post a notification that the authorization is being performed.
    //
    [[NSNotificationCenter defaultCenter] postNotificationName:kSinglyServiceIsAuthorizingNotification
                                                        object:self];

    [self.accountStore requestAccessToAccountsWithType:accountType
                                               options:options
                                            completion:^(BOOL granted, NSError *accessError)
    {

        //
        // Check for Access
        //
        if (!granted)
        {
            SinglyLog(@"Access to the Facebook account on the device was denied.");

            // If there was an error object, it means that the user denied
            // access, so we should be in an aborted state...
            if (accessError)
            {
                _isAborted = YES;
                [self serviceDidFailAuthorizationWithError:accessError];
            }

            // If the error is nil, it means access was already denied (in
            // Settings) so we should fall-back to the next method.
            else
                _isAborted = NO;

            //
            // We do not call the callback or delegate methods because we want
            // to fallback to the standard web-based workflow.
            //

            dispatch_semaphore_signal(authorizationSemaphore);
            return;
        }

        //
        // Check for Access Errors
        //
        if (accessError)
        {
            if (accessError.code == ACErrorAccountNotFound)
            {
                SinglyLog(@"Native Facebook authorization is not available because this device is not signed into Facebook.");
                dispatch_semaphore_signal(authorizationSemaphore);
                return;
            }

            SinglyLog(@"Unhandled error! %@", accessError);

            //
            // We are not authorized. Attempt fallbacks.
            //
            _isAuthorized = NO;

            [self serviceDidFailAuthorizationWithError:accessError];
            dispatch_semaphore_signal(authorizationSemaphore);
            return;
        }

        NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];
        ACAccount *account = [accounts lastObject];

        //
        // Apply the Facebook service to our current session.
        //
        NSError *applyError;
        [SinglySession.sharedSession applyService:self.serviceIdentifier
                                        withToken:account.credential.oauthToken
                                            error:&applyError];

        //
        // Handle Errors (Service, Token, etc)
        //
        if (applyError)
        {
            NSLog(@"Apply Error: %@", applyError);

            //
            // Parse Original Response from Singly
            //
            NSData *responseData = [applyError.userInfo[kSinglyResponseKey] dataUsingEncoding:NSUTF8StringEncoding];
            if (responseData == nil) {
                SinglyLog(@"Unhandled error: Response from singly was nil");
                NSError *responseError = [NSError errorWithDomain:@"com.singly.sdk" code:400 userInfo:@{NSLocalizedDescriptionKey:@"Unable to connect to server. Please try again."}];
                [self serviceDidFailAuthorizationWithError:responseError];
                dispatch_semaphore_signal(authorizationSemaphore);
                return;
            }
            id responseObject = [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:nil];

            //
            // Check for Facebook Errors
            //
            if (responseObject && [responseObject isKindOfClass:[NSDictionary class]] && responseObject[@"originalError"])
            {
                NSDictionary *facebookError = responseObject[@"originalError"][@"error"];
                NSLog(@"Facebook Error: %@", facebookError);

                //
                // Handle Token Errors
                //
                if ([facebookError[@"code"] intValue] == 190)
                {
                    SinglyLog(@"Facebook token is invalid. Attempting to renew credentials...");
                    [self.accountStore renewCredentialsForAccount:account
                                                  completion:^(ACAccountCredentialRenewResult renewResult, NSError *error)
                    {

                        // TODO Check for errors...
                        if (renewResult == ACAccountCredentialRenewResultFailed)
                        {
//                            NSLog(@"Failed Renewal");
                        }
                        else if (renewResult == ACAccountCredentialRenewResultRejected)
                        {
//                            NSLog(@"Renew rejected");

                            //
                            // If the user has removed the app, request authorization again.
                            //
                            if ([facebookError[@"error_subcode"] intValue] == 458)
                            {
                                [self requestNativeAuthorizationFromViewController:viewController
                                                                        withScopes:scopes];
                                return;
                            }
                        }
                        else if (renewResult == ACAccountCredentialRenewResultRenewed)
                        {
//                            NSLog(@"Renewed!");
                        }
                        NSError *applyError;
                        [SinglySession.sharedSession applyService:self.serviceIdentifier
                                                        withToken:account.credential.oauthToken
                                                            error:&applyError];

                        //
                        // If there was an error, there really isn't anything more
                        // that we can do. Inform the app that we cannot proceed.
                        //
                        if (applyError)
                        {
                            SinglyLog(@"Unhandled error: %@", applyError);
                            [self serviceDidFailAuthorizationWithError:applyError];
                            dispatch_semaphore_signal(authorizationSemaphore);
                            return;
                        }

                        //
                        // Otherwise, we are now authorized. Do not attempt any
                        // further authorizations.
                        //
                        _isAuthorized = YES;

						if (hasPublishStream) {
							NSMutableArray *newScopes = [@[@"real_publish_stream"] mutableCopy];
							[newScopes addObjectsFromArray:permissions];
							[self requestNativeAuthorizationFromViewController:viewController
																	withScopes:newScopes];
						}
						else
							[self serviceDidAuthorize];

                        dispatch_semaphore_signal(authorizationSemaphore);
                        return;
                    }];
                }

            }
            else
            {
                [self serviceDidFailAuthorizationWithError:applyError];
                dispatch_semaphore_signal(authorizationSemaphore);
                return;
            }
        }
        else
        {

            //
            // We are now authorized. Do not attempt any further authorizations.
            //
            _isAuthorized = YES;

			if (hasPublishStream) {
				NSMutableArray *newScopes = [@[@"real_publish_stream"] mutableCopy];
				[newScopes addObjectsFromArray:permissions];
				[self requestNativeAuthorizationFromViewController:viewController
														withScopes:newScopes];
			}
			else
            	[self serviceDidAuthorize];

            dispatch_semaphore_signal(authorizationSemaphore);
        }
    }];

    dispatch_semaphore_wait(authorizationSemaphore, DISPATCH_TIME_FOREVER);
    #if __IPHONE_OS_VERSION_MAX_ALLOWED < 60000
        dispatch_release(authorizationSemaphore);
    #endif
}

- (BOOL)requestApplicationAuthorization:(NSArray *)scopes
{
    NSArray *permissions = (scopes != nil) ? scopes : @[ @"email", @"user_location", @"user_birthday" ];
    NSMutableDictionary *params = [@{
        @"client_id": self.clientIdentifier,
        @"type": @"user_agent",
        @"redirect_uri": @"fbconnect://success",
        @"display": @"touch",
        @"sdk": @"ios",
        @"scope": [permissions componentsJoinedByString:@","]
    } mutableCopy];
    
    if (self.urlSchemeSuffix)
    {
        params[@"local_client_id"] = self.urlSchemeSuffix;
    }

    NSString *facebookAppURL = [NSString stringWithFormat:@"fbauth://authorize?%@", [params queryStringValue]];
    BOOL isAppInstalled = [[UIApplication sharedApplication] openURL:[NSURL URLWithString:facebookAppURL]];

    if (!isAppInstalled)
    {
        SinglyLog(@"Authorization via the Facebook app is not possible because the Facebook app is not installed.");
    }
    else
    {
        SinglyLog(@"Attempting to authorize via the installed Facebook app...");

		// Post a notification that the authorization is being performed via an app
		//
		[[NSNotificationCenter defaultCenter] postNotificationName:@"com.singly.notifications.isAuthorizingViaAppNotification"
															object:self];

        [SinglySession sharedSession].authorizingService = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleServiceAppliedNotification:)
                                                     name:kSinglyServiceAppliedNotification
                                                   object:nil];
    }

    return isAppInstalled;
}

@end
