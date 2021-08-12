//
//  NSObject+SafeKVO.h
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* - (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
*/
typedef void (^SK_ObservedValueChanged) (id object, NSString *keyPath ,id oldValue, id newValue);

@interface NSObject (SafeKVO)

/// 添加安全观察者
/// @param observer 观察者
/// @param keyPath 属性链
/// @param change 回调
- (void)sk_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath observeValueChanged:(SK_ObservedValueChanged)change;

/// 移除观察者
/// @param observer 观察者
/// @param keyPath 属性链
- (void)sk_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;

@end

NS_ASSUME_NONNULL_END
