import 'dart:convert';
import 'package:evolt_controller/widgets/snackbars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'dart:async';

class ControlsScreen extends StatefulWidget {
  final BluetoothCharacteristic dhtCharacteristic;
  final BluetoothCharacteristic? readCharacteristic;

  const ControlsScreen({
    super.key,
    required this.dhtCharacteristic,
    this.readCharacteristic,
  });

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  late BluetoothCharacteristic _dhtCharacteristic;
  bool _isConnected = false;
  bool _isSending = false;
  String _lastReceivedData = '';
  bool _isGpioOn = false;
  Timer? _statusTimer;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _dhtCharacteristic = widget.dhtCharacteristic;
    _checkConnection();
    _listenToDevice();
    _startStatusPolling();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _checkConnection() {
    setState(() {
      _isConnected = _dhtCharacteristic.device.isConnected;
    });
  }

  void _listenToDevice() async {
    try {
      await _dhtCharacteristic.setNotifyValue(true);
      _dhtCharacteristic.lastValueStream.listen(
        (value) {
          if (mounted) {
            setState(() {
              _lastReceivedData = utf8.decode(value);
              _parseGpioStatus(_lastReceivedData);

            });
          }
        },
        onError: (error) {
          if (mounted) {}
        },
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to listen to device: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  void _parseGpioStatus(String data) {
    if (data.startsWith('GPIO_13:')) {
      String status = data.substring(
        8,
      ); // Remove "GPIO_13:" prefix (8 characters)
      setState(() {
        _isGpioOn = status == '1';
        isLoading = false;
      });
    } else {
      debugPrint('⚠️ Unknown data format: $data');
    }
  }

  void _startStatusPolling() {
    _statusTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_isConnected && mounted) {
        _readGpioStatus();
      }
    });
  }

  Future<void> _readGpioStatus() async {
    try {

      // Use read characteristic if available, otherwise use write characteristic
      BluetoothCharacteristic characteristicToRead =
          widget.readCharacteristic ?? _dhtCharacteristic;

      List<int> value = await characteristicToRead.read();
      String data = utf8.decode(value);
      _parseGpioStatus(data);
    } catch (e) {
      debugPrint('❌ Error reading GPIO status: $e');
    }
  }

  Future<void> _sendCommand(String command) async {
    if (!_isConnected) {
      Snackbars.showError('Device not connected');
      return;
    }

    setState(() => _isSending = true);

    try {
      // Send simple string command as ESP32 expects
      await _dhtCharacteristic.write(utf8.encode(command));

      setState(() {
        _isSending = false;
      });

      // Read updated status after sending command
      await Future.delayed(Duration(milliseconds: 500));
      _readGpioStatus();
    } catch (e) {
      setState(() => _isSending = false);
      Snackbars.showError('Failed to send command, Try again!');
    }
  }

  Future<void> _sendLedCommand(String status) async {
    if (status == '1') {
      await _sendCommand('LIGHT ON');
    } else {
      await _sendCommand('LIGHT OFF');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          _dhtCharacteristic.device.platformName,
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: theme.colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16.w),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: _isConnected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8.w,
                  height: 8.h,
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _isConnected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Power Control',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 10.h),
                  _buildControlButton(
                    theme,
                    icon: Icons.power,
                    label: _isGpioOn ? 'Turn OFF' : 'Turn ON',
                    isOn: _isGpioOn,
                    onPressed: _isConnected && !_isSending
                        ? () => _isGpioOn
                              ? _sendLedCommand('0')
                              : _sendLedCommand('1')
                        : null,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildControlButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool isOn,
    required VoidCallback? onPressed,
  }) {
    return Container(
      height: 80.h,
      width: Get.width / 2,
      decoration: BoxDecoration(
        color: onPressed != null
            ? (!isOn
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : Colors.red.withValues(alpha: 0.2))
            : theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            padding: EdgeInsets.all(16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: onPressed != null
                      ? (!isOn ? Theme.of(context).primaryColor : Colors.red)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 24.sp,
                ),
                SizedBox(width: 6.h),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: onPressed != null
                        ? (!isOn ? Theme.of(context).primaryColor : Colors.red)
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
