//
//  Boy.h
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface Boy : NSObject

@property (nonatomic, strong) NSNumber *age;
@property (nonatomic, assign) int count;
@property (nonatomic, assign) CGPoint point;

@end

NS_ASSUME_NONNULL_END
