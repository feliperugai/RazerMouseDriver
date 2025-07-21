# Razer DeathAdder V2 X Hyperspeed driver for macOS

## Goal

This project aims to **try to create a driver for the Razer DeathAdder V2 X Hyperspeed mouse** on macOS. It is highly experimental and intended as a learning base for HID communication with Razer devices, especially this model.

## Supported Model

- **Razer DeathAdder V2 X Hyperspeed**
  - Vendor ID: `0x1532`
  - Product ID: `0x009c`

## Status

> ⚠️ **Experimental:** This project is a work-in-progress attempt to control DPI, polling rate, and other features of the mouse directly from macOS, without Razer Synapse. **Many things are not fully functional yet!**

### What works so far

- [x] List all connected Razer devices
- [x] Select the correct device (DeathAdder V2 X Hyperspeed)
- [x] Listen to physical button changes (e.g., DPI button presses)
- [x] Show the current DPI in the UI, updating live when changed via the mouse's physical buttons
- [ ] Changing the DPI from the UI (software DPI change is not yet functional)
- [ ] Changing polling rate from the UI (not fully tested)
- [ ] RGB or macro support

## How to use

1. **Clone the repository:**

   ```sh
   git clone https://github.com/your-username/RazerMouseDriver.git
   ```

2. **Open the project in Xcode** (requires macOS 13+ and Xcode 14+).
3. **Connect your Razer DeathAdder V2 X Hyperspeed mouse** to your Mac.
4. **Build and run the app.**
5. Use the menu bar extra to view current DPI and try changing it using the mouse's physical buttons.

## Important Notes

- The driver uses permissions for USB and Bluetooth device access (see `.entitlements`).
- Some features may not work due to macOS or hardware limitations.
- For reverse engineering, consider analyzing USB traffic with tools like Wireshark or USB sniffers.
- See also the [OpenRazer](https://github.com/openrazer/openrazer) project for HID command references.

## Contributing

Pull requests and suggestions are welcome! This is an experimental project and any help to decipher the Razer HID protocol is appreciated.

## License

MIT
