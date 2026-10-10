# Disk Arbitration claim lab — isolated macOS test (v0.14.0)

## Safety boundaries

A standalone, opt-in Objective-C CLI tests Apple's `DADiskClaim` and
`DADiskUnclaim` on **only blank, unpartitioned, physically external,
unmounted, expendable whole disks**. It does not open /dev nodes, unmount,
initialize, format, partition or write to the disk. It is intentionally NOT
embedded in the app or used to extend privileged broker grants.

On a signed/macOS development host:

```sh
./Scripts/build-claim-lab.sh
./.build/vb-disk-claim-lab --claim-blank disk9 --approve-test-only
```

Substitute the actual BSD name of a disposable blank test drive. The CLI
cross-checks diskutil info/list and refuses anything already partitioned,
mounted, internal, or unexpectedly claimed. It waits for a claim callback,
keeps the claim for two seconds, then unclaims it. Never use your startup disk.

**Caution:** A Disk Arbitration claim coordinates with Disk Arbitration; it
does not exclude other raw block I/O. Unplug testing must take place only on
expendable media, after backups and with no concurrent guest attachment.

## macOS validation to perform

1. Build on target macOS 27 SDK; verify C callbacks, code signature, and
   proper `DASessionScheduleWithRunLoop` integration.
2. Exercise immediate acquisition and release on an empty test disk.
3. Check concurrent claim attempts from two processes; second must fail.
4. Test connect/disconnect, claim denial, timeout and forced process exit.
5. Verify mount-trigger events during a claim, especially hotplug, are handled.
6. Confirm daemon can hold a long-lived per-connection claim without blocking
   other clients; then integrate only after that code is independently reviewed.
7. Only then attempt read-only *inspection* on a cloned external APFS install,
   preserving its partitions and System/Data volume group.

## Current status

The standalone test is **source provided, not compiled or run on macOS**.
No APFS disk descriptor grants are issued by VolumeBoot v0.14.0.
