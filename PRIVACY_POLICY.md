# Privacy Policy

**SnipKey**
**Effective Date:** August 28, 2026
**Last Updated:** August 28, 2026

## Overview

SnipKey ("the App") is developed by Jonathan Taveras Vargas. This Privacy Policy explains how the App handles your information. Your privacy is important to us, and we are committed to being transparent about our practices.

**In short: SnipKey does not collect, log, transmit, or share any personal data — and the keyboard never records your keystrokes. The only place your snippets live outside your device is your own personal iCloud, which only you can access with your Apple account.**

## Information We Collect

**None.** SnipKey does not collect any personal information, usage data, analytics, crash reports, or telemetry of any kind. There are no analytics, crash-reporting, or advertising SDKs in the App.

## The Keyboard and Your Keystrokes

SnipKey includes a custom keyboard extension. We want to be unambiguous about what it does and does not do:

- The keyboard does **not** log, store, or transmit anything you type. Keystrokes are processed entirely in memory, on your device, only to render the keyboard and insert text into the app you are using.
- Typing features such as auto-capitalization, smart punctuation, touch-accuracy correction, and `/` command suggestions run **completely on-device** using built-in, offline data. Nothing you type is ever sent anywhere.
- Enabling **Allow Full Access** is only used for clipboard operations (copying image and PDF snippets to the pasteboard) and for reading your snippets from the shared local database. Even with Full Access enabled, the keyboard makes **no network requests** and transmits nothing.

## Data Storage and iCloud

Your snippets, tags, and settings are stored:

1. **Locally on your device**, using Apple's SwiftData framework in a shared container so the App and the keyboard extension can both access them.
2. **In your personal iCloud**, via Apple's CloudKit **private database**, so your snippets sync across your own devices. This data is tied to your Apple account: it is encrypted in transit and at rest by Apple, it is accessible **only to you** through your Apple account, and the developer has **no access** to it. Apple's handling of this data is governed by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

iCloud sync is Apple infrastructure — there are no developer-operated servers, and no copy of your data exists anywhere the developer can reach.

## Network Communication

The App makes **no network requests of its own**, with two narrow exceptions:

- **iCloud (CloudKit)** — Apple's infrastructure, used solely to sync your snippets to your personal iCloud as described above.
- **RevenueCat (optional tips only)** — if you choose to leave a tip in the tip jar, the purchase is processed by Apple, and RevenueCat receives the standard App Store purchase receipt to validate it. No snippet content, typing data, or personal information is ever shared with RevenueCat. If you never open the tip jar, no communication occurs.

The keyboard extension itself makes **zero** network requests in all cases.

## On-Device Features

- **Biometric lock (Face ID / Touch ID)** — handled entirely by Apple's LocalAuthentication framework on your device. Authentication results are never stored or transmitted.
- **Reminders and timers** — reminders you create from the keyboard are scheduled as local notifications on your device, or written directly to the native Apple Reminders app if you enable that integration. Nothing leaves your device.

## Third-Party Services

There are no:

- Analytics or crash-reporting SDKs
- Advertising networks
- Social media trackers
- Developer-operated servers
- Third-party data sharing of any kind

## Cookies and Tracking

SnipKey does **not** use cookies, web beacons, pixels, fingerprinting, or any other tracking technologies.

## Children's Privacy

SnipKey does not collect personal information from anyone, including children under the age of 13. The App is safe for users of all ages.

## Data Sharing and Selling

We do **not** sell, trade, rent, or otherwise share any user data with third parties. There is no user data on our end to share.

## Your Rights

Since SnipKey does not collect any personal data, there is no personal data to access, modify, or delete from our end. Your snippets belong to you: manage or delete them in the App, disable iCloud sync for SnipKey in iOS Settings, or remove the data entirely by deleting the App and its iCloud data from your account settings.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be reflected by updating the "Last Updated" date at the top of this document. We encourage you to review this Privacy Policy periodically.

## Contact

If you have any questions or concerns about this Privacy Policy, please contact us by opening an issue on our GitHub repository:

- **GitHub:** [https://github.com/jtvargas/SnipKey](https://github.com/jtvargas/SnipKey)

## Open Source

SnipKey is open source software released under the MIT License. You can review the complete source code at any time to verify every privacy claim in this document.
