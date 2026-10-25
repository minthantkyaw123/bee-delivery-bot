Mira Native App
===============

Build branch contains generated native client source and a local bridge, not the user's local Mira core source, model weights, or config.

Expected GitHub Actions build artifacts:
- Mira-Android-APK
- Mira-Windows-Portable
- Mira-Server-Bridge

The PC bridge expects an existing Mira installation at D:\Mira. Run Start_Mira_Server.bat on that PC and keep the window open. Use COMPUTER_URL on the PC, PHONE_URL on Android over the same trusted Wi-Fi, and MIRA_ACCESS_KEY in the app. Do not forward port 8765 to the public Internet.

Voice recognition and Myanmar TTS depend on the device's speech services. Build completion must be followed by actual device-level tests.
