//
//  ViewController.m
//  SafeKVO
//
//  Created by niezhiqiang on 2021/8/11.
//

#import "ViewController.h"
#import "NSObject+SafeKVO.h"
#import "Person.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    Person *person = [Person new];
    Child *child = [Child new];
    Boy *boy = [Boy new];
    
    person.child = child;
    child.boy = boy;
    boy.age = @12;
    boy.count = 2;
    boy.point = CGPointMake(1, 2);

    
    [person sk_addObserver:self forKeyPath:@"child.boy.point" observeValueChanged:^(id  _Nonnull object, NSString * _Nonnull keyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"-------------------------");
        NSLog(@"object：%@",object);
        NSLog(@"keyPath：%@",keyPath);
        NSLog(@"oldValue：%@",oldValue);
        NSLog(@"newValue：%@",newValue);
    }];
    [person sk_addObserver:self forKeyPath:@"child.boy" observeValueChanged:^(id  _Nonnull object, NSString * _Nonnull keyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"-------------------------");
        NSLog(@"object：%@",object);
        NSLog(@"keyPath：%@",keyPath);
        NSLog(@"oldValue：%@",oldValue);
        NSLog(@"newValue：%@",newValue);
    }];
    [person sk_addObserver:self forKeyPath:@"child" observeValueChanged:^(id  _Nonnull object, NSString * _Nonnull keyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"-------------------------");
        NSLog(@"object：%@",object);
        NSLog(@"keyPath：%@",keyPath);
        NSLog(@"oldValue：%@",oldValue);
        NSLog(@"newValue：%@",newValue);
    }];
    person.child = [Child new];
    
    [person sk_removeObserver:self forKeyPath:@"child.boy.point"];
    [person sk_removeObserver:self forKeyPath:@"child.boy"];
    [person sk_removeObserver:self forKeyPath:@"child"];
}


@end
