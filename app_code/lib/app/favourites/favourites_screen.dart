import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:evolt_controller/app/favourites/favourite_controller.dart';
import 'package:evolt_controller/app/devices/controls/controls_screen.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  final FavouriteController _favController = Get.find();
  final RxBool _isScanning = true.obs;
  final RxSet<String> _connectingIds = <String>{}.obs;
  final Map<String, ScanResult> _foundFavDevices = {};

  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void initState() {
    super.initState();
    _startScanForFavourites();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  void _startScanForFavourites() {
    _foundFavDevices.clear();
    _isScanning.value = true;

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        if (_favController.favourites.contains(id)) {
          _foundFavDevices[id] = result;
        }
      }
      setState(() {}); // update UI with found devices
    });

    FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          androidUsesFineLocation: true,
        )
        .catchError((e) {
          _showSnackbar("Scan Error", e.toString());
        })
        .whenComplete(() {
          _isScanning.value = false;
        });
  }

  void _connectToDevice(ScanResult result) async {
    final device = result.device;
    final id = device.remoteId.str;

    if (_connectingIds.contains(id)) return;

    _connectingIds.add(id);

    try {
      await device.connect(timeout: const Duration(seconds: 10));

      final services = await device.discoverServices();

      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? readChar;

      for (var service in services) {
        for (var char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid.contains('dead')) writeChar = char;
          if (uuid.contains('fef4')) readChar = char;
        }
      }

      writeChar ??= services
          .expand((s) => s.characteristics)
          .firstWhere(
            (c) => c.properties.write || c.properties.writeWithoutResponse,
            orElse: () => throw Exception('No writable characteristic found'),
          );

      // Navigate to control screen
      Get.to(
        () => ControlsScreen(
          dhtCharacteristic: writeChar!,
          readCharacteristic: readChar,
        ),
      );
    } catch (e) {
      _showSnackbar("Connection Failed", e.toString());
    } finally {
      _connectingIds.remove(id);
    }
  }

  void _showSnackbar(String title, String message) {
    Get.snackbar(
      title,
      message,
      backgroundColor: Colors.redAccent,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Favourite Devices',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.sp),
        ),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _startScanForFavourites();
        },
        child: Obx(() {
          if (_favController.favourites.isEmpty) {
            return Center(
              child: Column(
                children: [
                  SizedBox(height: 48.h),
                  Icon(
                    Icons.favorite_border,
                    size: 48.sp,
                    color: Theme.of(context).primaryColor,
                  ),
                   SizedBox(height: 16.h),
                  Text('No favourites yet!',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }

          if (_isScanning.value && _foundFavDevices.isEmpty) {
            return CircularProgressIndicator();
          }

          if (!_isScanning.value && _foundFavDevices.isEmpty) {
            return Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 48.h),
                   Text("No favourite devices found nearby.",
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
                   ),
                   SizedBox(height: 16.h),
                  ElevatedButton.icon(
                    onPressed: _startScanForFavourites,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Rescan"),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: _foundFavDevices.entries.map((entry) {
              final id = entry.key;
              final result = entry.value;
              final name = result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : 'Unknown Device';

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8.r),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.ev_station, size: 20.sp),
                  ),
                  title: Text(name),
                  subtitle: Text(id),
                  trailing: Obx(() {
                    final isConnecting = _connectingIds.contains(id);
                    return ElevatedButton(
                      onPressed: isConnecting
                          ? null
                          : () => _connectToDevice(result),
                      child: isConnecting
                          ? SizedBox(
                              height: 20.h,
                              width: 20.w,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Connect',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  }),
                ),
              );
            }).toList(),
          );
        }),
      ),
    );
  }
}
