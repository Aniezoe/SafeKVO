//
//  Person.h
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import <Foundation/Foundation.h>
#import "Child.h"

NS_ASSUME_NONNULL_BEGIN

@interface Person : NSObject

@property (nonatomic, strong) Child *child;

@end

NS_ASSUME_NONNULL_END
