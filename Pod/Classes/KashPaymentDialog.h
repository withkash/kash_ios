//
//  Copyright (c) 2015 Kash Corp. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void (^kashPaymentOnCompleteBlock)(NSDictionary *result);

@interface KashPaymentDialog : NSObject<UIWebViewDelegate>
    @property NSString *publishableKey;

    - (KashPaymentDialog*)initializeWithPublishableKey:(NSString*)publishableKey;
    - (void)show:(NSDictionary *)options onComplete:(kashPaymentOnCompleteBlock)handler;
    - (void)dismiss:(id)sender;
@end
