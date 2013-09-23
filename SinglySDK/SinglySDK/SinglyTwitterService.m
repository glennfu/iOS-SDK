//
//  SinglyTwitterService.m
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

#import <Twitter/Twitter.h>

#import "NSDictionary+QueryString.h"
#import "NSString+URLEncoding.h"

#import "SinglyActivityIndicatorView.h"
#import "SinglyAlertView.h"
#import "SinglyConnection.h"
#import "SinglyLog.h"
#import "SinglyRequest.h"
#import "SinglyService+Internal.h"
#import "SinglySession.h"
#import "SinglyTwitterService.h"
#import "SinglyTwitterService+Internal.h"

@implementation SinglyTwitterService

@synthesize isAborted = _isAborted;
@synthesize isAuthorized = _isAuthorized;
@synthesize completionHandler = _completionHandler;

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
    return @"twitter";
}

- (BOOL)isNativeAuthorizationConfigured
{
    BOOL isConfigured = NO;

    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];

    if ([accounts respondsToSelector:@selector(count)] && [accounts count] > 0)
        isConfigured = YES;

    if (!isConfigured)
        SinglyLog(@"Integrated Twitter auth is not available because this device is not signed in to Twitter.");

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
        // Step 2 - Attempt Native Authorization
        //
        if (self.clientIdentifier && !self.isAuthorized && !self.isAborted && [self isNativeAuthorizationConfigured])
            [self requestNativeAuthorizationFromViewController:viewController
                                                    withScopes:scopes];

        //
        // Step 3 - Fallback to Singly Authorization
        //
        if (!self.isAuthorized && !self.isAborted)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self requestAuthorizationViaSinglyFromViewController:viewController
                                                           withScopes:scopes];
            });
        }

    });

}

- (void)requestNativeAuthorizationFromViewController:(UIViewController *)viewController
                                          withScopes:(NSArray *)scopes
{
    dispatch_semaphore_t authorizationSemaphore = dispatch_semaphore_create(0);
    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];

    if (!accountType)
    {
        SinglyLog(@"Native Twitter authorization is not available because this device is not signed into Twitter.");
        return;
    }
    
    //
    // Post a notification that the authorization is being performed.
    //
    [[NSNotificationCenter defaultCenter] postNotificationName:kSinglyServiceIsAuthorizingNotification
                                                        object:self];


    [self.accountStore requestAccessToAccountsWithType:accountType
                                               options:nil
                                            completion:^(BOOL granted, NSError *accessError)
    {

        //
        // Check for Access to Accounts
        //
        if (!granted)
        {
            SinglyLog(@"Access to the Twitter accounts on the device was denied.");

            //
            // If there was an error object, it means that the user denied
            // access, so we should be in an aborted state...
            //
            if (accessError)
            {
                _isAborted = YES;

                if (self.delegate && [self.delegate respondsToSelector:@selector(singlyServiceDidFail:withError:)])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate singlyService:self didFailWithError:accessError];
                    });
                }
            }

            //
            // If the error is nil, it means access was already denied (in
            // Settings) so we should fall-back to the next method.
            //
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
                SinglyLog(@"Native Twitter authorization is not available because this device is not signed into Twitter.");
                dispatch_semaphore_signal(authorizationSemaphore);
                return;
            }

            SinglyLog(@"Unhandled error! %@", accessError);

            //
            // Inform the Delegate
            //
            if (self.delegate && [self.delegate respondsToSelector:@selector(singlyServiceDidFail:withError:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate singlyService:self didFailWithError:accessError];
                });
            }

            //
            // Call the Completion Handler
            //
            if (self.completionHandler)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.completionHandler(NO, accessError);
                });
            }

            dispatch_semaphore_signal(authorizationSemaphore);
            return;
        }

        //
        // Select the Account to Authorize
        //
        NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];
        __block ACAccount *account;
        if (accounts.count > 1)
        {
            if (self.delegate && [self.delegate respondsToSelector:@selector(accountForTwitterAuthorization:)])
            {
                account = [self.delegate accountForTwitterAuthorization:accounts];
            }
            else
            {
                SinglyLog(@"You must implement the accountForTwitterAuthorization: delegate method and return the account to authorize.");
                dispatch_semaphore_signal(authorizationSemaphore);
                return;
            }
        }
        else
        {
            account = [accounts lastObject];
        }

        //
        // Request Access Token from Twitter
        //
        [self fetchAccessTokenForAccount:account completion:^(NSDictionary *accessToken, NSError *error)
        {

            // TODO Check for errors!

            id applyServiceHandler = ^(BOOL isSuccessful, NSError *applyError)
            {

                // TODO Check for errors!

                //
                // We are now authorized. Do not attempt any further authorizations.
                //
                _isAuthorized = YES;

                //
                // Inform the Delegate
                //
                if (self.delegate && [self.delegate respondsToSelector:@selector(singlyServiceDidAuthorize:)])
                {
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        [self.delegate singlyServiceDidAuthorize:self];
                    });
                }

                //
                // Call the Completion Handler
                //
                if (self.completionHandler)
                {
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        self.completionHandler(YES, nil);
                    });
                }

                dispatch_semaphore_signal(authorizationSemaphore);
            };

            //
            // Apply Service to Singly
            //
            [SinglySession.sharedSession applyService:self.serviceIdentifier
                                            withToken:accessToken[@"oauth_token"]
                                          tokenSecret:accessToken[@"oauth_token_secret"]
                                           completion:applyServiceHandler];
        }];
    }];

    dispatch_semaphore_wait(authorizationSemaphore, DISPATCH_TIME_FOREVER);
    #if __IPHONE_OS_VERSION_MAX_ALLOWED < 60000
        dispatch_release(authorizationSemaphore);
    #endif
}

#pragma mark - Reverse Authentication

- (NSString *)fetchReverseAuthParameters:(NSError **)error
{
    // Prepare the Request
    SinglyRequest *request = [SinglyRequest requestWithEndpoint:[NSString stringWithFormat:@"auth/%@/reverse_auth_parameters/%@", SinglySession.sharedSession.clientID, self.serviceIdentifier]];
    request.isAuthorizedRequest = NO;

    // Perform the Request
    NSError *requestError;
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    id responseObject = [connection performRequest:&requestError];

    // Check for Errors
    if (requestError)
    {
        SinglyLog(@"A request error occurred while attempting to fetch the reverse access token from '%@': %@", request.URL, requestError);
        if (error) *error = requestError;
        return nil;
    }

    NSString *reverseAuthParameters = responseObject[self.serviceIdentifier];

    SinglyLog(@"Retrieved Reverse Auth Parameters for '%@': %@", self.serviceIdentifier, reverseAuthParameters);

    return reverseAuthParameters;
}

- (void)fetchReverseAuthParametersWithCompletion:(SinglyAuthParametersCompletionBlock)completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        NSString *parameters = [self fetchReverseAuthParameters:&error];

        if (completionHandler) dispatch_sync(currentQueue, ^{
            completionHandler(parameters, error);
        });
        
    });
}

#pragma mark - Access Tokens

- (NSDictionary *)fetchAccessTokenForAccount:(ACAccount *)account error:(NSError **)error
{
    dispatch_semaphore_t accessTokenSemaphore = dispatch_semaphore_create(0);
    __block NSDictionary *accessTokenDictionary;

    // Configure the Request
    NSURL *accessTokenURL = [NSURL URLWithString:@"https://api.twitter.com/oauth/access_token"];
    NSString *reverseAuthParameters = [self fetchReverseAuthParameters:nil];
    NSDictionary *accessTokenParameters = @{
        @"x_reverse_auth_target": self.clientIdentifier,
        @"x_reverse_auth_parameters": reverseAuthParameters
    };
    TWRequest *accessTokenRequest = [[TWRequest alloc] initWithURL:accessTokenURL
                                                        parameters:accessTokenParameters
                                                     requestMethod:TWRequestMethodPOST];

    // Set the Account
    [accessTokenRequest setAccount:account];

    // Perform the Request
    [accessTokenRequest performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error)
    {
        NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        NSDictionary *responseDictionary = [NSDictionary dictionaryWithQueryString:responseString];

        accessTokenDictionary = responseDictionary;

        dispatch_semaphore_signal(accessTokenSemaphore);
    }];

    dispatch_semaphore_wait(accessTokenSemaphore, DISPATCH_TIME_FOREVER);
    #if __IPHONE_OS_VERSION_MAX_ALLOWED < 60000
        dispatch_release(accessTokenSemaphore);
    #endif

    return accessTokenDictionary;
}

- (void)fetchAccessTokenForAccount:(ACAccount *)account
                        completion:(SinglyTwitterAccessTokenCompletionBlock)completionHandler
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error;
        NSDictionary *accessToken = [self fetchAccessTokenForAccount:account error:&error];

        if (completionHandler) completionHandler(accessToken, error);
    });
}

@end
