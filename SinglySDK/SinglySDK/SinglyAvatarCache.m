//
//  SinglyAvatarCache.m
//  SinglySDK
//
//  Copyright (c) 2012 Singly, Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//


#import "SinglyAvatarCache.h"

static SinglyAvatarCache *sharedInstance = nil;

@implementation SinglyAvatarCache

+ (SinglyAvatarCache *)sharedCache
{
    static dispatch_once_t queue;
    dispatch_once(&queue, ^{
        sharedInstance = [[SinglyAvatarCache alloc] init];
    });

    return sharedInstance;
}

+ (SinglyAvatarCache *)sharedCacheInstance
{
    return sharedInstance;
}

- (void)cacheImage:(UIImage *)image forURL:(NSString *)url
{
    if (!url)
    {
        [NSException raise:NSInvalidArgumentException
                    format:@"%s: attempt to insert nil key", __PRETTY_FUNCTION__];
    }
    [self setObject:image forKey:url];
}

- (UIImage *)cachedImageForURL:(NSString *)url
{
    return [self objectForKey:url];
}

- (BOOL)cachedImageExistsForURL:(NSString *)url
{
    return [self objectForKey:url] != nil;
}

@end
