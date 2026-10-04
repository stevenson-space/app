# Stevenson Space Privacy Policy

Last updated: October 4, 2026

## About this policy

This policy describes how the Stevenson Space iOS app and its widgets handle
information. “We” and “us” refer to the app’s developer. The app provides school
schedules, lunch menus, reminders, and an optional student ID display. You can
use schedules and lunch menus without importing an ID or creating an account.

## Information used by the app

The app uses information you choose to provide to deliver its features:

- **Student ID:** the selected screenshot, extracted name, student number,
  barcode information, grade, school year, cropped photo, and import date.
- **Schedule:** class names, room numbers, period assignments, lunch and advisory
  assignments, free periods, and day-specific schedule changes you enter.
- **Preferences:** appearance, time format, reminder settings, and whether to hide
  your ID photo.
- **Downloaded content:** school schedule and lunch menu data, with locally
  cached copies and update information so the app can work between downloads.

Your ID, schedule customizations, and preferences are stored on your device and
are not uploaded to us. The app does not require Infinite Campus credentials or
sign in to your school account. It does not include advertising or third-party
analytics or tracking SDKs, sell your personal information, or use your ID for
advertising or AI model training.

## Student ID

Your ID is processed on this device and isn’t uploaded to us. When you import a
screenshot, Stevenson Space reads the barcode and student details and crops the
ID photo on your device. The app saves the extracted details and cropped photo,
not a copy of the original screenshot. Any original screenshot in your photo
library remains under your control and is subject to your Photos and iCloud
settings.

The extracted ID details are stored in the device’s Keychain with device-only
protection. The cropped photo is stored in the app’s local storage with iOS file
protection.

Importing an ID is optional. The app uses Apple’s photo picker to access the
image you select; it does not request unrestricted access to your photo library.
If the selected image is stored in iCloud Photos, Apple may download it to your
device to make it available for import. The app processes the image to create a
card you can review before saving. It does not send the image to a remote OCR or
AI service or use the photo to identify you through facial recognition.

Showing your card or barcode to someone, including a school scanner, lets them
read the displayed information. How the school or another recipient uses that
information is governed by their own practices.

## Widgets, Siri, Shortcuts, and notifications

The app makes saved schedule information and cached lunch menus available to its
widgets through storage shared locally with the app. Widgets can display class
names, rooms, and times on your Home Screen or Lock Screen. Student ID details
and photos are not provided to the widgets.

When you use the app’s Siri or Shortcuts actions, the app provides the requested
schedule information, including saved class names, rooms, and times, to those
Apple features. A shortcut you create can pass its results to other actions or
apps. Apple’s handling of Siri requests depends on your Apple settings and
[Apple’s privacy policy](https://www.apple.com/legal/privacy/).

Reminders are scheduled locally on your device with your notification
permission. They do not require an app-operated push notification server. You
can change reminder options in the app and revoke notification permission in iOS
Settings. Notification previews and widgets may be visible to others using or
looking at your device; you control their placement and visibility through iOS.

## Device backups

The saved ID photo may be included in Apple device backups, including iCloud
Backup or backups made to a Mac or PC, depending on your backup settings. Local
storage and iOS file protection do not exclude the photo from backups. These
backups are separate from Stevenson Space; the app does not upload your ID to us,
and we do not receive or have access to your device backups.

The extracted ID details use device-only Keychain protection. These items can
be restored from a backup to the same device, but do not migrate when a backup
is restored to a different device. “Device-only” does not mean excluded from
all backups.

You control backups through Apple’s device and backup settings. See
[Apple’s guide to managing iCloud storage](https://support.apple.com/en-us/108922)
for instructions on choosing which apps to back up and managing existing backups.
Removing your ID in the app removes its saved details and photo from the app’s
local storage; it does not directly delete copies in existing backups or your
original screenshot in Photos.

Older app versions stored extracted ID details in app preferences before moving
them to device-only Keychain storage. Backups made with those versions may still
contain those older copies. Updating the app does not rewrite existing backups.

## Network requests and other services

Your schedule customizations and app preferences are stored locally and may be
included in device backups. The app downloads school schedule and lunch menu
updates from GitHub. These requests do not include your student ID or photo;
GitHub receives the connection information needed to serve the requests, such as
your IP address, under [GitHub’s privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

The app uses HTTPS for these downloads. GitHub controls retention and deletion
of its service logs; we do not set their retention period. We do not send GitHub
your saved class names, room numbers, or other schedule customizations.

Apple separately operates the App Store, device backups, iCloud Photos, and Siri.
Apple may also provide developers with app usage statistics or diagnostic
reports through its platform services, depending on your settings. These
services are governed by Apple’s privacy policy and controls. The app does not
include a separate analytics or crash-reporting service.

If you install a beta through TestFlight, Apple automatically collects crash
logs and usage information, such as session and crash counts, install date, and
installed version, and shares them with us. You cannot opt out of this
collection. If you were invited by email, we can also see your name and email
address; if you joined through a public link, we cannot. Feedback and
screenshots you submit through TestFlight are also shared with us. We use this
information only to troubleshoot and improve the app and do not share it with
third parties. Apple retains feedback for one year and may retain crash and
usage data until the related bugs are resolved. See
[Apple’s TestFlight privacy information](https://www.apple.com/legal/privacy/data/en/test-flight/).

## Retention, deletion, and your choices

Saved ID information stays on your device until you replace or remove it. Saved
schedule customizations and preferences remain until you change or remove them;
they do not have an automatic expiration period. Downloaded school content is
cached and replaced as updates become available.

- **Remove an ID:** open the ID tab, open **ID options**, and choose **Remove ID**.
  This removes the saved ID details and cropped photo from the app. If the app
  reports that removal failed, unlock the device and try again.
- **Correct an ID:** choose **Replace Screenshot**, review the new card, and
  save it. ID details are read from the screenshot rather than edited manually.
- **Hide the photo:** **Hide ID Photo** changes its visibility; it does not delete
  the saved photo or exclude it from backups.
- **Change your schedule:** edit class details and assignments under
  **Settings → My Schedule**, and remove day overrides in Settings.
- **Stop optional features:** turn reminders off, remove widgets, or stop using
  Siri and Shortcuts actions. Removing an ID does not disable schedule features.
- **Remove the app:** remove your ID first. Deleting an app should not be relied
  on to clear its Keychain entries. Offloading the app preserves its documents
  and data for a later installation.

We cannot remotely read, edit, or delete the ID or schedule information stored
on your device. There is no Stevenson Space account to delete. Existing device
backups, your original screenshot, and information you have shared with other
people or through shortcuts must be managed separately. Removing the app does
not directly erase those copies.

## Security

The app uses iOS Keychain protection for extracted ID details and iOS file
protection for the saved photo. These protections restrict access while the
device is locked, but do not guarantee that information can never be accessed or
copied. Protect your device with a passcode and manage who can see your ID,
widgets, notifications, and backups.

## Students and minors

The app is designed for high school students. The same on-device ID processing
and optional-feature choices apply to younger users. Parents or guardians can
help students manage their saved information, permissions, and device backups.
Please do not send a student ID screenshot, barcode, or other sensitive student
information when asking for support.

## Contact and privacy requests

Contact the Stevenson Space developer at
[privacy@stevenson.space](mailto:privacy@stevenson.space) with privacy questions
or requests concerning information you have sent to us. If you email us, we
receive your email address and the contents of your message. We use that
information to respond and handle your request; our email service processes it
to deliver and store the correspondence.

We retain correspondence for as long as needed to resolve the request and any
related follow-up, or to meet applicable legal obligations. You can request
deletion of correspondence at the same address. This contact route does not
give us access to your device: use the controls described above to remove
information stored only in the app, and Apple’s controls to manage backups.

## Changes to this policy

We will update this policy when the app’s information-handling practices change
and revise the date above. If a new feature needs additional permission, the app
will request it before accessing the information covered by that permission.
