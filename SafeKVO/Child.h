//
//  Child.h
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import <Foundation/Foundation.h>
#import "Boy.h"

NS_ASSUME_NONNULL_BEGIN

@interface Child : NSObject

@property (nonatomic, strong) Boy *boy;

@end

NS_ASSUME_NONNULL_END
