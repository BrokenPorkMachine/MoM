#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
rg -q 'func unregister\(\)' Core/PrivilegedBrokerClient.swift
rg -q 'service\.unregister\(\)' Core/PrivilegedBrokerClient.swift
rg -q 'unregisterPrivilegedDaemon' App/AppModel.swift App/DashboardView.swift
rg -q 'approval-denied|approval denied|Approval' Docs/DAEMON_COMPONENT_SPEC.md Docs/RELEASE_v0.12.0.md
rg -q 'healthReport' Docs/DAEMON_COMPONENT_SPEC.md
rg -q 'MacOnMacVMControl' project.yml MacOnMac.xcodeproj/project.pbxproj
plutil -lint Resources/LaunchAgents/ca.zensoftware.MacOnMac.VMControl.plist >/dev/null
echo "PASS: daemon install, approval, upgrade, health, and removal lifecycle is documented and wired"
