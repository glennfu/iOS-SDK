//
//  SinglySession.m
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

#import <AddressBook/AddressBook.h>
#import <AddressBookUI/AddressBookUI.h>

#import "NSURL+AccessToken.h"

#import "SinglyAlertView.h"
#import "SinglyConnection.h"
#import "SinglyConstants.h"
#import "SinglyFacebookService.h"
#import "SinglyKeychainItemWrapper.h"
#import "SinglyLog.h"
#import "SinglyRequest.h"
#import "SinglySession.h"
#import "SinglySession+Internal.h"
#import "SinglyService+Internal.h"

static SinglySession *sharedInstance = nil;

@implementation SinglySession

+ (SinglySession *)sharedSession
{
    static dispatch_once_t queue;
    dispatch_once(&queue, ^{
        sharedInstance = [[SinglySession alloc] init];
    });

    return sharedInstance;
}

+ (SinglySession *)sharedSessionInstance
{
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        _accessTokenWrapper = [[SinglyKeychainItemWrapper alloc] initWithIdentifier:kSinglyAccessTokenKey accessGroup:nil];
        _baseURL = kSinglyBaseURL;
    }
    return self;
}

#pragma mark - Session Configuration

- (NSString *)accountID
{
    NSString *theAccountID = [self.accessTokenWrapper objectForKey:(__bridge id)kSecAttrAccount];
    if (theAccountID.length == 0) theAccountID = nil;
    return theAccountID;
}

- (void)setAccountID:(NSString *)accountID
{
    [self.accessTokenWrapper setObject:accountID forKey:(__bridge id)kSecAttrAccount];
}

- (NSString *)accessToken
{
    NSString *theAccessToken = [self.accessTokenWrapper objectForKey:(__bridge id)kSecValueData];
    if (theAccessToken.length == 0) theAccessToken = nil;
    return theAccessToken;
}

- (void)setAccessToken:(NSString *)accessToken
{
    [self.accessTokenWrapper setObject:accessToken forKey:(__bridge id)kSecValueData];
}

#pragma mark - Session Management

- (BOOL)isReady
{
    BOOL ready = YES;

    // The access token and account id should be set...
    if (!self.accessToken) ready = NO;
    if (!self.accountID) ready = NO;

    // The loaded profile id should match the account id...
    if (self.profile && ![self.profile[@"id"] isEqualToString:self.accountID])
        ready = NO;

    return ready;
}

- (BOOL)startSession:(NSError **)error
{
    // Raise an error if the Client ID and Client Secret have not been provided!
    if (!self.clientID || !self.clientSecret)
        [NSException raise:kSinglyCredentialsMissingException
                    format:@"%s: missing client id and/or client secret!", __PRETTY_FUNCTION__];

    // Ensure that we have an Access Token and Account ID...
    if (!self.accountID || !self.accessToken)
        return NO;

    // Update Profiles
    NSError *updateProfilesError;
    BOOL isSuccessful = [self updateProfiles:&updateProfilesError];

    // Handle Errors
    if (!isSuccessful)
    {
        SinglyLog(@"An error occurred while updating profiles: %@", updateProfilesError);
        if (error) *error = updateProfilesError;
    }

    // Handle Success
    else
    {
        // Post Notification
        [[NSNotificationCenter defaultCenter] postNotificationName:kSinglySessionStartedNotification
                                                            object:nil];
    }

    return isSuccessful;
}

- (void)startSessionWithCompletion:(SinglySessionCompletionBlock)completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        // Start the Session
        NSError *sessionStartError;
        BOOL isSuccessful = [self startSession:&sessionStartError];

        // Handle Errors
        if (sessionStartError)
            SinglyLog(@"An error occurred while starting the session: %@", sessionStartError);

        // Call the Completion Handler
        if (completionHandler) dispatch_sync(currentQueue, ^{
            completionHandler(isSuccessful, sessionStartError);
        });

    });
}

- (void)startSessionWithCompletionHandler:(SinglySessionCompletionBlock)completionHandler // DEPRECATED
{
    [self startSessionWithCompletion:completionHandler];
}

- (BOOL)resetSession
{

    // Reset Access Token and Account ID
    self.accessToken = nil;
    self.accountID = nil;

    // Reset the Keychain Item
    [self.accessTokenWrapper resetKeychainItem];

    // Reset Profiles
    [self resetProfiles];

    // Post Notification
    [[NSNotificationCenter defaultCenter] postNotificationName:kSinglySessionResetNotification
                                                        object:nil];

    return YES;

}

- (BOOL)removeAccount:(NSError **)error
{

    // Prepare the Request
    SinglyRequest *request = [SinglyRequest requestWithEndpoint:@"profiles"];
    request.HTTPMethod = @"DELETE";

    // Perform the Request
    NSError *requestError;
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    [connection performRequest:&requestError];

    // Check for Errors
    if (requestError)
    {
        SinglyLog(@"A request error occurred: %@", requestError.localizedDescription);
        if (error) *error = requestError;
        return NO;
    }

    [self resetSession];

    return YES;

}

- (void)removeAccountWithCompletion:(SinglyRemoveAccountCompletionBlock)completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        BOOL isSuccessful = [self removeAccount:&error];

        dispatch_sync(currentQueue, ^{
            completionHandler(isSuccessful, error);
        });
        
    });
}

- (void)requestAccessTokenWithCode:(NSString *)code // DEPRECATED
{
    [self requestAccessTokenWithCode:code completion:nil];
}

- (NSString *)requestAccessTokenWithCode:(NSString *)code error:(NSError **)error
{

    // Prepare the Request
    SinglyRequest *request = [SinglyRequest requestWithEndpoint:@"oauth/access_token"];
    request.HTTPMethod = @"POST";
    request.parameters = @{
        @"code" : code,
        @"client_id" : self.clientID,
        @"client_secret" : self.clientSecret
    };

    // Perform the Request
    NSError *requestError;
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    id responseObject = [connection performRequest:&requestError];

    // Check for Errors
    if (requestError)
    {
        SinglyLog(@"A request error occurred: %@", requestError.localizedDescription);
        if (error) *error = requestError;
        return nil;
    }

    // Persist the Access Token and Account ID
    self.accessToken = responseObject[@"access_token"];
    self.accountID = responseObject[@"account"];

    return self.accessToken;
}

- (void)requestAccessTokenWithCode:(NSString *)code
                        completion:(SinglyAccessTokenCompletionBlock)completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        NSString *accessToken = [self requestAccessTokenWithCode:code error:&error];

        dispatch_sync(currentQueue, ^{
            completionHandler(accessToken, error);
        });

    });
}

#pragma mark - Profile Management

- (BOOL)updateProfiles:(NSError **)error
{
    NSError *requestError;
    SinglyRequest *request = [SinglyRequest requestWithEndpoint:@"profile" andParameters:@{ @"auth" : @"true" }];
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    id responseObject = [connection performRequest:&requestError];

    // Check for invalid or expired tokens...
    if (requestError)
    {
        SinglyLog(@"An error occurred while requesting profiles: %@", requestError);

        // Reset Profiles
        _profile = nil;
        _profiles = nil;

        // If the access token has become invalid, reset the session...
        if ([requestError.domain isEqualToString:kSinglyErrorDomain] && requestError.code == kSinglyInvalidAccessTokenErrorCode)
        {
            SinglyLog(@"Access token is invalid or expired! Need to reauthorize...");
            [self resetSession];
        }

        if (error) *error = requestError;

        return NO;
    }

    NSDictionary *serviceProfiles = responseObject[@"services"];
    _profiles = serviceProfiles;
    _profile = responseObject;

    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kSinglySessionProfilesUpdatedNotification
                                                          object:self];
    });

    return YES;
}

- (void)updateProfilesWithCompletion:(void (^)(BOOL isSuccessful, NSError *error))completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        BOOL isSuccessful = [self updateProfiles:&error];

        if (completionHandler) dispatch_sync(currentQueue, ^{
            completionHandler(isSuccessful, error);
        });

    });
}

- (BOOL)resetProfiles
{

    // Reset Profiles
    _profile = nil;
    _profiles = nil;

    // Post Notification
    [[NSNotificationCenter defaultCenter] postNotificationName:kSinglySessionProfilesUpdatedNotification
                                                        object:self];

    return YES;

}

#pragma mark - Service Management

- (void)applyService:(NSString *)serviceIdentifier
           withToken:(NSString *)accessToken // DEPRECATED
{
    [self applyService:serviceIdentifier withToken:accessToken error:nil];
}

- (BOOL)applyService:(NSString *)serviceIdentifier
           withToken:(NSString *)accessToken
               error:(NSError **)error
{
    return [self applyService:serviceIdentifier withToken:accessToken tokenSecret:nil error:error];
}

- (BOOL)applyService:(NSString *)serviceIdentifier
           withToken:(NSString *)accessToken
         tokenSecret:(NSString *)tokenSecret
               error:(NSError **)error
{

    // Ensure that we have at least an access token.
    // TODO Return a Singly error saying there is no access token...
    if (!accessToken) return NO;

    // Prepare the Request Parameters
    NSMutableDictionary *requestParameters = [ @{
        @"client_id": self.clientID,
        @"client_secret": self.clientSecret,
        @"token": accessToken
    } mutableCopy ];

    // Set Token Secret (for OAuth 1.x)
    if (tokenSecret)
        requestParameters[@"token_secret"] = tokenSecret;
    
    // Set Account ID (if available)
    if (self.accountID)
        requestParameters[@"account"] = self.accountID;
	
	// If our account ID has expired, don't explode, just give us back the new one.
	requestParameters[@"verifyAccount"] = @"false";
	
    // Prepare the Request
    SinglyRequest *request = [SinglyRequest requestWithEndpoint:[NSString stringWithFormat:@"auth/%@/apply", serviceIdentifier]];
    request.parameters = requestParameters;

    // Perform the Request
    NSError *requestError;
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    id responseObject = [connection performRequest:&requestError];

    // Check for Errors
    if (requestError)
    {
        if (error) *error = requestError;
        return NO;
    }

    // Set Access Token and Account ID on the Shared Sesssion
    SinglySession.sharedSession.accessToken = responseObject[@"access_token"];
    SinglySession.sharedSession.accountID   = responseObject[@"account"];

    // Update Profiles
    NSError *profilesError;
    [SinglySession.sharedSession updateProfiles:&profilesError];
    if (profilesError)
    {
        if (error) *error = profilesError;
        return NO;
    }

    // Post Notification
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kSinglyServiceAppliedNotification
                                                          object:serviceIdentifier];
    });
    
    return YES;

}

- (void)applyService:(NSString *)serviceIdentifier
           withToken:(NSString *)accessToken
          completion:(SinglyApplyServiceCompletionBlock)completionHandler
{
    [self applyService:serviceIdentifier
             withToken:accessToken
           tokenSecret:nil
            completion:completionHandler];
}

- (void)applyService:(NSString *)serviceIdentifier
           withToken:(NSString *)accessToken
         tokenSecret:(NSString *)tokenSecret
          completion:(SinglyApplyServiceCompletionBlock)completionHandler
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        BOOL isApplied = [self applyService:serviceIdentifier withToken:accessToken tokenSecret:tokenSecret error:&error];

        if (completionHandler) completionHandler(isApplied, error);

    });
}

#pragma mark - URL Handling

- (BOOL)handleOpenURL:(NSURL *)url
{
    SinglyService *authorizingService = SinglySession.sharedSession.authorizingService;

    // Facebook
    if ([url.scheme hasPrefix:@"fb"])
    {
		// Clicking the app link from within the Facebook app triggers this
		if (!self.clientID || !self.clientSecret) return NO;

        SinglyFacebookService *service = (SinglyFacebookService *)authorizingService;
        NSString *accessToken = [url extractAccessToken];

        if (accessToken)
        {
            [SinglySession.sharedSession applyService:@"facebook"
                                            withToken:accessToken
                                           completion:^(BOOL isSuccessful, NSError *error)
            {
                if (isSuccessful)
                    [service serviceDidAuthorize];
                else
                    [service serviceDidFailAuthorizationWithError:error];
            }];
        }
        else
        {
            [service serviceDidFailAuthorizationWithError:nil];
        }

        return YES;
    }

    return NO;
}

@end

