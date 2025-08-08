import 'dart:async';
import 'package:evolt_controller/app/devices/controls/controls_screen.dart';
import 'package:evolt_controller/app/favourites/favourite_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _hasError = false;
  String _errorMessage = '';
  List<ScanResult> _scanResults = [];
  BluetoothCharacteristic? _selectedCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _scanningStateSubscription;
  final FavouriteController _favouriteController = Get.put(FavouriteController());

  @override
  void initState() {
    super.initState();
    _initializeScanning();
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _scanningStateSubscription?.cancel();
    _scanResults.clear();
    super.dispose();
  }

  Future<void> _initializeScanning() async {
    try {
      // Check if Bluetooth is available
      if (!await FlutterBluePlus.isSupported) {
        _setError('Bluetooth is not supported on this device');
        return;
      }

      // Check if Bluetooth is on
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        _setError('Please enable Bluetooth to scan for devices');
        return;
      }

      await _startScanning();
    } catch (e) {
      _setError('Failed to initialize Bluetooth scanning: ${e.toString()}');
    }
  }

  Future<void> _startScanning() async {
    _clearError();
    _scanResults.clear();

    // Listen to scan results
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        if (mounted) {
          setState(() => _scanResults = results);
        }
      },
      onError: (e) {
        if (kDebugMode) {
          debugPrint('Error in scan results subscription: $e');
        }
        _setError('Failed to receive scan results');
      },
    );

    // Listen to scanning state
    _scanningStateSubscription = FlutterBluePlus.isScanning.listen(
      (state) {
        if (mounted) {
          setState(() => _isScanning = state);
        }
      },
      onError: (e) {
        if (kDebugMode) {
          debugPrint('Error in scanning state subscription: $e');
        }
      },
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      _setError('Failed to start scanning: ${e.toString()}');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device, int deviceIndex) async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);
    _clearError();

    try {
      // Connect to device
      await device.connect(timeout: const Duration(seconds: 10));

      // Discover services and find characteristic
      await _discoverServices(device, deviceIndex);
    } catch (e) {
      _setError('Failed to connect: ${e.toString()}');
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _discoverServices(
    BluetoothDevice device,
    int deviceIndex,
  ) async {
    try {
      List<BluetoothService> services = await device.discoverServices();

      BluetoothCharacteristic? writeCharacteristic;
      BluetoothCharacteristic? readCharacteristic;

      // Look for the ESP32 service (0x180) and characteristics
      for (BluetoothService service in services) {
        debugPrint('Found service: ${service.uuid}');

        // Check if this is our target service (0x180)
        String serviceUuid = service.uuid.toString().toLowerCase();
        if (serviceUuid.contains('0180') || serviceUuid.contains('180')) {
          debugPrint('Found target service: ${service.uuid}');

          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            debugPrint('Found characteristic: ${characteristic.uuid}');

            String characteristicUuid = characteristic.uuid
                .toString()
                .toLowerCase();

            // Look for the write characteristic (0xDEAD)
            if (characteristicUuid.contains('dead')) {
              writeCharacteristic = characteristic;
              debugPrint('Found write characteristic: ${characteristic.uuid}');
            }

            // Look for the read characteristic (0xFEF4)
            if (characteristicUuid.contains('fef4')) {
              readCharacteristic = characteristic;
              debugPrint('Found read characteristic: ${characteristic.uuid}');
            }
          }
        }
      }

      // Use the write characteristic as primary (for backward compatibility)
      _selectedCharacteristic = writeCharacteristic ?? readCharacteristic;

      if (_selectedCharacteristic == null) {
        // If not found, try to find any writable characteristic
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse) {
              _selectedCharacteristic = characteristic;
              debugPrint(
                'Using fallback characteristic: ${characteristic.uuid}',
              );
              break;
            }
          }
          if (_selectedCharacteristic != null) break;
        }
      }

      if (_selectedCharacteristic == null) {
        throw Exception('No writable characteristic found');
      }

      setState(() => _isConnecting = false);

      // Navigate to controls screen with both characteristics
      if (mounted) {
        Get.to(
          ControlsScreen(
            dhtCharacteristic: _selectedCharacteristic!,
            readCharacteristic: readCharacteristic,
          ),
        );
      }
    } catch (e) {
      _setError('Failed to discover services: ${e.toString()}');
      setState(() => _isConnecting = false);
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = message;
      });
    }
  }

  void _clearError() {
    if (mounted) {
      setState(() {
        _hasError = false;
        _errorMessage = '';
      });
    }
  }

  Future<void> _retryScanning() async {
    await _startScanning();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Available Devices',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.sp),
        ),
        elevation: 0
      ),
      body: RefreshIndicator(
        onRefresh: _retryScanning,
        color: Theme.of(context).primaryColor,
        child: Stack(
          children: [
            Column(
              children: [
                // Error banner
                if (_hasError) _buildErrorBanner(),

                // Device list
                Expanded(child: _buildDeviceList()),
              ],
            ),
            _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      margin: EdgeInsets.all(16.dg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 20.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    // Filter devices to show only those with "evolte" in their name
    final filteredResults = _scanResults.where((result) {
      final deviceName = result.device.platformName.toLowerCase();
      return deviceName.contains('evolte') || deviceName.contains('evolte_01');
    }).toList();

    if (filteredResults.isEmpty && !_isScanning) {
      return _buildEmptyState();
    }

    if (filteredResults.isEmpty && _isScanning) {
      return _buildScanningState();
    }

    return Column(
      children: [
        // Show count of found Evolte devices
        if (filteredResults.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16.h),
              itemCount: filteredResults.length,
              itemBuilder: (context, index) {
                return _buildDeviceTile(filteredResults[index], index);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 60.dg, color: Colors.grey[400]),
          SizedBox(height: 16.h),
          Text(
            'No Evolte devices found',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Make sure your Evolte device is nearby and discoverable',
            style: TextStyle(fontSize: 14.sp, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 22.h),
          ElevatedButton.icon(
            onPressed: _retryScanning,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.green),
          SizedBox(height: 16.h),
          Text(
            'Scanning for Evolte devices...',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          // SizedBox(height: 8.h),
          // Text(
          //   'Please wait while we search for nearby devices',
          //   style: TextStyle(fontSize: 14.sp, color: Colors.grey[500]),
          //   textAlign: TextAlign.center,
          // ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(ScanResult result, int index) {
    final device = result.device;
    final platformName = device.platformName;
    final isConnectable = platformName.isNotEmpty;
    final rssi = result.rssi;

    return Container(
      margin: EdgeInsets.only(top: 8.h),

      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12.r)),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        tileColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        leading: Container(
          padding: EdgeInsets.all(8.dg),
          decoration: BoxDecoration(
            color: isConnectable
                ? Theme.of(
                    context,
                  ).primaryColor.withValues(alpha: 0.5)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(Icons.ev_station_outlined, size: 20.sp),
        ),
        title: Text(
          isConnectable ? platformName : 'Unknown Device',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16.sp),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (device.remoteId.toString().isNotEmpty) ...[
              Text(
                '${device.remoteId}',
                style: TextStyle(color: Colors.grey[500], fontSize: 8.sp),
              ),
            ],

            Row(
              children: [
                Icon(
                  Icons.signal_cellular_alt,
                  size: 16.sp,
                  color: _getRssiColor(rssi),
                ),
                SizedBox(width: 4.w),
                Text(
                  '$rssi dBm',
                  style: TextStyle(
                    color: _getRssiColor(rssi),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Obx(() {
                  final isFav = _favouriteController.isFavorite(device.remoteId.str);
                  return IconButton(
                    onPressed: () {
                      _favouriteController.toggleFavorite(device.remoteId.str);
                    },
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.redAccent : Colors.grey,
                      size: 20.sp,
                    ),
                    tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                  );
                }),

              ],
            ),
          ],
        ),
        trailing: SizedBox(
          width: 90.w,
          child: ElevatedButton(
            onPressed: isConnectable && !_isConnecting
                ? () => _connectToDevice(device, index)
                : null,
            style: ElevatedButton.styleFrom(
              elevation: 1,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: Text(
              isConnectable ? 'Connect' : 'Unavailable',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -35) return Colors.green;
    if (rssi >= -45) return Colors.lightGreen;
    if (rssi >= -55) return Colors.lime;
    if (rssi >= -65) return Colors.amber;
    if (rssi >= -75) return Colors.orange;
    if (rssi >= -85) return Colors.deepOrange;
    return Colors.red;
  }

  // Loading overlay
  Widget _buildLoadingOverlay() {
    if (!_isConnecting) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: EdgeInsets.all(20.dg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10.h),
            Text(
              'Connecting...',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
