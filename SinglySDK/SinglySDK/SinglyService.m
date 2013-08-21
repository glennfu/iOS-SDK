//
//  SinglyService.m
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

#import "SinglyConnection.h"
#import "SinglyConstants.h"
#import "SinglyLog.h"
#import "SinglyRequest.h"
#import "SinglyService.h"
#import "SinglyService+Internal.h"
#import "SinglySession.h"
#import "SinglySession+Internal.h"

@implementation SinglyService

@synthesize isAuthorized = _isAuthorized;
@synthesize completionHandler = _completionHandler;

+ (id)serviceWithIdentifier:(NSString *)serviceIdentifier
{

    // Normalize the Service Identifier
    serviceIdentifier = [SinglyService normalizeServiceIdentifier:serviceIdentifier];

    // Custom Service Implementation for Facebook
    if ([serviceIdentifier isEqualToString:@"facebook"])
        return [self facebookService];

    // Custom Service Implementation for Twitter
    else if ([serviceIdentifier isEqualToString:@"twitter"])
        return [self twitterService];

    SinglyService *serviceInstance = [[SinglyService alloc] initWithIdentifier:serviceIdentifier];
    return serviceInstance;

}

+ (SinglyFacebookService *)facebookService
{
    SinglyFacebookService *serviceInstance = [[SinglyFacebookService alloc] init];
    return serviceInstance;
}

+ (SinglyTwitterService *)twitterService
{
    SinglyTwitterService *serviceInstance = [[SinglyTwitterService alloc] init];
    return serviceInstance;
}

+ (NSString *)normalizeServiceIdentifier:(NSString *)serviceIdentifier
{
    serviceIdentifier = [serviceIdentifier lowercaseString];
    return serviceIdentifier;
}

- (id)initWithIdentifier:(NSString *)serviceIdentifier
{
    if (self = [self init])
    {
        serviceIdentifier = [SinglyService normalizeServiceIdentifier:serviceIdentifier];
        _serviceIdentifier = serviceIdentifier;
    }
    return self;
}

#pragma mark - Requesting Authorization

- (void)requestAuthorizationFromViewController:(UIViewController *)viewController
{
    [self requestAuthorizationFromViewController:viewController
                                      withScopes:nil
                                      completion:nil];
}

- (void)requestAuthorizationFromViewController:(UIViewController *)viewController
                                    completion:(SinglyServiceAuthorizationCompletionHandler)completionHandler
{
    [self requestAuthorizationFromViewController:viewController
                                      withScopes:nil
                                      completion:completionHandler];
}

- (void)requestAuthorizationFromViewController:(UIViewController *)viewController
                                    withScopes:(NSArray *)scopes
{
    [self requestAuthorizationFromViewController:viewController
                                      withScopes:scopes
                                      completion:nil];
}

- (void)requestAuthorizationFromViewController:(UIViewController *)viewController
                                    withScopes:(NSArray *)scopes
                                    completion:(SinglyServiceAuthorizationCompletionHandler)completionHandler
{
    _isAuthorized = NO;
    _completionHandler = completionHandler;

    [self requestAuthorizationViaSinglyFromViewController:viewController
                                               withScopes:scopes];
}

- (void)requestAuthorizationViaSinglyFromViewController:(UIViewController *)viewController
                                             withScopes:(NSArray *)scopes
{
    // Initialize the Login View Controller
    SinglyLoginViewController *loginViewController = [[SinglyLoginViewController alloc] initWithServiceIdentifier:self.serviceIdentifier];
    loginViewController.scopes = scopes;
    loginViewController.delegate = self;
    loginViewController.serviceName = [self.serviceIdentifier capitalizedString];

    // Present the Login View Controller
    [viewController presentViewController:loginViewController
                                 animated:YES
                               completion:nil];
}

#pragma mark - Service Disconnection

- (void)disconnect // DEPRECATED
{
    [self disconnectWithCompletion:nil];
}

- (BOOL)disconnect:(NSError **)error
{
    NSDictionary *serviceProfile = SinglySession.sharedSession.profiles[self.serviceIdentifier];

    // Prepare the Request
    SinglyRequest *request = [SinglyRequest requestWithEndpoint:@"profiles"];
    NSString *postString = [NSString stringWithFormat:@"delete=%@", [NSString stringWithFormat:@"%@@%@", serviceProfile[@"id"], self.serviceIdentifier]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];

    // Perform the Request
    NSError *requestError;
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    [connection performRequest:&requestError];

    // Check for Errors
    if (requestError)
    {
        if (error) *error = requestError;
        return NO;
    }

    // Update Profiles
    NSError *profilesError;
    [SinglySession.sharedSession updateProfiles:&profilesError];
    if (profilesError)
    {
        if (error) *error = profilesError;
        return NO;
    }

    return YES;
}

- (void)disconnectWithCompletion:(SinglyServiceDisconnectionCompletionHandler)completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *disconnectError;
        BOOL isSuccessful = [self disconnect:&disconnectError];

        if (completionHandler) dispatch_sync(currentQueue, ^{
            completionHandler(isSuccessful, disconnectError);
        });

    });
}

#pragma mark - Service Client Identifiers

- (NSString *)fetchClientIdentifier:(NSError **)error
{

    // If we already have the Client ID, do not attempt to fetch it again...
    if (self.clientIdentifier) return self.clientIdentifier;

    // Prepare the Request
    SinglyRequest *request = [[SinglyRequest alloc] initWithEndpoint:[NSString stringWithFormat:@"auth/%@/client_id/%@", SinglySession.sharedSession.clientID, self.serviceIdentifier]];
    request.isAuthorizedRequest = NO;

    // Perform the Request
    NSError *requestError;
    SinglyConnection *connection = [SinglyConnection connectionWithRequest:request];
    id responseObject = [connection performRequest:&requestError];

    // Check for Errors
    if (requestError)
    {
        SinglyLog(@"A request error occurred while attempting to fetch the client id from '%@': %@", request.URL, requestError);
        if (error) *error = requestError;
        return nil;
    }

    self.clientIdentifier = responseObject[self.serviceIdentifier];

    SinglyLog(@"Retrieved Client Identifier for '%@': %@", self.serviceIdentifier, self.clientIdentifier);

    return self.clientIdentifier;
}

- (void)fetchClientIdentifierWithCompletion:(SinglyFetchClientIdentifierCompletionBlock)completionHandler
{
    dispatch_queue_t currentQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSError *error;
        NSString *clientIdentifier = [self fetchClientIdentifier:&error];

        if (completionHandler) dispatch_sync(currentQueue, ^{
            completionHandler(clientIdentifier, error);
        });
        
    });
}

#pragma mark - Authorization Callbacks

- (void)serviceDidAuthorize
{

    //
    // Inform the Delegate
    //
    if (self.delegate && [self.delegate respondsToSelector:@selector(singlyServiceDidAuthorize:)])
        [self.delegate singlyServiceDidAuthorize:self];

    //
    // Call & Clear the Completion Handler
    //
    if (self.completionHandler)
    {
        self.completionHandler(YES, nil);
        _completionHandler = nil;
    }

}

- (void)serviceDidFailAuthorizationWithError:(NSError *)error
{

    //
    // Inform the Delegate
    //
    if (self.delegate && [self.delegate respondsToSelector:@selector(singlyService:didFailWithError:)])
        [self.delegate singlyService:self didFailWithError:error];

    //
    // Inform the Delegate w/Deprecated Method
    //
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (self.delegate && [self.delegate respondsToSelector:@selector(singlyServiceDidFail:withError:)])
        [self.delegate singlyServiceDidFail:self withError:error];
    #pragma clang diagnostic warning "-Wdeprecated-declarations"

    //
    // Call & Clear the Completion Handler
    //
    if (self.completionHandler)
    {
        self.completionHandler(NO, error);
        _completionHandler = nil;
    }
    
}

#pragma mark - Login View Controller Delegates

- (void)singlyLoginViewController:(SinglyLoginViewController *)controller
               didLoginForService:(NSString *)service
{

    //
    // Set Authorization State
    //
    _isAuthorized = YES;

    //
    // Call the Authorization Callback
    //
    [self serviceDidAuthorize];

}

- (void)singlyLoginViewController:(SinglyLoginViewController *)viewController
          errorLoggingInToService:(NSString *)serviceIdentifier
                        withError:(NSError *)error
{

    //
    // Set Authorization State
    //
    _isAuthorized = NO;

    //
    // Call the Failed Authorization Callback
    //
    [self serviceDidFailAuthorizationWithError:error];

}

#pragma mark - Notification Handlers

- (void)handleServiceAppliedNotification:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kSinglyServiceAppliedNotification object:nil];

    if (self.delegate && [self.delegate respondsToSelector:@selector(singlyServiceDidAuthorize:)])
        [self.delegate singlyServiceDidAuthorize:self];

    SinglySession.sharedSession.authorizingService = nil;
}

@end
