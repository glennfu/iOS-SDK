//
//  SinglyFacebookServiceTests.m
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

#import <OCMock/OCMock.h>
#import "SenTestCase+AsynchronousSupport.h"
#import "SenTestCase+Fixtures.h"

#import "SinglyService.h"
#import "SinglyService+Internal.h"
#import "SinglySession+Internal.h"
#import "SinglyTestURLProtocol.h"

#import "SinglyFacebookService+Internal.h"
#import "SinglyFacebookServiceTests.h"

@implementation SinglyFacebookServiceTests

- (void)setUp
{
    [super setUp];

    //
    // Initialize a test service instance for Facebook.
    //
    self.testService = [SinglyService facebookService];

    //
    // Set a bogus service client identifier. Fetching of client identifiers is
    // tested separately by `SinglyServiceTests`.
    //
    self.testService.clientIdentifier = @"000000000000000";

    //
    // Configure the Shared Session Instance with a bogus client identifier and
    // secret. These don't need to be valid because all of our interactions with
    // the Singly API will be canned or otherwise mocked.
    //
    SinglySession.sharedSession.clientID = @"test-client-id";
    SinglySession.sharedSession.clientSecret = @"test-client-secret";

    //
    // Register our custom URL protocol that will return canned responses for
    // requests to the Singly API.
    //
    [NSURLProtocol registerClass:[SinglyTestURLProtocol class]];
}

- (void)tearDown
{
    [super tearDown];

    self.testService = nil;

    [SinglySession.sharedSession resetSession];
    [SinglyTestURLProtocol reset];
}

#pragma mark - Mock Helpers

- (id)mockAccountStoreWithAccounts:(NSArray *)accounts
{
    ACAccountStore *accountStore = [[ACAccountStore alloc] init];
    id mockAccountStore = [OCMockObject partialMockForObject:accountStore];
    [[[mockAccountStore stub] andReturn:accounts] accountsWithAccountType:[OCMArg any]];
    return mockAccountStore;
}

- (id)mockAccount
{
    ACAccountStore *accountStore = [[ACAccountStore alloc] init];
    ACAccountType *testAccountType = [accountStore accountTypeWithAccountTypeIdentifier:@"com.apple.facebook"];
    ACAccountCredential *testCredentials = [[ACAccountCredential alloc] initWithOAuth2Token:@"test-access-token" refreshToken:@"test-refresh-token" expiryDate:[NSDate dateWithTimeIntervalSinceNow:86400]];
//    [testCredentials setValue:@"test-password" forKey:@"password"];
//    [testCredentials setValue:@"test-password" forKey:@"_password"];
//    [testCredentials performSelector:@selector(setPassword:) withObject:@"test-password"];
//    ACAccountCredential *testCredentials = [[ACAccountCredential alloc] performSelector:@selector(initWithPassword:) withObject:@"Foo"];
    ACAccount *mockAccount = [[ACAccount alloc] initWithAccountType:testAccountType];
    mockAccount.credential = testCredentials;
//    mockAccount.username = @"test-username";
//    [mockAccount setValue:@"test-password" forKey:@"password"];
//    [mockAccount setValue:@"Facebook" forKey:@"accountDescription"];
//    [mockAccount setValue:@"test-password" forKey:@"_password"];
    return mockAccount;
}

#pragma mark - Application-Based Authorization Tests

//
// Tests that an app that has been properly configured to both answer Facebook
// URL schemes and handle opens from those URLs by implementing the
// `application:openURL:sourceApplication:annotation:` method is properly
// recognized as being configured by the `isApplicationAuthorizationConfigured`
// method on `SinglyFacebookService`.
//
- (void)testApplicationBasedAuthorizationShouldBeAvailable
{
    NSArray *testURLTypes = @[
        @{ @"CFBundleURLSchemes": @[ @"custom-scheme" ] },
        @{ @"CFBundleURLSchemes": @[ @"fb000000000000000" ] }
    ];

    //
    // Mock the app delegate so that we can implement the delegate method
    // `application:openURL:sourceApplication:annotation:`.
    //
    id mockAppDelegate = [OCMockObject mockForProtocol:@protocol(UIApplicationDelegate)];
    id mockApplication = [OCMockObject mockForClass:[UIApplication class]];
    id mockApplicationInstance = [OCMockObject mockForClass:[UIApplication class]];
    [[mockAppDelegate stub] application:[OCMArg any] openURL:[OCMArg any] sourceApplication:[OCMArg any] annotation:[OCMArg any]];
    [[[mockApplicationInstance stub] andReturn:mockAppDelegate] delegate];
    [[[mockApplication stub] andReturn:mockApplicationInstance] sharedApplication];

    //
    // Mock the main bundle for the application so that we can override the
    // values found in Info.plist with values we want to use for testing.
    //
    id mockBundleInstance = [OCMockObject mockForClass:[NSBundle class]];
    id mockBundle = [OCMockObject mockForClass:[NSBundle class]];
    [[[mockBundleInstance stub] andReturn:testURLTypes] objectForInfoDictionaryKey:[OCMArg any]];
    [[[mockBundle stub] andReturn:mockBundleInstance] mainBundle];

    STAssertTrue([self.testService isAppAuthorizationConfigured], @"Facebook application authorization should be available.");

    [mockBundle stopMocking];
    [mockBundleInstance stopMocking];
    [mockApplicationInstance stopMocking];
    [mockApplication stopMocking];
    [mockAppDelegate stopMocking];
}

//
// Tests that the `isApplicationAuthorizationConfigured` method on
// `SinglyFacebookService` will return false if the app integrating the Singly
// SDK is not configured for the Facebook URL scheme (i.e. fb000000000000000).
//
- (void)testApplicationBasedAuthorizationShouldNotBeAvailableWhenURLSchemeIsMissing
{
    NSArray *testURLTypes = @[ @{ @"CFBundleURLSchemes": @[ @"custom-scheme" ] } ];

    //
    // Mock the app delegate so that we can implement the delegate method
    // `application:openURL:sourceApplication:annotation:`. Even though the
    // implemented method should not reach this check, we should keep it mocked
    // in case the method implementation changes.
    //
    id mockAppDelegate = [OCMockObject mockForProtocol:@protocol(UIApplicationDelegate)];
    id mockApplication = [OCMockObject mockForClass:[UIApplication class]];
    id mockApplicationInstance = [OCMockObject mockForClass:[UIApplication class]];
    [[mockAppDelegate stub] application:[OCMArg any] openURL:[OCMArg any] sourceApplication:[OCMArg any] annotation:[OCMArg any]];
    [[[mockApplicationInstance stub] andReturn:mockAppDelegate] delegate];
    [[[mockApplication stub] andReturn:mockApplicationInstance] sharedApplication];

    //
    // Mock the main bundle for the application so that we can override the
    // values found in Info.plist with values we want to use for testing.
    //
    id mockBundleInstance = [OCMockObject mockForClass:[NSBundle class]];
    [[[mockBundleInstance stub] andReturn:testURLTypes] objectForInfoDictionaryKey:[OCMArg any]];
    id mockBundle = [OCMockObject mockForClass:[NSBundle class]];
    [[[mockBundle stub] andReturn:mockBundleInstance] mainBundle];

    STAssertFalse([self.testService isAppAuthorizationConfigured], @"Facebook application authorization should not be available.");
    
    [mockBundle stopMocking];
    [mockBundleInstance stopMocking];
    [mockApplicationInstance stopMocking];
    [mockApplication stopMocking];
    [mockAppDelegate stopMocking];
}

//
// Tests that the `isApplicationAuthorizationConfigured` method on
// `SinglyFacebookService` will return false if the app integrating the Singly
// SDK has not implemented the `application:openURL:sourceApplication:annotation:`
// method in the application delegate.
//
- (void)testApplicationBasedAuthorizationShouldNotBeAvailableWhenAppDelegateMethodIsMissing
{
    NSArray *testURLTypes = @[ @{ @"CFBundleURLSchemes": @[ @"custom-scheme" ] } ];

    //
    // Mock the main bundle for the application so that we can override the
    // values found in Info.plist with values we want to use for testing.
    //
    id mockBundleInstance = [OCMockObject mockForClass:[NSBundle class]];
    [[[mockBundleInstance stub] andReturn:testURLTypes] objectForInfoDictionaryKey:[OCMArg any]];
    id mockBundle = [OCMockObject mockForClass:[NSBundle class]];
    [[[mockBundle stub] andReturn:mockBundleInstance] mainBundle];

    STAssertFalse([self.testService isAppAuthorizationConfigured], @"Facebook application authorization should not be available.");

    [mockBundle stopMocking];
    [mockBundleInstance stopMocking];
}

//
// Tests that the `handleOpenURL:` method on `SinglySession` will return true
// for Facebook URLs.
//
- (void)testHandleOpenURLShouldRecognizeFacebookURLs
{
    NSURL *testURL = [NSURL URLWithString:@"fb000000000000000://foo"];

    STAssertTrue([SinglySession.sharedSession handleOpenURL:testURL], @"Facebook URLs should be handled.");
}

//
// Tests that when the user cancels a login from the launched Facebook app that
// the delegate is informed that the authorization failed.
//
- (void)testCanceledAuthorizationViaFacebookAppShouldInformDelegate
{
    NSURL *testURL = [NSURL URLWithString:@"fb000000000000000://authorize"];

    //
    // Mock an object to act as the service delegate.
    //
    id mockServiceDelegate = [OCMockObject mockForProtocol:@protocol(SinglyServiceDelegate)];
    [[mockServiceDelegate expect] singlyService:[OCMArg any] didFailWithError:[OCMArg isNil]];
    [[mockServiceDelegate expect] singlyServiceDidFail:[OCMArg any] withError:[OCMArg isNil]]; // DEPRECATED

    //
    // Set our service delegate mock as the delegate for the Facebook service
    // instance we are testing.
    self.testService.delegate = mockServiceDelegate;

    //
    // Set the Facebook service instance as the currently authorizing service on
    // the shared session.
    //
    SinglySession.sharedSession.authorizingService = self.testService;

    //
    // Perform the test and verify that the delegate methods were called.
    //
    [SinglySession.sharedSession handleOpenURL:testURL];
    [mockServiceDelegate verify];
}

//
// Tests that when the user cancels a login from the launched Facebook app that
// the completion handler is called.
//
- (void)testCanceledAuthorizationViaFacebookAppShouldCallCompletionHandler
{
    __block BOOL isComplete = NO;
    NSURL *testURL = [NSURL URLWithString:@"fb000000000000000://authorize"];

    //
    // Set a custom completion handler on the service instance so that we can
    // ensure that it was called.
    //
    SinglyServiceAuthorizationCompletionHandler testCompletionHandler = ^(BOOL isSuccessful, NSError *error) {
        STAssertFalse(isSuccessful, @"The isSuccessful parameter should be false.");
        isComplete = YES;
    };
    [self.testService setValue:testCompletionHandler forKey:@"_completionHandler"];

    //
    // Set the Facebook service instance as the currently authorizing service on
    // the shared session.
    //
    SinglySession.sharedSession.authorizingService = self.testService;

    //
    // Pass our test URL to the `handleOpenURL:` method on the session.
    //
    [SinglySession.sharedSession handleOpenURL:testURL];

    //
    // Verify that the delegate method was called after a short delay, since we
    // need to wait for the asynchronous operation of applying access token to
    // the Singly API to complete.
    //
    [self waitForCompletion:^{ return isComplete; }];
}

//
// Tests that when authorization fails in the launched Facebook app that the
// delegate is informed of the failure.
//
- (void)testFailedAuthorizationViaFacebookAppShouldInformDelegate
{
    NSURL *testURL = [NSURL URLWithString:@"fb000000000000000://authorize#code=test-code&access_token=test-access-token&expires_in=12345"];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply-invalid"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock an object to act as the service delegate.
    //
    id mockServiceDelegate = [OCMockObject mockForProtocol:@protocol(SinglyServiceDelegate)];
    [[mockServiceDelegate expect] singlyService:[OCMArg any] didFailWithError:[OCMArg any]];
    [[mockServiceDelegate expect] singlyServiceDidFail:[OCMArg any] withError:[OCMArg any]]; // DEPRECATED

    //
    // Set our service delegate mock as the delegate for the Facebook service
    // instance we are testing.
    self.testService.delegate = mockServiceDelegate;

    //
    // Set the Facebook service instance as the currently authorizing service on
    // the shared session.
    //
    SinglySession.sharedSession.authorizingService = self.testService;

    //
    // Pass our test URL to the `handleOpenURL:` method on the session.
    //
    [SinglySession.sharedSession handleOpenURL:testURL];

    //
    // Verify that the delegate method was called after a short delay, since we
    // need to wait for the asynchronous operation of applying access token to
    // the Singly API to complete.
    //
    [self waitForVerifiedMock:mockServiceDelegate delay:1.0];
}

//
// Tests that when authorization fails in the launched Facebook app that the
// completion handler is called.
//
- (void)testFailedAuthorizationViaFacebookAppShouldCallCompletionHandler
{
    __block BOOL isComplete = NO;
    NSURL *testURL = [NSURL URLWithString:@"fb000000000000000://authorize#code=test-code&access_token=test-access-token&expires_in=12345"];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply-invalid"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Set a custom completion handler on the service instance so that we can
    // ensure that it was called.
    //
    SinglyServiceAuthorizationCompletionHandler testCompletionHandler = ^(BOOL isSuccessful, NSError *error) {
        STAssertFalse(isSuccessful, @"The isSuccessful parameter should be false.");
        isComplete = YES;
    };
    [self.testService setValue:testCompletionHandler forKey:@"_completionHandler"];

    //
    // Set the Facebook service instance as the currently authorizing service on
    // the shared session.
    //
    SinglySession.sharedSession.authorizingService = self.testService;

    //
    // Pass our test URL to the `handleOpenURL:` method on the session.
    //
    [SinglySession.sharedSession handleOpenURL:testURL];

    //
    // Verify that the delegate method was called after a short delay, since we
    // need to wait for the asynchronous operation of applying access token to
    // the Singly API to complete.
    //
    [self waitForCompletion:^{ return isComplete; }];
}


#pragma mark - Integrated Authorization Tests

//
// Tests that integrated authorization is available on devices where the user is
// signed into Facebook using the integrated support offered in iOS 6+.
//
- (void)testIntegratedAuthorizationShouldBeAvailable
{
    //
    // Mock the app delegate so that we can implement the delegate method
    // `application:openURL:sourceApplication:annotation:`.
    //
    ACAccountStore *accountStore = [[ACAccountStore alloc] init];
    id mockAccountStore = [OCMockObject partialMockForObject:accountStore];
    [[[mockAccountStore stub] andReturn:@[]] accountsWithAccountType:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    STAssertTrue([self.testService isNativeAuthorizationConfigured], @"Facebook integrated authorization should be available.");
}

//
// Tests that integrated authorization should not be available on devices where
// the user is not yet authenticated with Facebook using the integrated support
// offered in iOS 6+.
//
- (void)testIntegratedAuthorizationShouldNotBeAvailableWhenDeviceIsNotAuthenticatedWithFacebook
{
    //
    // Mock the app delegate so that we can implement the delegate method
    // `application:openURL:sourceApplication:annotation:`.
    //
    ACAccountStore *accountStore = [[ACAccountStore alloc] init];
    id mockAccountStore = [OCMockObject partialMockForObject:accountStore];
    [[[mockAccountStore stub] andReturn:nil] accountsWithAccountType:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    STAssertFalse([self.testService isNativeAuthorizationConfigured], @"Facebook integrated authorization should not be available.");
}

//
// Ensure that when the user cancels an integrated Facebook authorization
// request that the service delegate is informed of the failure.
//
- (void)testCanceledIntegratedAuthorizationShouldInformDelegate
{
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock the account store with a valid account, but force it to return
    // an error to symbolize the user canceling the request.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(NO, [[NSError alloc] init]);
    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];    
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Mock an object to act as the service delegate.
    //
    id mockServiceDelegate = [OCMockObject mockForProtocol:@protocol(SinglyServiceDelegate)];
    [[mockServiceDelegate expect] singlyService:[OCMArg any] didFailWithError:[OCMArg any]];
    [[mockServiceDelegate expect] singlyServiceDidFail:[OCMArg any] withError:[OCMArg any]]; // DEPRECATED

    //
    // Set our service delegate mock as the delegate for the Facebook service
    // instance we are testing.
    self.testService.delegate = mockServiceDelegate;

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                        withScopes:nil];

    //
    // Verify that the delegate method was called after a short delay.
    //
    [self waitForVerifiedMock:mockServiceDelegate delay:1.0];
}

//
// Ensure that when the user cancels an integrated Facebook authorization
// request that the completion handler is called.
//
- (void)testCanceledIntegratedAuthorizationShouldCallCompletionHandler
{
    __block BOOL isComplete = NO;
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock the account store with a valid account, but force it to return
    // an error to symbolize the user canceling the request.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(NO, [[NSError alloc] init]);
    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Set a custom completion handler on the service instance so that we can
    // ensure that it was called.
    //
    SinglyServiceAuthorizationCompletionHandler testCompletionHandler = ^(BOOL isSuccessful, NSError *error) {
        STAssertFalse(isSuccessful, @"The isSuccessful parameter should be false.");
        isComplete = YES;
    };
    [self.testService setValue:testCompletionHandler forKey:@"_completionHandler"];

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                        withScopes:nil];

    //
    // Verify that the completion handler was called by waiting for the
    // isComplete variable value to be set to true.
    //
    [self waitForCompletion:^{ return isComplete; }];
}

//
// Tests that a failed authorization attempt, that is, an attempt where an
// error was returned by the Singly API, informs the delegate.
//
- (void)testFailedIntegratedAuthorizationShouldInformDelegate
{
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply-invalid"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock the account store with a valid account and return with success.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(YES, nil);
    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Mock an object to act as the service delegate.
    //
    id mockServiceDelegate = [OCMockObject mockForProtocol:@protocol(SinglyServiceDelegate)];
    [[mockServiceDelegate expect] singlyService:[OCMArg any] didFailWithError:[OCMArg any]];
    [[mockServiceDelegate expect] singlyServiceDidFail:[OCMArg any] withError:[OCMArg any]]; // DEPRECATED

    //
    // Set our service delegate mock as the delegate for the Facebook service
    // instance we are testing.
    self.testService.delegate = mockServiceDelegate;

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                        withScopes:nil];

    //
    // Verify that the delegate method was called after a short delay.
    //
    [self waitForVerifiedMock:mockServiceDelegate delay:1.0];
}

//
// Tests that a failed authorization attempt, that is, an attempt where an
// error was returned by the Singly API, calls the completion handler.
//
- (void)testFailedIntegratedAuthorizationShouldCallCompletionHandler
{
    __block BOOL isComplete = NO;
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply-invalid"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock the account store with a valid account and return with success.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(YES, nil);
    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Set a custom completion handler on the service instance so that we can
    // ensure that it was called.
    //
    SinglyServiceAuthorizationCompletionHandler testCompletionHandler = ^(BOOL isSuccessful, NSError *error) {
        STAssertFalse(isSuccessful, @"The isSuccessful parameter should be false.");
        STAssertNotNil(error, @"The error parameter should not be nil.");
        isComplete = YES;
    };
    [self.testService setValue:testCompletionHandler forKey:@"_completionHandler"];

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                        withScopes:nil];

    //
    // Verify that the completion handler was called by waiting for the
    // isComplete variable value to be set to true.
    //
    [self waitForCompletion:^{ return isComplete; }];
}

//
// Tests that a successful authorization via the integrated authorization
// support in iOS 6+ informs the delegate.
//
- (void)testSuccessfulIntegratedAuthorizationShouldInformDelegate
{
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock the account store with a valid account and return with success.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(YES, nil);
    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Mock an object to act as the service delegate.
    //
    id mockServiceDelegate = [OCMockObject mockForProtocol:@protocol(SinglyServiceDelegate)];
    [[mockServiceDelegate expect] singlyServiceDidAuthorize:[OCMArg any]];

    //
    // Set our service delegate mock as the delegate for the Facebook service
    // instance we are testing.
    self.testService.delegate = mockServiceDelegate;

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                       withScopes:nil];

    //
    // Verify that the delegate method was called after a short delay.
    //
    [self waitForVerifiedMock:mockServiceDelegate delay:1.0];
}

//
// Tests that a successful authorization via the integrated authorization
// support in iOS 6+ calls the completion handler.
//
- (void)testSuccessfulIntegratedAuthorizationShouldCallCompletionHandler
{
    __block BOOL isComplete = NO;
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Can the response from applying the passed token to the Singly API.
    //
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    //
    // Mock the account store with a valid account and return with success.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(YES, nil);
    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Set a custom completion handler on the service instance so that we can
    // ensure that it was called.
    //
    SinglyServiceAuthorizationCompletionHandler testCompletionHandler = ^(BOOL isSuccessful, NSError *error) {
        STAssertTrue(isSuccessful, @"The isSuccessful parameter should be true.");
        isComplete = YES;
    };
    [self.testService setValue:testCompletionHandler forKey:@"_completionHandler"];

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                        withScopes:nil];

    //
    // Verify that the completion handler was called by waiting for the
    // isComplete variable value to be set to true.
    //
    [self waitForCompletion:^{ return isComplete; }];
}

//
//
//
- (void)testShouldAttemptToRenewCredentials
{
    __block BOOL isComplete = NO;
    UIViewController *testViewController = [[UIViewController alloc] init];

    //
    // Create a mock for the account store.
    //
    id mockAccountStore = [self mockAccountStoreWithAccounts:@[ [self mockAccount] ]];
    [self.testService setValue:mockAccountStore forKey:@"_accountStore"];

    //
    // Mock the account store to return an error when attempting to apply an
    // access token that is no longer valid.
    //
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {

        //
        // Can the response from applying the passed token to the Singly API.
        //
        NSData *responseData = [self dataForFixture:@"auth-facebook-oauth-error-app-not-installed"];
        [SinglyTestURLProtocol setCannedResponseData:responseData];
        
        void (^grantBlock)(BOOL granted, NSError *error) = nil;
        [invocation getArgument:&grantBlock atIndex:4];
        grantBlock(YES, nil);

    }] requestAccessToAccountsWithType:[OCMArg any] options:[OCMArg any] completion:[OCMArg any]];

    //
    // Mock the account store to return a successful response to a credentials
    // renewal request.
    //
    [[[mockAccountStore stub] andDo:^(NSInvocation *invocation) {

        //
        // Next, we need to can a successful response to the apply.
        //
        NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
        [SinglyTestURLProtocol setCannedResponseData:responseData];

        void (^renewBlock)(ACAccountCredentialRenewResult renewResult, NSError *error) = nil;
        [invocation getArgument:&renewBlock atIndex:3];
        renewBlock(ACAccountCredentialRenewResultRenewed, nil);

    }] renewCredentialsForAccount:[OCMArg any] completion:[OCMArg any]];

    //
    // Set a custom completion handler on the service instance so that we can
    // ensure that it was called.
    //
    SinglyServiceAuthorizationCompletionHandler testCompletionHandler = ^(BOOL isSuccessful, NSError *error) {
        STAssertTrue(isSuccessful, @"The isSuccessful parameter should be true.");
        isComplete = YES;
    };
    [self.testService setValue:testCompletionHandler forKey:@"_completionHandler"];

    //
    // Perform the test by requesting integrated authorization.
    //
    [self.testService requestNativeAuthorizationFromViewController:testViewController
                                                        withScopes:nil];

    //
    // Verify that the completion handler was called by waiting for the
    // isComplete variable value to be set to true.
    //
    [self waitForCompletion:^{ return isComplete; }];
}

@end
