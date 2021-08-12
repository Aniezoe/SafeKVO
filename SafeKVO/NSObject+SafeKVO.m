//
//  NSObject+SafeKVO.m
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import "NSObject+SafeKVO.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface SafeKVOModel : NSObject

@property (nonatomic, weak) NSObject *observer;// 观察者
@property (nonatomic, weak) NSObject *observed;// 被观察者
@property (nonatomic, copy) NSString *keyPath;// 属性链
@property (nonatomic, copy) SK_ObservedValueChanged change; // 观察者回调
@property (nonatomic, strong) NSObject *oldValue;// 被观察属性原值

@end

@implementation SafeKVOModel

- (instancetype)initWithObserver:(NSObject *)observer observed:(NSObject *)observed forKeyPath:(NSString *)keyPath change:(SK_ObservedValueChanged)change {
    if (self = [super init]) {
        self.observer = observer;
        self.observed = observed;
        self.keyPath = keyPath;
        self.change = change;
    }
    return self;
}

@end

#define forceInline __inline__ __attribute__((always_inline))

static NSString * const kSafeKVOClassPrefix = @"SafeKVONotifying_";
static NSString * const kSafeKVOAssiociateObservers = @"SafeKVOAssiociateObservers";

static forceInline SEL sk_setterSelectorFromPropertyName(NSString *propertyName) {
    if (propertyName.length <= 0)
        return nil;
    NSString *setterString = [NSString stringWithFormat:@"set%@%@:", [[propertyName substringToIndex:1] uppercaseString], [propertyName substringFromIndex:1]];
    return NSSelectorFromString(setterString);
}

static forceInline NSString *sk_propertyNameFromSetterString(NSString *setterString) {
    if (setterString.length <= 0 || ![setterString hasPrefix: @"set"] || ![setterString hasSuffix: @":"])
        return nil;
    NSRange range = NSMakeRange(3, setterString.length - 4);
    NSString *propertyName = [setterString substringWithRange:range];
    propertyName = [propertyName stringByReplacingCharactersInRange: NSMakeRange(0, 1) withString:[[propertyName substringToIndex: 1] lowercaseString]];
    return propertyName;
}

static forceInline void sk_setter(id self, SEL _cmd, id newValue) {
    @synchronized (self) {
        NSString *propertyName = sk_propertyNameFromSetterString(NSStringFromSelector(_cmd));
        NSParameterAssert(propertyName);
        if (!propertyName)
            return;
        
        NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)kSafeKVOAssiociateObservers);
        for (SafeKVOModel *model in observers) {
            if ([model.keyPath containsString:propertyName])
                model.oldValue = [model.observed valueForKeyPath:model.keyPath];
        }
        // 调用父类的set方法
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        void (*superSetter)(void *, SEL, id) = (void *)objc_msgSendSuper;
        superSetter(&superClass, _cmd, newValue);
        
        // 观察者回调
        for (SafeKVOModel *model in observers) {
            // 观察者未释放才需回调
            if ([model.keyPath containsString:propertyName] && model.observer) {
                model.change(model.observed, model.keyPath, model.oldValue, [model.observed valueForKeyPath:model.keyPath]);
                model.oldValue = nil;
            }
        }
    }
}

static forceInline Class sk_class(id self) {
    return class_getSuperclass(object_getClass(self));
}

static forceInline Class createSafeKVOClass(id object) {
    // 获取以SafeKVONotifying_为前缀拼接类名的子类
    Class observedClass = object_getClass(object);
    NSString *className = NSStringFromClass(observedClass);
    NSString *subClassName = [kSafeKVOClassPrefix stringByAppendingString:className];
    Class subClass = NSClassFromString(subClassName);
    // 运行时已经加载该类则直接返回
    if (subClass)
        return subClass;
    
    Class originalClass = object_getClass(object);
    // 分配类和原类的内存
    subClass = objc_allocateClassPair(originalClass, subClassName.UTF8String, 0);
    // 修改class实现，返回父类Class
    Method classMethod = class_getInstanceMethod(originalClass, @selector(class));
    const char *types = method_getTypeEncoding(classMethod);
    class_addMethod(subClass, @selector(class), (IMP)sk_class, types);
    // 注册类到运行时环境
    objc_registerClassPair(subClass);
    return subClass;
}


static forceInline BOOL objectHasSelector(id object, SEL selector) {
    BOOL result = NO;
    unsigned int count = 0;
    Class observedClass = object_getClass(object);
    Method *methods = class_copyMethodList(observedClass, &count);
    for (NSInteger i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        if (sel == selector) {
            result = YES;
            break;
        }
    }
    free(methods);
    return result;
}

@implementation NSObject (SafeKVO)

- (void)sk_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath observeValueChanged:(SK_ObservedValueChanged)change {
    @synchronized (self) {
        NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge void *)kSafeKVOAssiociateObservers);
        for (SafeKVOModel *observerModel in observers) {
            // 已添加过同一个观察者，无需重复添加
            if (observerModel.observer == observer && observerModel.observed == self && [observerModel.keyPath isEqualToString:keyPath]) {
                return;
            }
        }
        // 通过keyPath依次执行->创建子类重写set方法操作
        NSArray *keys = [keyPath componentsSeparatedByString:@"."];
        NSInteger index = 0;
        id object = self;
        while (index < keys.count) {
            SEL setterSelector = sk_setterSelectorFromPropertyName(keys[index]);
            Method setterMethod = class_getInstanceMethod([object class], setterSelector);
            NSParameterAssert(setterMethod);
            if (!setterMethod) {
                return;
            }
            id nextObject = [object valueForKey:keys[index]];
            Class observedClass = object_getClass(object);
            NSString *className = NSStringFromClass(observedClass);
            if (![className hasPrefix:kSafeKVOClassPrefix]) {
                // 创建子类并修改本类isa指针使其指向子类
                observedClass = createSafeKVOClass(object);
                object_setClass(object, observedClass);
            }
            if (!objectHasSelector(object, setterSelector)) {
                // 重写set方法在方法里调用父类的set方法并通过block回调到上层，以完成监听过程
                const char *types = method_getTypeEncoding(setterMethod);
                class_addMethod(observedClass, setterSelector, (IMP)sk_setter, types);
            }
            // 添加监听者到类的关联对象数组
            observers = objc_getAssociatedObject(object, (__bridge void *)kSafeKVOAssiociateObservers);
            if (!observers) {
                observers = [NSMutableArray array];
                objc_setAssociatedObject(object, (__bridge void *)kSafeKVOAssiociateObservers, observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            SafeKVOModel *kvoModel = [[SafeKVOModel alloc] initWithObserver:observer observed:self forKeyPath:keyPath change:change];
            [observers addObject:kvoModel];
            
            index++;
            if (index < keys.count) {
                object = nextObject;
            }
        }
    }
}

- (void)sk_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    @synchronized (self) {
        NSArray *keys = [keyPath componentsSeparatedByString:@"."];
        NSInteger index = 0;
        id object = self;
        while (index < keys.count) {
            SafeKVOModel *modelRemoved = nil;
            NSMutableArray *observers = objc_getAssociatedObject(object, (__bridge void *)kSafeKVOAssiociateObservers);
            for (SafeKVOModel *model in observers) {
                if (model.observer == observer && model.observed == self && [model.keyPath isEqualToString:keyPath]) {
                    modelRemoved = model;
                    break;
                }
            }
            if (modelRemoved) {
                [observers removeObject:modelRemoved];
                if (!observers.count) {
                    object_setClass(object, [object class]);
                }
            } else {
                object_setClass(object, [object class]);
            }
            object = [object valueForKey:keys[index]];
            index++;
        }
    }
}

@end
