//
//  NSObject+SafeKVO.m
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import "NSObject+SafeKVO.h"
#import <objc/runtime.h>
#import <objc/message.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

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

static forceInline void __SKPrivateSetter(id self, SEL _cmd, void (^setValueImp)(IMP imp)) {
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
        
        setValueImp(objc_msgSendSuper);
        
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
 
static forceInline void SKSetter_id(id self, SEL _cmd, id value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, id))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_BOOL(id self, SEL _cmd, BOOL value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, BOOL))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_double(id self, SEL _cmd, double value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, double))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_float(id self, SEL _cmd, float value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, float))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_char(id self, SEL _cmd, char value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, char))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_int(id self, SEL _cmd, int value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, int))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_long(id self, SEL _cmd, long value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, long))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_longlong(id self, SEL _cmd, long long value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, long long))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_short(id self, SEL _cmd, short value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, short))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_unsignedchar(id self, SEL _cmd, unsigned char value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, unsigned char))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_unsignedint(id self, SEL _cmd, unsigned int value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, unsigned int))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_unsignedlong(id self, SEL _cmd, unsigned long value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, unsigned long))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_unsignedlonglong(id self, SEL _cmd, unsigned long long value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, unsigned long long))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_unsignedshort(id self, SEL _cmd, unsigned short value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, unsigned short))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_CGPoint(id self, SEL _cmd, CGPoint value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, CGPoint))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_NSRange(id self, SEL _cmd, NSRange value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, NSRange))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_CGRect(id self, SEL _cmd, CGRect value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, CGRect))imp)(&superClass, _cmd, value);
    });
}

static forceInline void SKSetter_CGSize(id self, SEL _cmd, CGSize value) {
    __SKPrivateSetter(self, _cmd, ^(IMP imp) {
        struct objc_super superClass = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        ((void (*)(void *, SEL, CGSize))imp)(&superClass, _cmd, value);
    });
}

static forceInline IMP __SKSetter(Method setMethod) {
    if (!setMethod) {
        return NULL;
    }
    
    IMP imp = NULL;
    const char *encoding = method_getTypeEncoding(setMethod);
    if (*encoding == 'v') {
        char *argType = method_copyArgumentType(setMethod, 2);
        switch (*argType) {
            case 'c': {
                imp = (IMP)SKSetter_char;
            } break;
            case 'd': {
                imp = (IMP)SKSetter_double;
            } break;
            case 'f': {
                imp = (IMP)SKSetter_float;
            } break;
            case 'i': {
                imp = (IMP)SKSetter_int;
            } break;
            case 'l': {
                imp = (IMP)SKSetter_long;
            } break;
            case 'q': {
                imp = (IMP)SKSetter_longlong;
            } break;
            case 's': {
                imp = (IMP)SKSetter_short;
            } break;
            case 'S': {
                imp = (IMP)SKSetter_unsignedshort;
            } break;
            case 'B': {
                imp = (IMP)SKSetter_BOOL;
            } break;
            case 'C': {
                imp = (IMP)SKSetter_unsignedchar;
            } break;
            case 'I': {
                imp = (IMP)SKSetter_unsignedint;
            } break;
            case 'L': {
                imp = (IMP)SKSetter_unsignedlong;
            } break;
            case 'Q': {
                imp = (IMP)SKSetter_unsignedlonglong;
            } break;
            case '#':
            case '@':{
                imp = (IMP)SKSetter_id;
            } break;
            case '{': {
                if(strcmp(argType, @encode(CGPoint)) ==0) {
                    imp = (IMP)SKSetter_CGPoint;
                }
#if TARGET_OS_OSX
                else if (strcmp(argType, @encode(NSPoint)) == 0) {
                    imp = (IMP)SKSetter_CGPoint;
                }
#endif
                else if (strcmp (argType, @encode(NSRange)) == 0) {
                    imp = (IMP)SKSetter_NSRange;
                }
                else if (strcmp(argType,@encode(CGRect)) == 0) {
                    imp = (IMP)SKSetter_CGRect;
                }
#if TARGET_OS_OSX
                else if (strcmp(argType,@encode(NSRect)) == 0) {
                    imp = (IMP)SKSetter_CGRect;
                }
#endif
                else if(strcmp(argType, @encode(CGSize)) == 0) {
                    imp = (IMP)SKSetter_CGSize;
                }
#if TARGET_OS_OSX
                else if (strcmp(argType, @encode(NSSize)) == 0) {
                    imp = (IMP)SKSetter_CGSize;
                }
#endif
            } break;
            default: {
            } break;
        }
    }
    return imp;
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
                IMP imp = __SKSetter(setterMethod);
                NSParameterAssert(imp);
                class_addMethod(observedClass, setterSelector, imp, types);
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
