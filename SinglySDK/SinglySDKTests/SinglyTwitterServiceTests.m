//
//  SinglyTwitterServiceTests.m
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

#import "SenTestCase+AsynchronousSupport.h"
#import "SenTestCase+Fixtures.h"

#import "SinglyService.h"
#import "SinglyService+Internal.h"
#import "SinglyTestURLProtocol.h"

#import "SinglyTwitterService+Internal.h"
#import "SinglyTwitterServiceTests.h"

@implementation SinglyTwitterServiceTests

- (void)setUp
{
    [super setUp];

    //
    // Initialize a test service instance for Twitter.
    //
    self.testService = [SinglyService twitterService];

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
    ACAccountType *testAccountType = [accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    ACAccountCredential *testCredentials = [[ACAccountCredential alloc] initWithOAuth2Token:@"test-access-token" refreshToken:@"test-refresh-token" expiryDate:[NSDate dateWithTimeIntervalSinceNow:86400]];
    ACAccount *mockAccount = [[ACAccount alloc] initWithAccountType:testAccountType];
    mockAccount.credential = testCredentials;
    return mockAccount;
}

#pragma mark - Integrated Authorization Tests

//
// Tests that integrated authorization is available on devices where the user is
// signed into Twitter using the integrated support offered in iOS 5+.
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

    STAssertTrue([self.testService isNativeAuthorizationConfigured], @"Twitter integrated authorization should be available.");
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

@end
