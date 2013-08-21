//
//  SinglySessionTests.m
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

#import "SinglyConstants.h"
#import "SinglySession.h"
#import "SinglySession+Internal.h"
#import "SinglySessionTests.h"
#import "SinglyTestURLProtocol.h"

@implementation SinglySessionTests

- (void)setUp
{
    [super setUp];
    
    SinglySession.sharedSession.clientID = @"test-client-id";
    SinglySession.sharedSession.clientSecret = @"test-client-secret";

    [NSURLProtocol registerClass:[SinglyTestURLProtocol class]];
}

- (void)tearDown
{
    [super tearDown];
    
    [SinglySession.sharedSession resetSession];

    [SinglyTestURLProtocol reset];
}

#pragma mark -

- (void)testSharedSessionInitialization
{
    STAssertNotNil(SinglySession.sharedSessionInstance, @"The shared session instance was not initialized!");
    STAssertNotNil(SinglySession.sharedSession, @"The shared session was not initialized!");
}

- (void)testSubsequentCallsToSharedSessionShouldReturnSingletonInstance
{
    SinglySession *sessionOne = SinglySession.sharedSession;
    SinglySession *sessionTwo = SinglySession.sharedSession;

    STAssertEquals(sessionOne, sessionTwo, @"Both session pointers should be identical.");
}

- (void)testSessionShouldInitializeWithDefaults
{
    SinglySession *testSession = [[SinglySession alloc] init];

    STAssertEqualObjects(kSinglyAccessTokenKey,testSession.accessTokenWrapper.identifier, [NSString stringWithFormat:@"The accessTokenWrapper.identifier property should be equal to '%@'.", kSinglyAccessTokenKey]);
    STAssertEqualObjects(kSinglyBaseURL, testSession.baseURL, [NSString stringWithFormat:@"The baseURL property should equal '%@'.", kSinglyBaseURL]);
}

#pragma mark - Session Configuration

- (void)testShouldSetBaseURL
{
    SinglySession *testSession = [[SinglySession alloc] init];
    testSession.baseURL = @"http://localhost:8042";

    STAssertEqualObjects(testSession.baseURL, @"http://localhost:8042", @"The client id should match 'http://localhost:8042'.");
}

- (void)testShouldSetClientID
{
    SinglySession *testSession = [[SinglySession alloc] init];
    testSession.clientID = @"another-test-client-id";

    STAssertEqualObjects(testSession.clientID, @"another-test-client-id", @"The client id should match 'another-test-client-id'.");
}

- (void)testShouldSetClientSecret
{
    SinglySession *testSession = [[SinglySession alloc] init];
    testSession.clientSecret = @"another-test-client-secret";

    STAssertEqualObjects(testSession.clientSecret, @"another-test-client-secret", @"The client secret should match 'another-test-client-secret'.");
}

#pragma mark - Session Management

- (void)testShouldStartSession
{
    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    SinglySession.sharedSession.accountID = @"test-account-id";
    SinglySession.sharedSession.accessToken = @"test-access-token";

    BOOL isStarted = [SinglySession.sharedSession startSession:nil];

    STAssertTrue(isStarted, @"Session should be started.");
}

- (void)testShouldStartSessionWithCompletion
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    SinglySession.sharedSession.accountID = @"test-account-id";
    SinglySession.sharedSession.accessToken = @"test-access-token";

    [SinglySession.sharedSession startSessionWithCompletion:^(BOOL isReady, NSError *error) {
        STAssertTrue(isReady, @"The session should be started.");
        isComplete = YES;
    }];

    [self waitForCompletion:^{ return isComplete; }];
}

- (void)testStartSessionShouldPostNotification
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    id testObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kSinglySessionStartedNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *notification)
    {
        STAssertTrue(SinglySession.sharedSession.isReady, @"Session should be in a ready state.");
        isComplete = YES;
    }];

    // Start Session
    SinglySession.sharedSession.accessToken = @"S0meAcc3ssT0k3n";
    SinglySession.sharedSession.accountID = @"36b62eda6b24f323657c07c7bb764140";
    [SinglySession.sharedSession startSession:nil];

    [self waitForCompletion:^{ return isComplete; }];

    [[NSNotificationCenter defaultCenter] removeObserver:testObserver];
}

- (void)testShouldNotStartSessionWithMissingAccountCredentials
{
    [SinglySession.sharedSession resetSession];

    STAssertNil(SinglySession.sharedSession.accessToken, @"The accessToken property should be nil.");
    STAssertNil(SinglySession.sharedSession.accountID, @"The accessToken property should be nil.");

    BOOL isStarted = [SinglySession.sharedSession startSession:nil];

    STAssertFalse(isStarted, @"The session should not be started or ready.");
}

- (void)testShouldThrowExceptionForMissingSinglyCredentials
{
    SinglySession.sharedSession.clientID = nil;
    SinglySession.sharedSession.clientSecret = nil;

    STAssertThrowsSpecificNamed([SinglySession.sharedSession startSession:nil], NSException, kSinglyCredentialsMissingException, @"Should throw SinglyCredentialsMissingException when client id or client secret are missing!");
}

- (void)testShouldResetSession
{
    SinglySession.sharedSession.accessToken = @"test-access-token";
    SinglySession.sharedSession.accountID = @"test-account-id";

    STAssertEqualObjects(SinglySession.sharedSession.accessToken, @"test-access-token", @"The accessToken property should equal 'test-access-token'.");
    STAssertEqualObjects(SinglySession.sharedSession.accountID, @"test-account-id", @"The accountID property should equal 'test-account-id'.");

    [SinglySession.sharedSession resetSession];

    STAssertNil(SinglySession.sharedSession.accessToken, @"The accessToken property should be nil.");
    STAssertNil(SinglySession.sharedSession.accountID, @"The accountID property should be nil.");
    STAssertFalse(SinglySession.sharedSession.isReady, @"The session should not be in a ready state.");
    STAssertNil(SinglySession.sharedSession.profile, @"The profile property should be nil");
    STAssertNil(SinglySession.sharedSession.profiles, @"The profiles property should be nil");
}

- (void)testResetSessionShouldPostSessionResetNotification
{
    __block BOOL isComplete = NO;

    id testObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kSinglySessionResetNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *notification)
    {
        isComplete = YES;
    }];

    [SinglySession.sharedSession resetSession];

    [self waitForCompletion:^{ return isComplete; }];

    [[NSNotificationCenter defaultCenter] removeObserver:testObserver];
}

- (void)testResetSessionShouldPostProfilesUpdatedNotification
{
    __block BOOL isComplete = NO;

    id testObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kSinglySessionProfilesUpdatedNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *notification)
    {
        isComplete = YES;
    }];

    [SinglySession.sharedSession resetSession];
    
    [self waitForCompletion:^{ return isComplete; }];

    [[NSNotificationCenter defaultCenter] removeObserver:testObserver];
}

- (void)testShouldRemoveAccount
{
    NSData *responseData = [self dataForFixture:@"profiles-delete"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    SinglySession.sharedSession.accessToken = @"test-access-token";
    SinglySession.sharedSession.accountID = @"test-account-id";

    NSError *error;
    BOOL isSuccessful = [SinglySession.sharedSession removeAccount:&error];

    STAssertTrue(isSuccessful, @"The return value should be true.");
    STAssertNil(error, @"The error object should be nil.");
}

- (void)testShouldRemoveAccountWithCompletion
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"profiles-delete"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    SinglySession.sharedSession.accessToken = @"test-access-token";
    SinglySession.sharedSession.accountID = @"test-account-id";

    [SinglySession.sharedSession removeAccountWithCompletion:^(BOOL isSuccessful, NSError *error) {
        STAssertTrue(isSuccessful, @"The isSuccessful parameter should be true.");
        STAssertNil(error, @"The error parameter should be nil.");
        isComplete = YES;
    }];

    [self waitForCompletion:^{ return isComplete; }];
}

- (void)testShouldRequestAccessTokenWithCode
{
    NSData *responseData = [self dataForFixture:@"oauth-access_token"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    NSString *testCode = @"test-code";
    NSString *accessToken = [SinglySession.sharedSession requestAccessTokenWithCode:testCode error:nil];

    STAssertEqualObjects(accessToken, @"S0meAcc3ssT0k3n", @"The returned access token should equal 'S0meAcc3ssT0k3n'.");
}

- (void)testShouldRequestAccessTokenWithCodeAndCompletion
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"oauth-access_token"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    NSString *testCode = @"test-code";
    [SinglySession.sharedSession requestAccessTokenWithCode:testCode completion:^(NSString *accessToken, NSError *error) {
        STAssertEqualObjects(accessToken, @"S0meAcc3ssT0k3n", @"The passed access token should equal 'S0meAcc3ssT0k3n'.");
        isComplete = YES;
    }];

    [self waitForCompletion:^{ return isComplete; }];
}

- (void)testRequestingAccessTokenWithInvalidCodeShouldFailWithError
{
    NSData *responseData = [self dataForFixture:@"oauth-access_token-invalid"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    NSError *error;
    NSString *testCode = @"invalid-code";
    NSString *accessToken = [SinglySession.sharedSession requestAccessTokenWithCode:testCode error:&error];

    STAssertNil(accessToken, @"The returned access token should be nil.");
    STAssertNotNil(error, @"The error should not be nil.");
}

- (void)testRequestingAccessTokenWithInvalidCodeAndCompletionShouldFailWithError
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"oauth-access_token-invalid"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    NSString *testCode = @"invalid-code";
    [SinglySession.sharedSession requestAccessTokenWithCode:testCode completion:^(NSString *accessToken, NSError *error) {
        STAssertNil(accessToken, @"The passed access token should be nil.");
        STAssertNotNil(error, @"The passed error should not be nil.");
        isComplete = YES;
    }];

    [self waitForCompletion:^{ return isComplete; }];
}

#pragma mark - Profiles

- (void)testShouldUpdateProfiles
{
    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    BOOL isSuccessful = [SinglySession.sharedSession updateProfiles:nil];

    STAssertTrue(isSuccessful, @"Return value from updateProfiles: should be true.");
}

- (void)testShouldUpdateProfilesWithCompletion
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    [SinglySession.sharedSession updateProfilesWithCompletion:^(BOOL isSuccessful, NSError *error) {
        STAssertTrue(isSuccessful, @"Parameter value 'isSuccessful' should be true.");
        isComplete = YES;
    }];

    [self waitForCompletion:^{ return isComplete; }];
}

- (void)testUpdateProfilesShouldPostNotification
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    id testObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kSinglySessionProfilesUpdatedNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *notification)
    {
        isComplete = YES;
    }];

    [SinglySession.sharedSession updateProfiles:nil];

    [self waitForCompletion:^{ return isComplete; }];

    [[NSNotificationCenter defaultCenter] removeObserver:testObserver];
}

- (void)testShouldResetProfiles
{

    // Mock Profiles Response
    NSData *responseData = [self dataForFixture:@"profiles"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    [SinglySession.sharedSession updateProfiles:nil];

    STAssertNotNil(SinglySession.sharedSession.profile, @"Profile property should not be nil.");
    STAssertNotNil(SinglySession.sharedSession.profiles, @"Profiles property should not be nil.");

    [SinglySession.sharedSession resetProfiles];

    STAssertNil(SinglySession.sharedSession.profile, @"Profile property should be nil.");
    STAssertNil(SinglySession.sharedSession.profiles, @"Profiles property should be nil.");

}

- (void)testResetProfilesShouldPostNotification
{
    __block BOOL isComplete = NO;

    id testObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kSinglySessionProfilesUpdatedNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *notification)
    {
        isComplete = YES;
    }];

    [SinglySession.sharedSession resetProfiles];

    [self waitForCompletion:^{ return isComplete; }];

    [[NSNotificationCenter defaultCenter] removeObserver:testObserver];
}

#pragma mark - Service Management

- (void)testShouldApplyService
{
    NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    BOOL isSuccessful = [SinglySession.sharedSession applyService:@"facebook"
                                                        withToken:@"test-token"
                                                            error:nil];

    STAssertTrue(isSuccessful, @"Return value for applyService: should be true.");
}

- (void)testShouldApplyServiceWithCompletion
{
    __block BOOL isComplete = NO;

    NSData *responseData = [self dataForFixture:@"auth-facebook-apply"];
    [SinglyTestURLProtocol setCannedResponseData:responseData];

    [SinglySession.sharedSession applyService:@"facebook" withToken:@"test-token" completion:^(BOOL isSuccessful, NSError *error) {
        STAssertTrue(isSuccessful, @"Parameter value 'isSuccessful' should be true.");
        isComplete = YES;
    }];

    [self waitForCompletion:^{ return isComplete; }];
}

@end
