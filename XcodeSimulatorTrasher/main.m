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
        if (argc == 2 && (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help") || !strcmp(argv[1], "help")))
        {
            const char *executableName = basename(argv[0]);
            printf("usage: %s\n"
                   "    show available simulator runtimes and select which to trash\n"
                   "OR\n"
                   "usage: %s <simulator_runtime> ...\n"
                   "    trash provided simulator runtimes\n\n"
                   "simulator runtimes are '%s' dictionary keys in %s\n",
                   executableName, executableName, DefaultDevicesKey.UTF8String, deviceSetPlistUrl.path.UTF8String);
            return 0;
        }

        if (![fm fileExistsAtPath:simulatorsUrl.path])
        {
            printf("directory %s not found\n", simulatorsUrl.path.UTF8String);
            return 2;
        }
        if (![fm fileExistsAtPath:deviceSetPlistUrl.path])
        {
            printf("file %s not found\n", deviceSetPlistUrl.path.UTF8String);
            return 3;
        }

        NSError *error;
        NSData *deviceSetPlistData = [NSData dataWithContentsOfURL:deviceSetPlistUrl options:NSDataReadingUncached error:&error];
        if (!deviceSetPlistData)
        {
            printf("error reading file: %s\n", error.description.UTF8String);
            return 4;
        }

        error = nil;
        NSMutableDictionary *deviceSetPlist = [NSPropertyListSerialization propertyListWithData:deviceSetPlistData options:NSPropertyListMutableContainers format:NULL error:&error];
        if (!deviceSetPlist)
        {
            printf("error deserializing plist: %s\n", error.description.UTF8String);
            return 5;
        }

        NSMutableDictionary *defaultDevices = deviceSetPlist[DefaultDevicesKey];
        if (!defaultDevices)
        {
            printf("key '%s' is missing from %s\n", DefaultDevicesKey.UTF8String, deviceSetPlistUrl.path.UTF8String);
            return 6;
        }
        if (!defaultDevices.count)
        {
            printf("no simulator runtimes installed, nothing to do\n");
            return 0;
        }

        if (![fm changeCurrentDirectoryPath:simulatorsUrl.path])
        {
            printf("unable to change current directory to %s\n", simulatorsUrl.path.UTF8String);
            return 7;
        }

        NSArray<NSString *> *simulatorRuntimesToTrash;
        if (argc == 1)
        {
            NSMutableArray<NSString *> *simulatorRuntimes = [NSMutableArray arrayWithCapacity:defaultDevices.count];
            [defaultDevices enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id _Nonnull obj, BOOL * _Nonnull stop) {
                if ([obj isKindOfClass:[NSDictionary class]]) // ignore key "version" which is a number
                    [simulatorRuntimes addObject:key];
            }];
            [simulatorRuntimes sortUsingComparator:^NSComparisonResult(NSString * _Nonnull obj1, NSString * _Nonnull obj2) {
                return [obj1 compare:obj2 options:NSNumericSearch];
            }];

            printf("available simulator runtimes:\n");
            [simulatorRuntimes enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                printf("%lu) %s\n", idx + 1, obj.UTF8String);
            }];

            const char *quitString = "quit";
            const NSUInteger min = 1, max = simulatorRuntimes.count;
            printf("\nenter space-separated list of simulator runtime indexes (%lu-%lu) to trash or '%s' to quit:\n", min, max, quitString);

            const int bufSize = 255;
            char input[bufSize];
            if (!fgets(input, bufSize - 1, stdin))
            {
                int ret = feof(stdin) ? 0 : 8;
                clearerr(stdin);
                return ret;
            }
            if (!strncmp(input, quitString, strlen(quitString)))
                return 0;

            NSMutableIndexSet *indexSet = [NSMutableIndexSet new];
            for (NSString *s in [@(input) componentsSeparatedByString:@" "])
            {
                NSInteger i = s.integerValue;
                if (i >= min && i <= max)
                    [indexSet addIndex:i - 1];
            }
            simulatorRuntimesToTrash = [simulatorRuntimes objectsAtIndexes:indexSet];
        }
        else
        {
            NSMutableArray<NSString *> *simulatorRuntimesToTrashMutable = [NSMutableArray arrayWithCapacity:argc - 1];
            for (int i = 1; i < argc; ++i)
                [simulatorRuntimesToTrashMutable addObject:@(argv[i])];
            simulatorRuntimesToTrash = simulatorRuntimesToTrashMutable;
        }

        BOOL shouldWriteFile = NO;
        for (NSString *simulatorRuntime in simulatorRuntimesToTrash)
        {
            NSMutableDictionary<NSString *, NSString *> *simulatorDevicesDic = defaultDevices[simulatorRuntime];
            if (!simulatorDevicesDic)
            {
                printf("simulator runtime '%s' not found\n", simulatorRuntime.UTF8String);
                continue;
            }
            if (![simulatorDevicesDic isKindOfClass:[NSDictionary class]])
            {
                printf("object under key '%s' is not a dictionary: %s\n", simulatorRuntime.UTF8String, simulatorDevicesDic.description.UTF8String);
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
