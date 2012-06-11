//
//  TKBrowserDelegate.h
//  doppelgänger
//
//  Created by Tommy Knowlton on 6/9/12.
//  Copyright (c) 2012 Tommy Knowlton. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TKBrowserDelegate : NSObject<NSBrowserDelegate>
{
    NSMutableArray *volumes;
}
- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column;
- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column;
@end
