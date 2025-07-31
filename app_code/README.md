# EV Charger Controller

A Flutter app for controlling ESP32-based relay systems via Bluetooth Low Energy (BLE) with enhanced device management and dynamic connectivity.

## Features

- **Smart Device Discovery**: Automatically identifies and prioritizes EV charger devices
- **Dynamic Device Support**: Works with any ESP32 device using the same service UUID pattern
- **Enhanced BLE Communication**: Improved connection management with ACK handling
- **Real-time Status Monitoring**: Live command feedback and response history
- **Signal Strength Monitoring**: RSSI-based device sorting for better connection quality
- **Robust Error Handling**: Comprehensive error handling and reconnection capabilities

## ESP32 Setup

### Hardware Requirements

- ESP32 development board
- Relay module (for actual switching)
- Power supply

### Software Setup

1. Flash the provided `esp32_ble_code.c` to your ESP32
2. The ESP32 will advertise as "EV_Charger_01" (or any name containing "EV_Charger")
3. It creates a BLE service with UUID `0x00FF` and characteristic `0xFF01`

### ESP32 Commands

The ESP32 responds to these commands:

- `TURN ON` - Activates the relay
- `TURN OFF` - Deactivates the relay
- `STATUS` - Returns current relay state

### Expected Responses

- `"Data received"` - ACK for successful command execution
- Device sends notifications for all write operations

## Flutter App Setup

### Prerequisites

- Flutter SDK
- Android/iOS device with Bluetooth support
- Bluetooth permissions enabled

### Installation

1. Clone this repository
2. Run `flutter pub get` to install dependencies
3. Connect your device and run `flutter run`

### Permissions

The app requires Bluetooth permissions:

- `BLUETOOTH` - For scanning and connecting
- `BLUETOOTH_ADMIN` - For managing connections
- `ACCESS_FINE_LOCATION` - Required for BLE scanning on Android

## Usage

1. **Scan for Devices**: Open the app and tap the refresh button to scan
2. **Device Selection**: EV charger devices are highlighted and prioritized
3. **Connect**: Select your ESP32 device from the list
4. **Control**: Use the TURN ON/OFF buttons to control the relay
5. **Monitor**: View real-time responses and command status in the interface

## Enhanced Features

### Smart Device Detection

The app automatically identifies EV charger devices using these patterns:

- `EV_Charger`
- `EV_Controller`
- `EV_Relay`
- `Charger_`
- `Controller_`

### Connection Management

- **Automatic Reconnection**: Tap the refresh button in the app bar to reconnect
- **Connection Status**: Real-time connection status with detailed feedback
- **Command Feedback**: Visual indicators for successful/failed commands
- **ACK Handling**: Automatic acknowledgment verification for reliable communication

### Signal Quality

- **RSSI Monitoring**: Signal strength indicators for each device
- **Smart Sorting**: Devices sorted by signal strength for optimal connection
- **Quality Indicators**: Color-coded signal quality (Excellent/Good/Fair/Poor)

## BLE Communication

### Service UUID: `0x00FF`

### Characteristic UUID: `0xFF01`

### Properties: Read, Write, Notify

The ESP32 sends notifications back to confirm command execution and provide status updates.

## Troubleshooting

### Connection Issues

- Ensure Bluetooth is enabled on your device
- Check that the ESP32 is powered and advertising
- Verify the device name contains one of the EV charger patterns
- Use the refresh button to reconnect if needed

### Command Issues

- Check the response history for error messages
- Ensure the ESP32 code is properly flashed
- Verify the characteristic UUID matches (0xFF01)
- Look for ACK status in the command feedback section

### Permission Issues

- Grant all required Bluetooth permissions
- On Android, ensure location permission is granted (required for BLE scanning)

## Development

### Key Files

- `lib/ble/ble_manager.dart` - Enhanced BLE communication logic with ACK handling
- `lib/ble/ble_constants.dart` - BLE UUIDs, commands, and device patterns
- `lib/pages/controls/controls_screen.dart` - Improved control interface with status feedback
- `lib/pages/home/home_screen.dart` - Smart device discovery and filtering
- `lib/widgets/device_tile.dart` - Enhanced device display with signal quality
- `esp32_ble_code.c` - ESP32 BLE server implementation

### Adding New Commands

1. Add command constant in `ble_constants.dart`
2. Add button in `controls_screen.dart`
3. Handle command in ESP32 `handle_relay_command()` function
4. Update expected responses in `ble_constants.dart`

### Dynamic Device Support

The app is designed to work with any ESP32 device using the same service/characteristic UUID pattern. Simply update the device name patterns in `ble_constants.dart` to support new device types.

## License

This project is licensed under the MIT License.
