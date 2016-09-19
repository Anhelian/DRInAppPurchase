//
//  DRInAppPurchaseService.h
//  TheBetterHalf
//
//  Created by Denis Romashov on 02.07.15.
//  Copyright (c) 2015 InMotionSoft. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SKProduct;
@protocol DRInAppPurchaseDelegate <NSObject>

@optional
- (void)completeTransactionWithIdentifier:(NSString *)identifier;
- (void)failedTransaction;
- (void)failedTransactionWithInternetConnection;

- (void)restoredTransaction;
- (void)restoreTransactionFailed:(NSError *)error;

@end


@interface DRInAppPurchaseService : NSObject

+ (instancetype)sharedPurchaseService;

- (void)initializeForProductIDs:(NSSet *)productIDs;

- (void)addListener:(id<DRInAppPurchaseDelegate>)listener;
- (void)removeListener:(id<DRInAppPurchaseDelegate>)listener;

- (void)purchaseProductWithBudleID:(NSString *)bundleID;
- (void)restoreCompletedTransactions;

- (BOOL)isPurchasedProductWithBundleID:(NSString *)bundleID;
- (NSString *)formattedPriceWithCurrencyForProductID:(NSString *)productID;

@end
