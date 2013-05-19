//
//  SinglyLoginViewController.m
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
#import "UIViewController+Modal.h"

#import "SinglyActivityIndicatorView.h"
#import "SinglyAlertView.h"
#import "SinglyConstants.h"
#import "SinglyLoginViewController.h"
#import "SinglyLoginViewController+Internal.h"
#import "SinglyService+Internal.h"

@implementation SinglyLoginViewController

@synthesize serviceIdentifier = _serviceIdentifier;

- (id)initWithServiceIdentifier:(NSString *)serviceIdentifier
{
    self = [super init];
    if (self)
    {
        self.serviceIdentifier = serviceIdentifier;
    }
    return self;
}

- (void)setServiceIdentifier:(NSString *)serviceIdentifier
{
    @synchronized(self)
    {
        _serviceIdentifier = [SinglyService normalizeServiceIdentifier:[serviceIdentifier copy]];
    }
}

- (NSString *)serviceIdentifier
{
    @synchronized(self)
    {
        return _serviceIdentifier;
    }
}

#pragma mark - View Callbacks

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.webView = [[UIWebView alloc] initWithFrame:self.view.frame];
    self.webView.scalesPageToFit = YES;
    self.webView.delegate = self;
    [self.view addSubview:self.webView];
}

- (void)viewWillAppear:(BOOL)animated
{

    //
    // If the login view is being presented modally, we need to add our own
    // navigation bar to the view so that the user can abort the login, if
    // necessary.
    //
    if (self.isModal) [self configureNavigationBar];

    //
    // Otherwise, be sure to clean up a previously initialized navigation bar
    // as to not display a redundant one...
    //
    else if (!self.isModal && self.navigationBar)
    {
        [self.navigationBar removeFromSuperview];
        self.navigationBar = nil;
    }

    NSString *urlStr = [SinglySession.sharedSession.baseURL stringByAppendingFormat:@"/oauth/authenticate?redirect_uri=singly://authorize&service=%@&client_id=%@",
                        self.serviceIdentifier, SinglySession.sharedSession.clientID];

    if (SinglySession.sharedSession.accountID)
        urlStr = [urlStr stringByAppendingFormat:@"&account=%@", SinglySession.sharedSession.accountID];
    else
        urlStr = [urlStr stringByAppendingString:@"&account=false"];

    if (self.scopes)
    {
        NSString *scopes = [self.scopes componentsJoinedByString:@","];
        urlStr = [urlStr stringByAppendingFormat:@"&scope=%@", scopes];
    }

    if (self.flags)
        urlStr = [urlStr stringByAppendingFormat:@"&flag=%@", self.flags];

    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [SinglyActivityIndicatorView showIndicator];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    [SinglyActivityIndicatorView dismissIndicator];

	if ([self.webView isLoading])
        [self.webView stopLoading];
}

#pragma mark - Web View Delegates

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{

    if ([request.URL.scheme isEqualToString:@"singly"] && [request.URL.host isEqualToString:@"authorize"])
    {

        // Display Activity Indicator
        [SinglyActivityIndicatorView showIndicator];

        // Get the Request Parameters
        NSDictionary *parameters = [NSDictionary dictionaryWithQueryString:request.URL.query];
        NSString *code = [parameters objectForKey:@"code"];

        if (!code)
        {
            NSLog(@"[SinglySDK] Missing code on redirect!");
            return NO;
        }

        // Request the Access Token from the Singly API
        [SinglySession.sharedSession requestAccessTokenWithCode:code
                                                     completion:^(NSString *accessToken, NSError *error)
        {

            // Handle Errors...
            if (error)
            {
                NSError *loginError = [NSError errorWithDomain:kSinglyErrorDomain
                                                          code:kSinglyLoginFailedErrorCode
                                                      userInfo:@{ NSLocalizedDescriptionKey : [error localizedDescription] }];

                // Dismiss the Activity Indicator
                [SinglyActivityIndicatorView dismissIndicator];

                // Dismiss the Login View
                [self dismissViewControllerAnimated:YES completion:nil];

                // Notify the Delegate
                if (self.delegate && [self.delegate respondsToSelector:@selector(singlyLoginViewController:errorLoggingInToService:withError:)])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate singlyLoginViewController:self errorLoggingInToService:self.serviceIdentifier withError:loginError];
                    });
                }

                return;
            }

            // Update Profiles
            [SinglySession.sharedSession updateProfilesWithCompletion:^(BOOL isSuccessful, NSError *error)
            {

                // Dismiss the Activity Indicator
                [SinglyActivityIndicatorView dismissIndicator];

                // Dismiss the Login View
                [self dismissViewControllerAnimated:YES completion:nil];

                // Notify the Delegate
                if (self.delegate && [self.delegate respondsToSelector:@selector(singlyLoginViewController:didLoginForService:)])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate singlyLoginViewController:self didLoginForService:self.serviceIdentifier];
                    });
                }

            }];

        }];

        return NO;
    }

    return YES;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [SinglyActivityIndicatorView dismissIndicator];
//    SinglyAlertView *alertView = [[SinglyAlertView alloc] initWithTitle:nil message:[error localizedDescription]];
//    [alertView addCancelButtonWithTitle:@"Dismiss"];
//    [alertView show];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [SinglyActivityIndicatorView dismissIndicator];
}

#pragma mark -

- (void)cancel
{
    NSError *error = [NSError errorWithDomain:kSinglyErrorDomain
                                         code:kSinglyLoginAbortedErrorCode
                                     userInfo:@{ NSLocalizedDescriptionKey : @"User aborted the login process." }];

    if (self.delegate && [self.delegate respondsToSelector:@selector(singlyLoginViewController:errorLoggingInToService:withError:)])
        [self.delegate singlyLoginViewController:self errorLoggingInToService:self.serviceIdentifier withError:error];

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)configureNavigationBar
{
    self.webView.frame = CGRectMake(0, 44, self.view.frame.size.width, self.view.frame.size.height - 44);
    self.navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];

    NSString *title = (self.serviceName ? self.serviceName : self.serviceIdentifier);
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:title];
    navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                        style:UIBarButtonItemStyleBordered
                                                                       target:self
                                                                       action:@selector(cancel)];
    self.navigationBar.items = @[navigationItem];

    //
    // Set the tint color of our navigation bar to match the tint of the
    // view controller's navigation bar that is responsible for presenting
    // us modally.
    //
    if ([self.presentingViewController respondsToSelector:@selector(navigationBar)])
    {
        UIColor *presentingTintColor = ((UINavigationController *)self.presentingViewController).navigationBar.tintColor;
        self.navigationBar.tintColor = presentingTintColor;
    }

    [self.view addSubview:self.navigationBar];
}

@end
