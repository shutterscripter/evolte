import 'package:flutter/material.dart';
import 'package:evolt_controller/app/scan/ble_off/bluetooth_off_view.dart';
import 'package:evolt_controller/app/scan/scan_view.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

void main() {
  runApp(const MyApp());
}



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late BluetoothAdapterState _bluetoothAdapterState;

  @override
  void initState() {
    _bluetoothAdapterState = BluetoothAdapterState.unknown;

    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _bluetoothAdapterState = state;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Widget currentPage = _bluetoothAdapterState != BluetoothAdapterState.on
        ? const BleOffPage()
        : const ScanPage();

    return ScreenUtilInit(
      designSize: const Size(360, 690),

      child: GetMaterialApp(
        title: 'Flutter BLE App',
        home: currentPage,
        debugShowCheckedModeBanner: false,
        theme: FlexThemeData.light(
          scheme: FlexScheme.blumineBlue,
          useMaterial3: true,
          typography: Typography.material2021(platform: defaultTargetPlatform),
        ),
        darkTheme: FlexThemeData.dark(
          scheme: FlexScheme.blumineBlue,
          useMaterial3: true,
          typography: Typography.material2021(platform: defaultTargetPlatform),
        ),
      ),
    );
  }
}
