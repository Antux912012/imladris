<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Security Policy and Vulnerability Management

This document defines the security reporting and patch disclosure process for the Imladris application. This policy complies with **Regulation (EU) 2024/2847 (EU Cyber Resilience Act)** requirements.

---

## 1. Supported Software Versions

We provide security updates for the current minor release branch:

| Version Branch | Supported | Security Patch Delivery Channel |
| :--- | :--- | :--- |
| `0.17.x` | **Yes** | GitHub Releases, Flatpak, Debian, Fedora RPM, AUR |
| `< 0.17.0` | No | Upgrade to the latest stable release |

---

## 2. Reporting a Vulnerability

If you find a security vulnerability, do not open a public issue. Report security defects through private channels:

1. **GitHub Security Advisory (Preferred)**:
   Navigate to the repository security page:  
   `https://github.com/Antux912012/imladris/security/advisories/new`
2. **Encrypted Security Email**:
   Send an encrypted report to:  
   `antux912012@users.noreply.github.com`  
   Use the subject line: `[SECURITY] Vulnerability Report: Imladris`.

### Report Requirements:
Include these details in your report:
* The affected component or file (for example, `McpServer.vala` or `SandboxController.vala`).
* Step-by-step reproduction instructions or a minimal proof-of-concept document.
* The attack vector and potential security impact (for example, remote code execution or sandbox escape).
* Any proposed remediation or patch.

---

## 3. Vulnerability Response Timeline

Our security team follows this response timeline:

1. **Initial Acknowledgment**: Within **48 hours** of report receipt.
2. **Triage and Assessment**: Within **5 business days** of acknowledgment.
3. **Remediation and Release**: Fixes are prioritized based on CVSS 3.1 severity scores. High and critical severity issues receive patched releases within **14 business days**.
4. **Coordinated Public Disclosure**: Public advisories are published simultaneously with the patch release.

---

## 4. Security Architecture and Sandbox Model

Imladris enforces security boundaries through these controls:

* **Strict Sandboxing**: The Flatpak deployment operates under `org.gnome.Platform//51` with least-privilege permissions.
* **No Unsanitized Shell Invocations**: Process execution uses `GLib.SubprocessLauncher` with explicit argument vectors. The application does not pass unsanitized input to shell interpreters (`sh -c`).
* **Path Traversal Protection**: Workspace file operations validate relative paths and reject `..` path segments.
* **Local-First AI Execution**: Elrond Assistance runs offline on loopback (`127.0.0.1:8088`). The engine transmits no prompt text, document content, or telemetry to external servers.
* **Secret Storage**: Cloud AI API keys reside in local user configuration files restricted to POSIX permissions `0600`.
