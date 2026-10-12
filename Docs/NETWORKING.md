# Network Backend — MacOnMac

Current shipping status is documented in [SUPPORT_MATRIX.md](SUPPORT_MATRIX.md). Bridged networking is disabled; the v0.15 details below record the implementation history and must not be read as current availability.

## Scope and configuration

- Default mode is `nat` using `VZVirtioNetworkDeviceConfiguration` and `VZNATNetworkDeviceAttachment` (already present in prior versions but now configurable).
- `disconnected`: guest receives no virtual network adapter.
- `bridged`: select one of `VZBridgedNetworkInterface.networkInterfaces`; mapped using `VZBridgedNetworkDeviceAttachment`.
- Network profiles stored at `<VM Folder>/connectivity.json` and read at **every** new guest launch. Existing VMs without this file default to NAT.
- Stable locally administered unicast MAC derived from the persisted VM manifest UUID; does not rotate across guest boots.

## Entitlements

Bridged networking is disabled in the current release: it is omitted from the UI and rejected by connectivity policy. Older saved profiles that request bridging are loaded with NAT selected. The entitlement file remains a research template and does not enable this feature.

## Lifecycle

- UI: Network & Guest Tools > Load profile, edit mode/interface, Save profile, restart guest.
- Provisioning writes the selected profile before creating a VZ configuration.
- Both VM install and existing-VM boot validate settings and call `VZVirtualMachineConfiguration.validate()`; unsupported bridge mode returns a framework error (fail closed).
- Changes do not live-edit the running network stack. Do not alter a running VM's settings file externally.
- LAN exposure: Bridged networking would place a guest on the host's LAN, so it stays disabled until entitlement, signing, and live network qualification pass. NAT is outbound-focused and should not be confused with a port-forwarding service.

## Future work

- Explicitly-managed inbound port forwarding, firewall profile, per-VM network counters, multiple interfaces, MAC collision detection, DHCP snapshots, connection health probes, and vmnet private/host-only adapters.
- Native Xcode build / signed bridged entitlement / real guest DHCP and network stability must be validated.

API references:
- https://developer.apple.com/documentation/virtualization/vzbridgednetworkdeviceattachment
- https://developer.apple.com/documentation/virtualization/vznatnetworkdeviceattachment
- https://developer.apple.com/documentation/virtualization/vzmacaddress

## v0.16.0 Network and integration diagnostics

`volumeboot-host <VM> diagnose` and the Guest Tools panel report selected network mode, guest heartbeat freshness, and authenticated ping/status response counts. These are integration/transport indicators. They do not prove the guest has DHCP, a working DNS resolver, or internet/LAN reachability. The Guest Tools protocol uses VirtioFS and works when the guest virtual NIC is disconnected. NAT remains available for evaluation; bridged networking is disabled.
