# SafeKVO

#### 系统API以及用法

翻开苹果的观察者api，实现很简洁接口也很少，定义在**NSKeyValueObserving.h**里面
```
@interface NSObject(NSKeyValueObserverRegistration)

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(nullable void *)context;
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(nullable void *)context API_AVAILABLE(macos(10.7), ios(5.0), watchos(2.0), tvos(9.0));
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;

@end

@interface NSObject(NSKeyValueObserving)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;

@end

@interface NSObject(NSKeyValueObserverNotification)

- (void)willChangeValueForKey:(NSString *)key;
- (void)didChangeValueForKey:(NSString *)key;

@end
```

如上，是通过给NSObject添加分类实现的：
+ **NSKeyValueObserverRegistration注册观察者**
+ **observeValueForKeyPath观察者回调**
+ **NSKeyValueObserverNotification观察者通知**

使用起来也很简单，我们定义一个Person类，添加三个属性a、b、c

```
@interface Person : NSObject

@property (nonatomic, assign) NSInteger a;
@property (nonatomic, assign) NSInteger b;
@property (nonatomic, assign) NSInteger c;

@end

@interface ViewController ()

@property (nonatomic, strong) Person *person;

@end

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.person addObserver:self
                  forKeyPath:@"a"
                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                     context:nil];
    [self.person addObserver:self
                  forKeyPath:@"b"
                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                     context:nil];
    [self.person addObserver:self
                  forKeyPath:@"c"
                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                     context:nil];
    self.person.a = 10;
    self.person.b = 5;
    self.person.c = 2;
    [self.person removeObserver:self forKeyPath:@"a"];
    [self.person removeObserver:self forKeyPath:@"b"];
    [self.person removeObserver:self forKeyPath:@"c"];
    NSLog(@"person对象观察者全部移除");
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
    NSLog(@"%@属性变化：%@", keyPath, change);
}

- (Person *)person {
    if (!_person) {
        _person = [[Person alloc] init];
    }
    return _person;
}

```

初始值都是0，控制台输出如下
```
2021-08-10 21:55:30.100992+0800 test[19703:48456267] a属性变化：{
    kind = 1;
    new = 10;
    old = 0;
}
2021-08-10 21:55:30.101123+0800 test[19703:48456267] b属性变化：{
    kind = 1;
    new = 5;
    old = 0;
}
2021-08-10 21:55:30.101235+0800 test[19703:48456267] c属性变化：{
    kind = 1;
    new = 2;
    old = 0;
}
2021-08-10 21:55:30.101336+0800 test[19703:48456267] person对象观察者全部移除
```

![](https://upload-images.jianshu.io/upload_images/8431568-34901b30c9aff824.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/810)

我们在如上位置打上断点，然后在控制台打印person的isa指针，输出如下
```
(lldb) po self.person->isa
NSKVONotifying_Person

(lldb) po self.person->isa
Person
```
可以看到，**对象的观察者没有完全移除的时候isa指向NSKVONotifying_Person，完全移除之后isa指向Person**

#### 实现原理

苹果的官方文档有[KVO实现原理](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/KeyValueObserving/Articles/KVOImplementation.html)的描述，很遗憾KVO的源码没有开源，不过通过上面在控制台的打印结果，也能侧面印证底层实现
> **当对象的属性被添加观察者时，一个继承自该对象所属类的子类被动态创建，接着修改该对象的isa指针，使其指向该子类，并重写了被观察属性的`setter`方法，依次调用`willChangeValueForKey`、父类的`setter`方法、`didChangeValueForKey`，最后会调用到该对象的`observeValueForKeyPath`方法，不仅如此苹果还修改了class方法的返回值使其返回对象原本的类，目的是隐藏观察者的底层实现，当对象属性的观察者被全部移除之后，对象的isa指针会被修正，重新指向原本的类**

#### 观察者相关的crash

+ 添加次数多于移除次数，当监听者释放后，触发observeValueForKeyPath时crash
+ 添加次数少于移除次数指直接crash
+ 观察者没有实现observeValueForKeyPath时直接crash

如上几个crash苹果完全有能力避免他们发生，但是为什么苹果没有做这件事呢，因为他不知道用户的真正意图，苹果期望在调试阶段就暴露可能有问题的逻辑，让其直接crash，然而事与愿违，通常我们是成对调用的，但是由于某种原因，导致添加和移除的次数无法匹配，最终导致线上大量的crash，所以crash防护需求就诞生了，**没有什么问题是添加一个中间层解决不了的，如果有，那就再添加一层**
在添加或移除观察者之前插入一层数据结构用于存储次数，比如哈希表

> 添加观察者时：控制只添加一次
移除观察者时：控制只移除一次
观察键值改变时：控制消息分发到观察者上

**为了避免被观察者提前被释放后，触发observeValueForKeyPath时的crash，需要hook一下NSObject的`dealloc`方法，在对象`dealloc`函数调用之前，移除相关观察者。**

**还是有点复杂！**有没有一种方案既可以实现安全性又不用hook系统方法呢？

#### 实现安全的观察者

##### 一、API

干脆用runtime库自己实现一个安全的观察者，根据其实现原理，仿照系统api，通过分类的方式添加一个中间层，作者写了一个工具，下面讲述下实现原理，如下接口类似系统api，只是把回调函数写成了block

```
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
```

> **同时去掉了context和options参数**
原因是context参数用于给同一个属性添加同一个观察者同时代入上下文，回调时用于反解参数，基本没啥场景，options参数用于描述属性改变的类型，通常只用new和change，工具已经实现这两种类型，综上省略了context和options参数

##### 二、安全数据模型
用于存储：观察者、被观察者、属性链、观察者回调到关联对象
```
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
```

##### 三、工具函数

通过属性名生成`setter`的**`SEL`**
```
static forceInline SEL sk_setterSelectorFromPropertyName(NSString *propertyName) {
    if (propertyName.length <= 0)
        return nil;
    NSString *setterString = [NSString stringWithFormat:@"set%@%@:", [[propertyName substringToIndex:1] uppercaseString], [propertyName substringFromIndex:1]];
    return NSSelectorFromString(setterString);
}
```
通过`setter`方法名生成属性名
```
static forceInline NSString *sk_propertyNameFromSetterString(NSString *setterString) {
    if (setterString.length <= 0 || ![setterString hasPrefix: @"set"] || ![setterString hasSuffix: @":"])
        return nil;
    NSRange range = NSMakeRange(3, setterString.length - 4);
    NSString *propertyName = [setterString substringWithRange:range];
    propertyName = [propertyName stringByReplacingCharactersInRange: NSMakeRange(0, 1) withString:[[propertyName substringToIndex: 1] lowercaseString]];
    return propertyName;
}
```
**核心方法**，子类重写`setter`方法，内部调用父类的`setter`方法修改值，注意**系统的是现实在调用父类`setter`方法前后分别调用`willChangeValueForKey`和`didChangeValueForKey`方法，然后通过`observeValueForKeyPath`方法回调到父类，而我们这里直接通过自定义的block回调，因此不用调用上面两个方法**
```
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
```
返回父类的Class用于重写子类的Class方法
```
static forceInline Class sk_class(id self) {
    return class_getSuperclass(object_getClass(self));
}
```
**核心方法**，用于动态创建子类并注册到运行时环境
```
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
```
判断对象是否能响应传入的**`SEL`**
```
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
```
##### 四、API实现

添加安全观察者，此处有个难点就是keyPath的处理，需要通过属性链中的类一一生成其子类，因为keyPath中的任意节点变化都有可能导致最终的属性变化，都是我们监听的范围

```
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
```
遍历清除观察者，若已经清空则修正对象的isa指针
```
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
```

#### 总结
本工具支持了多线程，同时通过runtime和关联对象实现了安全观察者，解决了观察者添加、移除、回调的各种crash，注意，**本代码还没有经过大量使用，如有需要，请务必反复测试之后再应用于项目中**
