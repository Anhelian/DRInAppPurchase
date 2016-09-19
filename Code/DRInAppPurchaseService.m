//
//  DRInAppPurchaseService.m
//  TheBetterHalf
//
//  Created by Denis Romashov on 02.07.15.
//  Copyright (c) 2015 InMotionSoft. All rights reserved.
//

#import "DRInAppPurchaseService.h"
#import "DRInternetConnection.h"

#import <SVProgressHUD.h>
#import <StoreKit/StoreKit.h>

static NSString *const kNoFullaccess = @"Purchase the full app for access";

typedef void (^RequestProductsCompletionHandler)(BOOL success, NSArray * products);

@interface DRInAppPurchaseService () <SKProductsRequestDelegate, SKPaymentTransactionObserver>

@property (nonatomic, strong) NSMutableDictionary *listeners;
@property (nonatomic, strong) NSArray *products;
@property (nonatomic, strong) NSSet *productIDs;
@property (nonatomic, strong) NSMutableSet *purchasedProductIDs;
@property (nonatomic, strong) NSNumberFormatter *priceFormatter;

@property (nonatomic, strong) RequestProductsCompletionHandler completionHandler;

@end


@implementation DRInAppPurchaseService

+ (DRInAppPurchaseService *)sharedPurchaseService
{
    static DRInAppPurchaseService *sharedService = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        sharedService = [[DRInAppPurchaseService alloc] init];
    });
    
    return sharedService;
}

- (void)initializeForProductIDs:(NSSet *)productIDs
{
    self.productIDs = [productIDs copy];
    [self setupPurchasedProductIDs];
    
    [self requestProductsWithCompletionHandler:^(BOOL success, NSArray *products) {
        self.products = (success) ? products : [NSArray array];
    }];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setupPriceFormatter];
        self.listeners = [NSMutableDictionary new];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    
    return self;
}


#pragma mark -
#pragma mark Configurations

- (void)setupPriceFormatter
{
    NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    
    self.priceFormatter = numberFormatter;
}

- (void)setupPurchasedProductIDs
{
    self.purchasedProductIDs = [NSMutableSet setWithCapacity:self.productIDs.count];
    for (NSString *productIdentifier in self.productIDs) {
        BOOL purchase = [[NSUserDefaults standardUserDefaults] boolForKey:productIdentifier];
        if (purchase) {
            [self.purchasedProductIDs addObject:productIdentifier];
        }
    }
}


#pragma mark -
#pragma mark Public Methods

- (void)addListener:(id<DRInAppPurchaseDelegate>)listener
{
    NSValue *listenerValue = [NSValue valueWithNonretainedObject:listener];
    NSString *key = [@([listener hash]) stringValue];
    [self.listeners setObject:listenerValue forKey:key];
}

- (void)removeListener:(id<DRInAppPurchaseDelegate>)listener
{
    NSString *key = [@([listener hash]) stringValue];
    [self.listeners removeObjectForKey:key];
}

- (void)purchaseProductWithBudleID:(NSString *)bundleID
{
    if ([self currentNetworkStatus]) {
        [SVProgressHUD showWithMaskType:(SVProgressHUDMaskTypeBlack)];
        if (self.products.count) {
            [self buyProduct:[self productForhBundleID:bundleID]];
        } else {
            [self requestProductsWithCompletionHandler:^(BOOL success, NSArray *products) {
                if (success) {
                    self.products = products;
                    [self buyProduct:[self productForhBundleID:bundleID]];
                }
            }];
        }
    } else {
        [self notifyFailedTransactionWithInternetConnection];
    }
}

- (void)restoreCompletedTransactions
{
    if ([self currentNetworkStatus]) {
        [SVProgressHUD showWithMaskType:(SVProgressHUDMaskTypeBlack)];
        [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    } else {
        [self notifyFailedTransactionWithInternetConnection];
    }
}

- (BOOL)isPurchasedProductWithBundleID:(NSString *)bundleID
{
    return [self isProductPurchased:bundleID];
}

- (NSString *)formattedPriceWithCurrencyForProductID:(NSString *)productID
{
    SKProduct *product = [self productForhBundleID:productID];
    NSString *formattedPrice = [self.priceFormatter stringFromNumber:[product price]];
    return formattedPrice;
}


#pragma mark -
#pragma mark SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    NSArray *skProducts = response.products;
    [self.priceFormatter setLocale:[skProducts.firstObject priceLocale]];
    
    if (self.completionHandler) {
        self.completionHandler(YES, skProducts);
    } else {
        [SVProgressHUD dismiss];
        [self notifyFailedTransactionWithInternetConnection];
    }
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    if (self.completionHandler) {
        self.completionHandler(NO, nil);
    }
}


#pragma mark -
#pragma mark SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
                
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:transaction];
                break;
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;
            case SKPaymentTransactionStateRestored:
                [self restoreTransaction:transaction];
                break;
            default:
                break;
        }
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    [self notifyRestoreTransactionsFailed:error];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    if (!queue.transactions.count) {
        NSError *error = [NSError errorWithDomain:kNoFullaccess code:404 userInfo:@{NSLocalizedDescriptionKey : kNoFullaccess}];
        [self notifyRestoreTransactionsFailed:error];
    } else {
        [self notifyRestoreTransactionsFinished];
    }
}


#pragma mark -
#pragma mark Notification for listeners

- (void)notifyRestoreTransactionsCompletedWithID:(NSString *)identifier
{
    [self performSelectorOnDelegates:@selector(completeTransactionWithIdentifier:) withObject:identifier];
}

- (void)notifyRestoreTransactionsFailed:(NSError *)error
{
    [self performSelectorOnDelegates:@selector(restoreTransactionFailed:) withObject:error];
}

- (void)notifyRestoreTransactionsFinished
{
    [self performSelectorOnDelegates:@selector(restoredTransaction)];
}

- (void)notifyFailedTransaction
{
    [self performSelectorOnDelegates:@selector(failedTransaction)];
}

- (void)notifyFailedTransactionWithInternetConnection
{
    [self performSelectorOnDelegates:@selector(failedTransactionWithInternetConnection)];
}


#pragma mark -
#pragma mark Transactions

- (void)completeTransaction:(SKPaymentTransaction *)transaction
{
    [SVProgressHUD dismiss];
    
    [self provideContentForProductID:transaction.payment.productIdentifier];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    [self notifyRestoreTransactionsCompletedWithID:transaction.payment.productIdentifier];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction
{
    [SVProgressHUD dismiss];
    
    NSString *transactionID = transaction.originalTransaction.payment.productIdentifier;
    [self provideContentForProductID:transactionID];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    [self notifyRestoreTransactionsFinished];
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction
{
    [SVProgressHUD dismiss];
    [self notifyFailedTransaction];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}


#pragma mark -
#pragma mark Helpers

- (void)requestProductsWithCompletionHandler:(RequestProductsCompletionHandler)completionHandler
{
    self.completionHandler = [completionHandler copy];
    SKProductsRequest *productRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:self.productIDs];
    productRequest.delegate = self;
    
    [productRequest start];
}

- (void)provideContentForProductID:(NSString *)productIdentifier
{
    [self.purchasedProductIDs addObject:productIdentifier];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:productIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)buyProduct:(SKProduct *)product
{
    if ([SKPaymentQueue canMakePayments] && product) {
        [[SKPaymentQueue defaultQueue] addPayment:[SKPayment paymentWithProduct:product]];
    }
}

- (BOOL)isProductPurchased:(NSString *)productID
{
    BOOL purchase = [self.purchasedProductIDs containsObject:productID];
    if (!purchase) {
        purchase = [[NSUserDefaults standardUserDefaults] boolForKey:productID];
    }
    return purchase;
}


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

- (void)performSelectorOnDelegates:(SEL)aSelector
{
    for (NSValue *value in [self.listeners allValues]) {
        id<DRInAppPurchaseDelegate> delegate = [value nonretainedObjectValue];
        if ([delegate respondsToSelector:aSelector]) {
            [delegate performSelector:aSelector];
        }
    }
}

- (void)performSelectorOnDelegates:(SEL)aSelector withObject:(id)anObject
{
    for (NSValue *value in [self.listeners allValues]) {
        id<DRInAppPurchaseDelegate> delegate = [value nonretainedObjectValue];
        if ([delegate respondsToSelector:aSelector]) {
            [delegate performSelector:aSelector withObject:anObject];
        }
    }
}

#pragma clang diagnostic pop


#pragma mark -
#pragma mark Helpers

- (BOOL)currentNetworkStatus
{
    DRInternetConnection *reachability = [DRInternetConnection reachabilityForInternetConnection];
    NetworkStatus networkStatus = [reachability currentReachabilityStatus];
    return networkStatus != NotReachable;
}

- (SKProduct *)productForhBundleID:(NSString *)bundleID
{
    SKProduct *product;
    for (SKProduct *bundleProduct in self.products) {
        if ([bundleProduct.productIdentifier isEqualToString:bundleID]) {
            product = bundleProduct;
        }
    }
    return product;
}

@end
