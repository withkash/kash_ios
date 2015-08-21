//
//  Copyright (c) 2015 Kash Corp. All rights reserved.
//

#import "KashPaymentDialog.h"
#import "WebViewJavascriptBridge.h"
#include <netdb.h>


#define kKashDialogAnimationInDuration 0.5
#define kKashDialogAnimationOutDuration 0.5
#define kKashDialogOverlayAnimationInDuration 0.5
#define kKashDialogOverlayAnimationOutDuration 0.5

#define kKashAccentColor ([UIColor colorWithRed:91/255.0f green:198/255.0f blue:136/255.0f alpha:1.0f])


@interface KashPaymentDialog ()
    - (BOOL)isNetworkAvailable;
    - (void)delayInSeconds:(double)delay thenExecute:(void(^)(void))block;
    
    @property NSDictionary *options;
    @property (nonatomic, copy) void (^onCompleteBlock)(NSDictionary *result);

    @property BOOL isDialogVisible;
    @property WebViewJavascriptBridge *bridge;
    @property NSDictionary *paymentResult;

    @property (nonatomic, strong) UIView *dialogView;
    @property (nonatomic, strong) UIView *overlayView;
    @property (nonatomic, strong) UIView *loadingView;
    @property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
    @property (nonatomic, strong) UILabel *loadingErrorLabel;
    @property (nonatomic, strong) UIButton *loadingButton;
    @property (nonatomic, strong) UIWebView *webView;
@end


@implementation KashPaymentDialog


- (BOOL)isNetworkAvailable
{
    char *hostname;
    struct hostent *hostinfo;
    hostname = "withkash.com";
    hostinfo = gethostbyname (hostname);
    if (hostinfo == NULL){
        return NO;
    }
    else{
        return YES;
    }
}

- (void)delayInSeconds:(double)delay thenExecute:(void(^)(void))block
{
    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC);
    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^(void){
        if (block){
            block();
        }
    });
}

- (KashPaymentDialog*)initializeWithPublishableKey:(NSString*)publishableKey
{
    KashPaymentDialog* instance = [self init];
    instance.publishableKey = publishableKey;
    return instance;
}

- (void)renderPaymentDialog:(BOOL)isRotateRender
{
    UIView *rootView = [[[[UIApplication sharedApplication] delegate] window] rootViewController].view;
    // OVERLAY: create transparent overlay
    _overlayView = [[UIView alloc] init];
    _overlayView.frame = rootView.bounds;
    _overlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.6];
    
    // OVERLAY: make it clickable
    UIButton *dismissOverlayButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissOverlayButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dismissOverlayButton.backgroundColor = [UIColor clearColor];
    dismissOverlayButton.frame = _overlayView.bounds;
    [dismissOverlayButton addTarget:self action:@selector(dismiss:) forControlEvents:UIControlEventTouchUpInside];
    [_overlayView addSubview:dismissOverlayButton];
    
    // OVERLAY: fade in
    if (isRotateRender) {
        [rootView addSubview:_overlayView];
    }
    else {
        [UIView transitionWithView:rootView duration:kKashDialogOverlayAnimationInDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^ { [rootView addSubview:_overlayView]; }
                        completion:nil];
    }
    
    // DIALOG: create a container view with shadow
    _dialogView = [[UIView alloc] init];
    if (rootView.bounds.size.width > 320) {
        _dialogView.frame = CGRectInset(rootView.bounds, rootView.bounds.size.width * 0.06, rootView.bounds.size.height * 0.1);
    }
    else {
        _dialogView.frame = CGRectMake(0.0f, 25.0f, rootView.bounds.size.width, rootView.bounds.size.height - 25.0f);
    }
    _dialogView.layer.cornerRadius = 10;
    _dialogView.layer.shadowRadius = 20;
    _dialogView.layer.shadowOffset = CGSizeMake(1, 1);
    _dialogView.layer.shadowOpacity = 0.5;
    

    // DIALOG: create a subview mask (need child UIView for mask to prevent shadow clipping)
    UIView *dialogMaskView = [[UIView alloc] init];
    dialogMaskView.frame = CGRectMake(0.0f, 0.0f, _dialogView.frame.size.width, _dialogView.frame.size.height);
    dialogMaskView.layer.cornerRadius = 10;
    dialogMaskView.clipsToBounds = YES;
    [_dialogView addSubview:dialogMaskView];
    
    
    // DIALOG: slide in from bottom
    CGRect startFrame = _dialogView.frame;
    startFrame.origin.y += rootView.bounds.size.height;
    CGRect endFrame = _dialogView.frame;
    _dialogView.frame = startFrame;
    _dialogView.alpha = 1.0f;
    [_overlayView addSubview:_dialogView];
    [UIView animateWithDuration:kKashDialogAnimationInDuration
                          delay:(kKashDialogOverlayAnimationInDuration/2.0)
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         _dialogView.frame = endFrame;
                         _dialogView.alpha = 1.0f; }
                     completion:nil ];
    
    // DIALOG: add web view
    if (!_webView) {
        _webView = [[UIWebView alloc] init];
        _webView.delegate = self;
        _webView.scrollView.bounces = NO;
        
        NSString *urlString = @"https://cdn.withkash.com/kash.js/1.0.0/iOS.html";
        if (_options[@"appEndpoint"]) {
            urlString = _options[@"appEndpoint"];
        }
        NSURL *url = [NSURL URLWithString:urlString];
        NSURLRequest *urlRequest = [NSURLRequest requestWithURL:url];
        
        // setup javascript bridge
        // https://github.com/marcuswestin/WebViewJavascriptBridge
        _bridge = [WebViewJavascriptBridge bridgeForWebView:_webView handler:^(id data, WVJBResponseCallback responseCallback) {
            NSLog(@"Received message from javascript: %@", data);
        }];
        
        [_bridge registerHandler:@"kashJS_loaded" handler:^(id data, WVJBResponseCallback responseCallback) {
            [_loadingView removeFromSuperview];
            NSMutableDictionary *configOptions = [NSMutableDictionary dictionaryWithDictionary:@{@"publishableKey":_publishableKey}];
            if (_options[@"apiEndpoint"]) {
                configOptions[@"apiEndpoint"] = _options[@"apiEndpoint"];
            }
             responseCallback(configOptions);
        }];
        
        [_bridge registerHandler:@"kashJS_done" handler:^(id data, WVJBResponseCallback responseCallback) {
            _paymentResult = data;
            [self dismiss:nil];
        }];
        
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [_webView loadRequest:urlRequest];
    }
    
    // load webview to container
    _webView.frame = CGRectMake(0.0f, 0.0f, _dialogView.frame.size.width, _dialogView.frame.size.height);
    [dialogMaskView addSubview:_webView];
    
    // DIALOG: add loading view
    if (!isRotateRender) {
        _loadingView = [[UIView alloc] init];
        _loadingView.frame = CGRectMake(0.0f, 0.0f, _dialogView.frame.size.width, _dialogView.frame.size.height);
        [_loadingView setBackgroundColor:[UIColor whiteColor]];
        
        // add activity indicator
        _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _loadingSpinner.color = kKashAccentColor;
        _loadingSpinner.center = CGPointMake(_loadingView.frame.size.width/2, _loadingView.frame.size.height/2);
        [_loadingView addSubview:_loadingSpinner];
        [_loadingSpinner startAnimating];
        
        // add error text label
        _loadingErrorLabel = [[UILabel alloc] init];
        _loadingErrorLabel.frame = _loadingView.frame;
        _loadingErrorLabel.textColor = [UIColor redColor];
        _loadingErrorLabel.textAlignment = NSTextAlignmentCenter;
        _loadingErrorLabel.numberOfLines = 0;
        [_loadingView addSubview:_loadingErrorLabel];
        
        // add cancel button
        _loadingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_loadingButton setTitle:@"cancel" forState:UIControlStateNormal];
        [_loadingButton setTitleColor:kKashAccentColor forState:UIControlStateNormal];
        [_loadingButton addTarget:self action:@selector(dismiss:) forControlEvents:UIControlEventTouchUpInside];
        [_loadingButton sizeToFit];
        _loadingButton.center = CGPointMake(_loadingView.frame.size.width/2, _loadingView.frame.size.height/2 + 50.0f);
        [_loadingView addSubview:_loadingButton];
        
        // add loading view to container
        [dialogMaskView addSubview:_loadingView];
        
        // if network not available, then bail
        if (![self isNetworkAvailable]) {
            [self webView:_webView
                didFailLoadWithError:[NSError errorWithDomain:@"Network Error"
                                              code:ENETDOWN
                                          userInfo:@{NSLocalizedDescriptionKey : @"Direct debit payment network is not available right now"}]];
            return;
        }
    }
    
    
    // listen for orientation changes
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(orientationChanged:)
     name:UIDeviceOrientationDidChangeNotification
     object:[UIDevice currentDevice]];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [_loadingSpinner stopAnimating];
    [_loadingErrorLabel setText:[error localizedDescription]];
    [_loadingButton setTitle:@"ok" forState:UIControlStateNormal];
    [_loadingButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
}

- (void) orientationChanged:(NSNotification *)note
{
    if (!_isDialogVisible) {
        return;
    }
    
    [_overlayView removeFromSuperview];
    [self renderPaymentDialog:YES];
}

- (void)show:(NSDictionary *)options onComplete:(kashPaymentOnCompleteBlock)onCompleteBlock
{
    _isDialogVisible = YES;
    _onCompleteBlock = onCompleteBlock;
    _options = options;
    
    [self renderPaymentDialog:NO];
}

- (void)dismiss:(id)sender
{
    _isDialogVisible = NO;
    UIView *rootView = [[[[UIApplication sharedApplication] delegate] window] rootViewController].view;
 
    // cleanup
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self ];
    _bridge = nil;
    
    // DIALOG: slide out to bottom
    CGRect endFrame = _dialogView.frame;
    endFrame.origin.y += rootView.bounds.size.height;
    [UIView animateWithDuration:kKashDialogAnimationOutDuration
                          delay:0.0f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         _dialogView.frame = endFrame;
                         _dialogView.alpha = 1.0f; }
                     completion:nil];
    
    // OVERLAY: fade out
    [self delayInSeconds:(kKashDialogAnimationOutDuration/2) thenExecute:^{
        [UIView transitionWithView:_overlayView.superview duration:kKashDialogOverlayAnimationOutDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^ { [_overlayView removeFromSuperview]; }
                        completion:^(BOOL animationFinished){
                            if (_onCompleteBlock) {
                                _onCompleteBlock(_paymentResult);
                            }
                        }];
    }];
}

@end
