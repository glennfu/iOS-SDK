# Singly iOS SDK

A simple SDK for accessing Singly from iOS apps.

## Getting Started

The first thing you will need is a Client ID and a Client Secret for your
application from Singly. If you have not done so already, add your application
by [signing in to Singly](https://singly.com/apps). Your Client ID and Client
Secret can be found on the application settings page for your application.

Once you have your Client ID and Client Secret, we can either start a new iOS
application or use an existing one. If you are starting fresh, you can take a
look at and clone our [skeleton project](https://github.com/singly/ios-sdk-skeleton)
that is already bootstrapped for the Singly iOS SDK.

### Download the Singly SDK

The easiest way to get started with the Singly SDK is to [download our
pre-packaged distribution](http://singly.github.com/iOS-SDK/downloads).

### Include the Singly SDK in Your Project

1. Drag the `SinglySDK.framework` and `SinglySDK.bundle` files from the
   pre-packaged distribution into your Xcode project. You will be asked to
   add them to your targets; do this.

2. The Singly SDK requires a number of frameworks that you may or may not
   already be linking to. Under your Build Phases setting, add the `Accounts`,
   `AddressBook`, `AddressBookUI`, `Security`, `Social`, `Twitter` and
   `QuartzCore` frameworks to the "Link Binary With Libraries" phase. If you are
   targeting iOS 5, be sure to mark the `Social` framework as "Optional" instead
   of "Required".

3. Import the Singly SDK into the source files you wish to use the SDK in by
   using `#import <SinglySDK/SinglySDK.h>`.

### Opening a Session to Singly

To start using the Singly SDK in your project, you will first need to
initialize the `SinglySession`. You'll probably want to do this in your
application delegate right after the application has finished launching, such
as in the `application:didFinishLaunchingWithOptions:launchOptions` method.

```objective-c
SinglySession *session = [SinglySession sharedSession];
session.clientID = CLIENT_ID;
session.clientSecret = CLIENT_SECRET;

[session startSessionWithCompletion:^(BOOL isReady, NSError *error) {
    if (isReady) {
        // The session is ready to go!
    } else {
        // A valid session could not be started. You will need to authenticate
        // with a service (from a view controller) to establish a valid
        // session.
    }
}];
```

The `SinglySession` has two other properties:

  * `accessToken` - Your Singly Access Token. You should not need to access
    this unless you really need to do something that does not fit into the
    current Singly SDK.
  * `accountID` - Your Singly Account ID.

Both of these are saved between runs in the `NSUserDefaults` and should be
setup using `SinglyService` or a `SinglyLoginViewController` instance.

### Logging Into Services Using Singly

The Singly iOS SDK attempts to provide the best possible user experience, based
on the service the user wishes to authenticate with and the support that we
have for that service on the device they are using. To request authorization,
call the following from a view controller to present the login view for a
given service:

```objective-c
SinglyService *service = [SinglyService serviceWithIdentifier:@"facebook"];
service.delegate = self;
[service requestAuthorizationFromViewController:self];
```

The delegate for the service you are requesting authorization from should
adhere to the `SinglyServiceDelegate` protocol. These methods will be called
after the authorization request has completed:

```objective-c
- (void)singlyServiceDidAuthorize:(SinglyService *)service
{
    // We're ready to rock! Go do something amazing!
}

- (void)singlyServiceDidFail:(SinglyService *)service
                   withError:(NSError *)error
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Login Error"
                                                    message:[error localizedDescription]
                                                    delegate:self cancelButtonTitle:@"OK"
                                                    otherButtonTitles:nil];
    [alert show];
    [self dismissViewControllerAnimated:YES completion:nil];
}
```

### Using the Singly Login Picker

If you wish to login multiple services, or offer multiple services for login,
then you can use the `SinglyLoginPickerViewController`.

```
SinglyLoginPickerViewController *viewController = [[SinglyLoginPickerViewController alloc] init];
[self presentModalViewController:viewController animated:YES];
```

### Making API Requests

Once we have a valid session we can start making API requests. We can make
GET, POST or any method requests using the `SinglyRequest` class (which is
simply a convenient subclass of `NSURLRequest`). The request is only a
description of the request that we are going to make, to actually execute
the request we use `NSURLConnection`.

Here is an example that requests the profiles list and uses blocks to handle
the result:

```objective-c
SinglyRequest *request = [SinglyRequest requestWithEndpoint:@"profiles"];

[NSURLConnection sendAsynchronousRequest:request
                                   queue:[NSOperationQueue mainQueue]
                       completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
    NSArray *profiles = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    NSLog(@"The profiles result is: %@", profiles);
}];
```

## Building the Example App

Singly SDK ships with an example app that illustrates all of the capabilities
of the SDK.

### Provide Your Client ID and Client Secret

Before you can build and run the example app, you will need to provide your
Client ID and Client Secret in `SinglyConfiguration.h`.

### Enable Native Facebook Authorization (optional)

See the instructions below (under "Native Facebook Authorization") to enable
testing of the Facebook application fallback attempt.

### Build and Run!

Once you have things configured, simply build and run the project in the
Simulator.

If you wish to run the example on your iPhone or iPad, you will need to
configure the project with provisioning appropriate to your device and Apple
developer account, which is beyond the scope of this document.

## API Documentation

After you've cloned the project, you will find generated documentation in
the `SinglySDK/Documentation` folder. This documentation is automatically
regenerated with each successful build of the framework in Xcode, provided
you have [appledoc](http://gentlebytes.com/appledoc/) installed.

You may also view the documentation for the latest release at
[http://singly.github.com/iOS-SDK/api](http://singly.github.com/iOS-SDK/api)
or subscribe to it within Xcode at
[http://singly.github.com/iOS-SDK/api/SinglySDK.atom](http://singly.github.com/iOS-SDK/api/SinglySDK.atom).

## Native Facebook Authorization

Singly SDK interfaces directly with the device to support authorization on
iOS 6+ and will attempt to fallback to the installed Facebook application and
then the built-in Singly web-based authorization. In order for the Facebook
application fallback to work, you will need to perform the following steps:

### Configure Your Application at Facebook

On the [Facebook Developers](http://developers.facebook.com) site, you will
need to create and configure your app as a "Native iOS App". You will need
to set the bundle identifier defined in your Info.plist.

### Register your app to handle Facebook URLs

You must add the following to your Info.plist, replacing the 0's with your
actual Facebook App ID:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>fb000000000000000</string>
        </array>
    </dict>
</array>
```

### Configure your app delegate to handle launches by URL

When native integration is not possible, we fall back to launching the
Facebook app (if installed) in order to complete the auth workflow. In order
for this to happen, you will need your application delegate to implement the
following method in order for the round-trip process to complete:

```objective-c
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
  return [SinglySession.sharedSession handleOpenURL:url];
}
```

## Need Help?

We are available to answer your questions, help you work through integration
issues and look into possible bugs with our service and SDKs.

  * **Found a bug?**
    If you think you have come across a bug in the SDK, please take a moment
    to [file an issue](https://github.com/singly/ios-sdk/issues), providing as
    much information about the issue as possible.

  * **File a support ticket.**
    For questions or help implementing the SDK into your app, feel
    free to [contact support](https://singly.com/docs/contact/).

You may also contact the maintainer of the Singly iOS SDK, Justin Mecham, at
[opie@singly.com](mailto:opie@singly.com).

## License

The Singly iOS SDK is licensed under the terms of the BSD License. Please see
the [LICENSE](http://github.com/singly/ios-sdk/blob/master/LICENSE) file for
more information.
