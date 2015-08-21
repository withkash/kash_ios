//
//  KCViewController.m
//  Kash
//
//  Copyright (c) 2015 Kash Corp. All rights reserved.
//

#import "KCViewController.h"
#import "Kash.h"

@interface KCViewController ()
@property (nonatomic, strong) KashPaymentDialog *kashPaymentDialog;
@end

@implementation KCViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)delayInSeconds:(double)delay thenExecute:(void(^)(void))block  {
    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC);
    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^(void){
        if (block){
            block();
        }
    });
}

- (IBAction)doneButtonClick:(id)sender {
    // TODO: Swap it with your actual key
    _kashPaymentDialog = [[KashPaymentDialog alloc] initializeWithPublishableKey:@"pk_test_f4fe24dc4d3d705e39713cfe84938c3a"];

    // For production:
    //NSDictionary *options = @{@"apiEndpoint": @"https://api.withkash.com/v1"};
    // For testing:
    NSDictionary *options = @{@"apiEndpoint": @"https://api-test.withkash.com/v1"};
    [_kashPaymentDialog show:options onComplete:^(NSDictionary *result) {
        _kashPaymentDialog = nil;
        NSLog(@"%@", result);
    }];
}

@end
