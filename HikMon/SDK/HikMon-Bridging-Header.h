//
//  HikMon-Bridging-Header.h
//  Swift 侧只能看到这个 ObjC 门面，绝不能把 HCNetSDK.h 塞进来
//  （那个头会 #define BOOL int / #define NULL 0，进了桥接头会毁掉 Foundation）
//

#ifndef HikMon_Bridging_Header_h
#define HikMon_Bridging_Header_h

#import "HikMonSDK.h"

#endif
