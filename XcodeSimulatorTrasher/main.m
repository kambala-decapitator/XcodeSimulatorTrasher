//
//  main.m
//  XcodeSimulatorTrasher
//
//  Created by Andrey Filipenkov on 14/01/17.
//  Copyright © 2017 Andrey Filipenkov. All rights reserved.
//

@import Foundation;

#include <libgen.h>

static NSString *const SimulatorsRelativePath = @"Developer/CoreSimulator/Devices", *const DeviceSetPlist = @"device_set.plist";
static NSString *const DefaultDevicesKey = @"DefaultDevices";

int main(int argc, char *argv[])
{
    @autoreleasepool
    {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *libraryUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
        if (!libraryUrl)
        {
            printf("~/Library not found\n");
            return 1;
        }

        NSURL *simulatorsUrl = [libraryUrl URLByAppendingPathComponent:SimulatorsRelativePath isDirectory:YES];
        NSURL *deviceSetPlistUrl = [simulatorsUrl URLByAppendingPathComponent:DeviceSetPlist];
        if (argc < 2)
        {
            printf("usage: %s [one or more %s dictionary keys from %s]\n", basename(argv[0]), DefaultDevicesKey.UTF8String, deviceSetPlistUrl.path.UTF8String);
            return 2;
        }

        if (![fm fileExistsAtPath:simulatorsUrl.path])
        {
            printf("directory %s not found\n", simulatorsUrl.path.UTF8String);
            return 3;
        }
        if (![fm fileExistsAtPath:deviceSetPlistUrl.path])
        {
            printf("file %s not found\n", deviceSetPlistUrl.path.UTF8String);
            return 4;
        }

        NSError *error;
        NSData *deviceSetPlistData = [NSData dataWithContentsOfURL:deviceSetPlistUrl options:NSDataReadingUncached error:&error];
        if (!deviceSetPlistData)
        {
            printf("error reading file: %s\n", error.description.UTF8String);
            return 5;
        }

        error = nil;
        NSMutableDictionary *deviceSetPlist = [NSPropertyListSerialization propertyListWithData:deviceSetPlistData options:NSPropertyListMutableContainers format:NULL error:&error];
        if (!deviceSetPlist)
        {
            printf("error deserializing plist: %s\n", error.description.UTF8String);
            return 6;
        }

        NSMutableDictionary<NSString *, NSMutableDictionary *> *defaultDevices = deviceSetPlist[DefaultDevicesKey];
        if (!defaultDevices)
        {
            printf("key %s is missing from %s\n", DefaultDevicesKey.UTF8String, deviceSetPlistUrl.path.UTF8String);
            return 7;
        }

        if (![fm changeCurrentDirectoryPath:simulatorsUrl.path])
        {
            printf("unable to change current directory to %s\n", simulatorsUrl.path.UTF8String);
            return 8;
        }

        BOOL shouldWriteFile = NO;
        for (int i = 1; i < argc; ++i)
        {
            NSString *simulatorRuntime = @(argv[i]);
            NSMutableDictionary<NSString *, NSString *> *simulatorDevicesDic = defaultDevices[simulatorRuntime];
            if (!simulatorDevicesDic)
            {
                printf("key %s not found\n", simulatorRuntime.UTF8String);
                continue;
            }

            NSMutableArray<NSString *> *trashedDevices = [NSMutableArray arrayWithCapacity:simulatorDevicesDic.count];
            [simulatorDevicesDic enumerateKeysAndObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSString * _Nonnull key, NSString * _Nonnull simulatorDirectoryName, BOOL * _Nonnull stop) {
                NSMutableArray<NSString *> *logLines = [NSMutableArray arrayWithCapacity:3];
                [logLines addObject:[NSString stringWithFormat:@"trashing simulator directory %@ of device %@", simulatorDirectoryName, key]];
                NSError *trashError;
                if ([fm trashItemAtURL:[NSURL fileURLWithPath:simulatorDirectoryName] resultingItemURL:NULL error:&trashError])
                    [trashedDevices addObject:key];
                else
                {
                    [logLines addObject:[NSString stringWithFormat:@"error: %@", trashError]];
                    [logLines addObject:@"----------"];
                }
                printf("%s\n", [logLines componentsJoinedByString:@"\n"].UTF8String);
            }];
            if (trashedDevices.count == simulatorDevicesDic.count)
            {
                [defaultDevices removeObjectForKey:simulatorRuntime];
                shouldWriteFile = YES;
            }
            else
            {
                [simulatorDevicesDic removeObjectsForKeys:trashedDevices];
                if (trashedDevices.count > 0)
                    shouldWriteFile = YES;
            }
        }

        if (shouldWriteFile)
        {
            printf("saving changes to %s\n", deviceSetPlistUrl.path.UTF8String);
            if (![deviceSetPlist writeToURL:deviceSetPlistUrl atomically:YES])
            {
                printf("error writing file\n");
                return 9;
            }
        }
        else
            printf("no changes - not overwriting %s\n", deviceSetPlistUrl.path.UTF8String);
    }
    return 0;
}
