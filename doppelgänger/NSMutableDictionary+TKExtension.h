//
//  NSMutableDictionary+TKExtension.h
//  doppelgänger
//
//  Created by Tommy Knowlton on 6/23/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableDictionary (TKExtension)
- (NSSet *)safelyAddObject: (id)o toBucketForKey: (id)k;
@end

