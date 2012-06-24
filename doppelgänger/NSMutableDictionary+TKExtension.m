//
//  NSMutableDictionary+TKExtension.m
//  doppelgänger
//
//  Created by Tommy Knowlton on 6/23/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "NSMutableDictionary+TKExtension.h"

@implementation NSMutableDictionary (TKExtension)
- (NSSet *)safelyAddObject:(id)o toBucketForKey:(id)k
{
    //  thread-safe
    //  find the bucket (dictionary value of type NSMutableSet) belonging to the key, creating it if need be
    NSMutableSet *bucket = [self objectForKey:k];
    if (nil == bucket)
    {
        NSMutableSet *newBucket = [NSMutableSet setWithObject:o];   //  1
        @synchronized(self)
        {
            bucket = [self objectForKey:k];
            if (nil == bucket)
            {
                bucket = newBucket;
                [self setObject:bucket
                         forKey:k];
                return [NSSet setWithObject:o];   //  with 1 above, this optimizes the case of adding the first item to newly-created buckets (by avoiding additional synchronization below, that is unnecessary in the special case).
            }
        }
    }
    
    //  add the object to the bucket and take an immutable snapshot (for inspection by the caller)
    @synchronized(bucket)
    {
        [bucket addObject: o];
        bucket = [NSSet setWithSet:bucket];
    }
    
    return bucket;
}
@end
