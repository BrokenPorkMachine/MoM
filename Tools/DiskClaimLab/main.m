// macOS-only opt-in integration laboratory. NOT part of VolumeBoot.app.
// Exercises DADiskClaim and DADiskUnclaim against disposable BLANK external
// unmounted media, without ever opening /dev or issuing writes/unmounts.
#import <Foundation/Foundation.h>
#import <DiskArbitration/DiskArbitration.h>
#include <unistd.h>
#include <string.h>

static NSDictionary *VBPlist(NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/diskutil"];
    task.arguments = arguments;
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return nil;
    NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0 || data.length > 4 * 1024 * 1024) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static BOOL VBEligibleBlankExternal(NSString *name) {
    NSDictionary *info = VBPlist(@[@"info", @"-plist", name]);
    NSDictionary *list = VBPlist(@[@"list", @"-plist"]);
    if (!info || !list) return NO;
    if (![info[@"DeviceIdentifier"] isEqual:name] || ![info[@"WholeDisk"] isEqual:@YES] ||
        ![info[@"Internal"] isEqual:@NO] || ![info[@"VirtualOrPhysical"] isEqual:@"Physical"] ||
        ![info[@"DeviceLocation"] isEqual:@"External"] || ![info[@"Mounted"] isEqual:@NO]) return NO;
    NSString *mediaContent = info[@"Content"];
    if (![mediaContent isKindOfClass:[NSString class]] ||
        (mediaContent.length > 0 && ![mediaContent isEqualToString:@"0"])) return NO;
    if (![info[@"TotalSize"] respondsToSelector:@selector(unsignedLongLongValue)] ||
        [info[@"TotalSize"] unsignedLongLongValue] == 0) return NO;
    for (NSString *key in @[@"FilesystemName", @"FilesystemType", @"FilesystemUserVisibleName",
                             @"APFSContainerReference", @"VolumeName"]) {
        id value = info[key];
        if (value && value != [NSNull null] && (![value isKindOfClass:[NSString class]] || [value length] > 0)) return NO;
    }
    NSArray *disks = list[@"AllDisksAndPartitions"];
    if (![disks isKindOfClass:[NSArray class]]) return NO;
    NSInteger count = 0;
    for (NSDictionary *disk in disks) {
        if (![disk isKindOfClass:[NSDictionary class]]) return NO;
        if ([disk[@"DeviceIdentifier"] isEqual:name]) {
            count++;
            id parts = disk[@"Partitions"];
            if (parts && (![parts isKindOfClass:[NSArray class]] || [parts count] > 0)) return NO;
            NSString *content = disk[@"Content"];
            if (![content isKindOfClass:[NSString class]] ||
                (content.length > 0 && ![content isEqualToString:@"0"])) return NO;
        }
    }
    return count == 1;
}

typedef struct { BOOL completed; BOOL acquired; BOOL releaseRequested; } VBClaim;

static DADissenterRef VBClaimRelease(DADiskRef disk, void *context) {
    // Ask Disk Arbitration to retain the claim until this test finishes.
    // This is coordination with Disk Arbitration, NOT a kernel I/O lock.
    (void)disk;
    VBClaim *claim = context;
    claim->releaseRequested = YES;
    return DADissenterCreate(kCFAllocatorDefault, kDAReturnNotPermitted,
                            CFSTR("VolumeBoot claim laboratory still active"));
}
static void VBClaimComplete(DADiskRef disk, DADissenterRef dissenter, void *context) {
    (void)disk;
    VBClaim *claim = context;
    claim->completed = YES;
    claim->acquired = dissenter == NULL;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4 || strcmp(argv[1], "--claim-blank") || strcmp(argv[3], "--approve-test-only")) {
            fprintf(stderr, "Usage: vb-disk-claim-lab --claim-blank diskN --approve-test-only\n"
                            "ONLY expendable blank, unmounted external whole disks. NO writes.\n");
            return 64;
        }
        NSString *name = [NSString stringWithUTF8String:argv[2]];
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^disk(0|[1-9][0-9]*)$" options:0 error:NULL];
        if (!name || [pattern numberOfMatchesInString:name options:0 range:NSMakeRange(0,name.length)] != 1) {
            fprintf(stderr, "Invalid disk name\n"); return 65;
        }
        if (!VBEligibleBlankExternal(name)) {
            fprintf(stderr, "DENIED: not an unmounted, empty, external whole disk\n"); return 77;
        }
        DASessionRef session = DASessionCreate(kCFAllocatorDefault);
        if (!session) return 70;
        DADiskRef disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, name.UTF8String);
        if (!disk) { CFRelease(session); return 70; }
        DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        if (DADiskIsClaimed(disk) || !VBEligibleBlankExternal(name)) {
            fprintf(stderr, "DENIED: claimed or changed during preflight\n");
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
            CFRelease(disk); CFRelease(session); return 77;
        }
        VBClaim claim = {0};
        DADiskClaim(disk, kDADiskClaimOptionDefault, VBClaimRelease, &claim, VBClaimComplete, &claim);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
        while (!claim.completed && [deadline timeIntervalSinceNow] > 0) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
        }
        BOOL acquired = claim.completed && claim.acquired;
        if (acquired && !VBEligibleBlankExternal(name)) {
            fprintf(stderr, "DENIED: disk metadata changed after claim acquisition\n");
            DADiskUnclaim(disk);
            acquired = NO;
        }
        if (acquired) {
            puts("CLAIM ACQUIRED: observing for 2 seconds (no reads of raw blocks, no writes)");
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow:2];
            while ([end timeIntervalSinceNow] > 0) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
            }
            DADiskUnclaim(disk);
            puts("CLAIM RELEASED");
        } else {
            // Async completion might arrive later. This utility must not free
            // its context until the callback has completed. Stop the run loop
            // only once Disk Arbitration has delivered a response.
            if (!claim.completed) {
                fprintf(stderr, "CLAIM TIMEOUT: exiting without unloading session state\n");
                _exit(75);
            }
            fprintf(stderr, "CLAIM DENIED by Disk Arbitration\n");
        }
        DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(disk); CFRelease(session);
        if (claim.releaseRequested) fprintf(stderr, "Notice: claim-release callback was requested\n");
        return acquired ? 0 : 77;
    }
}
