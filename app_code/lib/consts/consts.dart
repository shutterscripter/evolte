const double hPadding = 18.0;
const double vPadding = 12.0;
const infoTextSize = 18.0;
const titleSize = 26.0;
const subTitleSize = 22.0;
const iconSize = 40.0;
const homeSizedHeight = 20.0;

// ESP32 BLE Service and Characteristic UUIDs
const String serviceUuid =
    "00000180-0000-1000-8000-00805f9b34fb"; // 0x180 service
const String dhtCharacteristicUuid =
    '0000dead-0000-1000-8000-00805f9b34fb'; // 0xDEAD characteristic for writing
const String readCharacteristicUuid =
    '0000fef4-0000-1000-8000-00805f9b34fb'; // 0xFEF4 characteristic for reading
const String serverName = 'eVolte_01';
