//
//  TKBrowserDelegate.m
//  doppelgänger
//
//  Created by Tommy Knowlton on 6/9/12.
//  Copyright (c) 2012 Tommy Knowlton. All rights reserved.
//

#import "TKBrowserDelegate.h"

static NSArray *VOLUMES_RESOURCE_KEYS = nil;
static NSInteger _inited = 0;
static NSString *const _VOLUME_DUP_FILES_KEY = @"_VOLUME_DUP_FILES_KEY";

@implementation TKBrowserDelegate
+ (id)alloc
{
    if (OSAtomicTestAndSet(1, &_inited))
    {
        VOLUMES_RESOURCE_KEYS = [NSArray arrayWithObjects:NSURLVolumeIsLocalKey, NSURLLocalizedNameKey, nil];    

    }
    
    return [super alloc];
}

- (id)init
{
    self = [super init];
    
    volumes = [[NSMutableArray alloc] init];

    return self;
}

- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column
{
    NSLog(@"browser:%p numberOfRowsInColumn:%ld", (__bridge void *)sender, column);

    NSInteger result = 0;
    
    if (0 == column) {
        result = [volumes count];
        if (!result) {
            // enumerate volumes that can be scanned
            NSFileManager *fm = [NSFileManager defaultManager];

            for (NSURL *url in [fm mountedVolumeURLsIncludingResourceValuesForKeys:VOLUMES_RESOURCE_KEYS options: (NSVolumeEnumerationSkipHiddenVolumes)])
            {
                NSMutableDictionary *value = [NSMutableDictionary dictionaryWithDictionary:[url resourceValuesForKeys:VOLUMES_RESOURCE_KEYS error:nil]];
                
                NSString *volName = [value objectForKey:NSURLLocalizedNameKey];
                if (volName)
                {
                    NSLog(@"adding volume \"%@\".", volName);
                    [value setObject:[[NSMutableArray alloc] init] forKey:_VOLUME_DUP_FILES_KEY];
                    [volumes addObject:value];
                }
            }
            result = [volumes count];
        }
    } else if (1 == column) {
        //  if a scan is in-progress or completed for the selected volume, enable the rescan action,
        //  else enqueue a task to scan the files on the volume
    } else {
        //  rows in this column are individual files on the same volume, that have identical contents; each row is a full-path
    }
    
    return result;
}

- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
    NSLog(@"browser:%p willDisplayCell:%p atRow:%ld column:%ld", (__bridge void *)sender, (__bridge void *)cell, row, column);
    

    if (0 == column) {
        NSMutableDictionary *value = [volumes objectAtIndex:row];

        NSImage *image = [value valueForKey:NSURLEffectiveIconKey];
        [image setSize:NSMakeSize(16.0f, 16.0f)];
        NSBrowserCell *browserCell = (NSBrowserCell *)cell;
        [browserCell setImage:image];

        [browserCell setTitle:[value objectForKey:NSURLLocalizedNameKey]];
    }
}

@end
