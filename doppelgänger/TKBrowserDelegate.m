//
//  TKBrowserDelegate.m
//  doppelgänger
//
//  Created by Tommy Knowlton on 6/9/12.
//  Copyright (c) 2012 Tommy Knowlton. All rights reserved.
//

#import "TKBrowserDelegate.h"
#import <Security/SecDigestTransform.h>
#import "NSMutableDictionary+TKExtension.h"

static NSArray *VOLUMES_RESOURCE_KEYS = nil;
static NSArray *FILES_RESOURCE_KEYS = nil;
static NSString *const _VOLUME_DUP_FILES_KEY = @"_VOLUME_DUP_FILES_KEY";
static NSString *const _VOLUME_DIGESTS_FILES_MAP_KEY = @"_VOLUME_DIGESTS_FILES_MAP_KEY";

static BOOL inited = NO;

NSData *fileContentDigest(NSURL *file) {
    CFReadStreamRef cfrs = CFReadStreamCreateWithFile(kCFAllocatorDefault, (__bridge CFURLRef)file);
    SecTransformRef readTransform = SecTransformCreateReadTransformWithReadStream(cfrs);
    CFErrorRef error = NULL;
    SecTransformRef digester = SecDigestTransformCreate(kSecDigestSHA2, 0, &error);
    SecGroupTransformRef group = SecTransformConnectTransforms(readTransform,
                                                               kSecTransformOutputAttributeName,
                                                               digester,
                                                               kSecTransformInputAttributeName,
                                                               SecTransformCreateGroupTransform(),
                                                               &error);
    
    CFRelease(digester);
    CFRelease(readTransform);
    CFRelease(cfrs);
    
    CFDataRef digest = SecTransformExecute(group, &error);
    CFRelease(group);
    
    return (__bridge_transfer NSData *)digest;
}

@implementation TKBrowserDelegate
+ (id)alloc
{
    @synchronized(self)
    {
        if (!inited) {
            inited = YES;
            VOLUMES_RESOURCE_KEYS = [NSArray arrayWithObjects:NSURLVolumeIsLocalKey, NSURLLocalizedNameKey, nil];    
            FILES_RESOURCE_KEYS = [[NSArray alloc] init];   //  TODO: what keys do we need?
        }
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
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (0 == column) 
    {
        result = [volumes count];
        if (!result) 
        {
            // enumerate volumes that can be scanned
            for (NSURL *url in [fm mountedVolumeURLsIncludingResourceValuesForKeys:VOLUMES_RESOURCE_KEYS options: (NSVolumeEnumerationSkipHiddenVolumes)])
            {
                NSMutableDictionary *value = [NSMutableDictionary dictionaryWithDictionary:[url resourceValuesForKeys:VOLUMES_RESOURCE_KEYS error:nil]];
                
                NSString *volName = [value objectForKey:NSURLLocalizedNameKey];
                if (volName)
                {
                    NSLog(@"adding volume \"%@\".", volName);
                    [volumes addObject:value];
                }
            }
            result = [volumes count];
        }
    } 
    else if (1 == column) 
    {
        //  figure out which is the selected volume (row) from column 0
        NSInteger row = [sender selectedRowInColumn:0];
        
        //  if a scan is not yet in-progress or completed for the selected volume, start one
        NSMutableDictionary *volumeInfo = [volumes objectAtIndex:row];
        NSMutableSet *dfs = [volumeInfo objectForKey:_VOLUME_DUP_FILES_KEY];
        
        if (nil == dfs)
        {
            dfs = [[NSMutableSet alloc] init];
            [volumeInfo setObject:dfs forKey:_VOLUME_DUP_FILES_KEY];    //  no race here because we're on the UI thread
            NSMutableDictionary *filesSizesDict = [[NSMutableDictionary alloc] init];
            NSMutableDictionary *filesDigestsDict = [[NSMutableDictionary alloc] init];
            NSURL *volumeUrl = [volumeInfo objectForKey:NSURLVolumeURLKey];
            NSDirectoryEnumerator *vfe = [fm enumeratorAtURL:volumeUrl
                                  includingPropertiesForKeys:FILES_RESOURCE_KEYS
                                                     options:0
                                                errorHandler:nil];
            NSOperationQueue *que0 = [[NSOperationQueue alloc] init],
            *que1 = [[NSOperationQueue alloc] init];

            //  don't block the UI thread during enumerating                
            [que0 addOperationWithBlock:^{
                for (NSURL *file in vfe)
                {
                    NSNumber *isRegularFile = nil;
                    NSError *err1 = nil;
                    if ([file getResourceValue:&isRegularFile
                                        forKey:NSURLIsRegularFileKey
                                         error:&err1] &&
                        [isRegularFile boolValue])
                    {
                        //  then see whether the file could be a duplicate of another file...
                        //  try to do it efficiently
                        [que1 addOperationWithBlock:^{
                            //  put each regular file into a bucket that is keyed by the file's content length

                            NSNumber *fileSize;
                            NSError *err2;
                            if (![file getResourceValue:&fileSize
                                                 forKey:NSURLFileSizeKey
                                                  error:&err2])
                            {
                                NSLog(@"Error getting the file size for %@: %@", file, err2);
                                return;
                            }                        

                            //  for purposes of this app, ignore files having file size < 64 bytes. Yes, that is arbitrary. IMO, you're not actually going to get any useful savings by hard-linking these files.
                            
                            if (65LL > [fileSize longLongValue])
                            {
                                return;
                            }
                            
                            NSSet *sameSizeFiles = [filesSizesDict safelyAddObject:file
                                                                    toBucketForKey:fileSize];
                            
                            //  if this is the first and only file in that bucket, we have no reason to compute a content digest; this might be the only file we ever see having the same fileSize
                            NSUInteger bucketSize = [sameSizeFiles count];
                            if (1 == bucketSize)
                            {
                                return;
                            }

                            //  if this file is the first collision into this size bucket, (a special case, owing to the optimization of avoiding the digest by returning early (see immediately preceding if statement) where there was only one file in this bucket)
                            NSSet *sameDigestFiles;
                            NSData *digest;
                            if (2 == bucketSize)
                            {
                                //  then add the content digests for both files to the digests dictionary
                                
                                for (NSURL *f in sameSizeFiles) 
                                {
                                    digest = fileContentDigest(f);                                                                        
                                    sameDigestFiles = [filesDigestsDict safelyAddObject:f 
                                                                         toBucketForKey:digest];                                    
                                }
                            }
                            else 
                            {
                                //  else add the content digest for this file to the digests dictionary
                                digest = fileContentDigest(file);
                                sameDigestFiles = [filesDigestsDict safelyAddObject:file
                                                                     toBucketForKey:digest];
                            }
                            
                            NSUInteger digestCollisions = [sameDigestFiles count];                            
                            if (1 < digestCollisions)
                            {
                                NSLog(@"probable file duplication at bucket for digest key %@: %@", [digest description], sameDigestFiles);
                                
                                [dfs addObject:file];
                            }                                                              
                        }];
                    }
                    else if (nil != err1) {
                        NSLog(@"Error checking whether URL %@ is a regular file: %@", file, err1);
                        return;
                    }
                }
                NSLog(@"finished enumerating volume %@", volumeUrl);
            }];
        }
        //  return the count of duplicates found so-far
        result = [dfs count];        
    }
    else
    {
        //  TODO
        //  rows in this column are tuples (content-md5, content-length) identifying content that is duplicated
    }
    
    return result;
}

- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
    NSLog(@"browser:%p willDisplayCell:%p atRow:%ld column:%ld", (__bridge void *)sender, (__bridge void *)cell, row, column);
    
    
    if (0 == column) 
    {
        NSMutableDictionary *value = [volumes objectAtIndex:row];
        
        NSImage *image = [value valueForKey:NSURLEffectiveIconKey];
        [image setSize:NSMakeSize(16.0f, 16.0f)];
        NSBrowserCell *browserCell = (NSBrowserCell *)cell;
        [browserCell setImage:image];
        
        [browserCell setTitle:[value objectForKey:NSURLLocalizedNameKey]];
    }
}

@end
