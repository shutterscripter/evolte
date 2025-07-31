import 'dart:convert';
import 'package:evolt_controller/widgets/snackbars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ControlsScreen extends StatefulWidget {
  final BluetoothCharacteristic dhtCharacteristic;

  const ControlsScreen({super.key, required this.dhtCharacteristic});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  late BluetoothCharacteristic _dhtCharacteristic;
  bool _isConnected = false;
  bool _isSending = false;
  String _lastReceivedData = '';

  @override
  void initState() {
    super.initState();
    _dhtCharacteristic = widget.dhtCharacteristic;
    _checkConnection();
    //_listenToDevice();
  }

  @override
  void dispose() {
    // Don't disconnect here as user might want to go back to scan
    super.dispose();
  }

  void _checkConnection() {
    setState(() {
      _isConnected = _dhtCharacteristic.device.isConnected;
      // WidgetsBinding.instance.addPostFrameCallback((_) {
      //   Snackbars.showInfo(
      //     _isConnected ? 'Device is connected' : 'Device is disconnected',
      //   );
      // });
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
            });
            Fluttertoast.showToast(
              msg: 'Received: $_lastReceivedData',
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
          }
        },
        onError: (error) {
          if (mounted) {
            Fluttertoast.showToast(
              msg: 'Error receiving data: $error',
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
          }
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

      Snackbars.showInfo('Charger ${command.substring(6)}');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Device Controls',
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _isConnected ? Colors.green: Colors.red,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.dg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device Info
            _buildDeviceInfo(),
            const SizedBox(height: 10),

            // Light Controls
            _buildLedControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildLedControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EV Charger Controls',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected && !_isSending
                        ? () => _sendLedCommand('1')
                        : null,
                    icon:  Icon(Icons.ev_station),
                    label: const Text('Turn ON'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding:  EdgeInsets.symmetric(vertical: 10.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                  ),
                ),
                 SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected && !_isSending
                        ? () => _sendLedCommand('0')
                        : null,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('LIGHT OFF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding:  EdgeInsets.symmetric(vertical: 10.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Device Name',
              _dhtCharacteristic.device.platformName,
            ),
            // _buildInfoRow(
            //   'Device ID',
            //   _dhtCharacteristic.device.remoteId.toString(),
            // ),
            // _buildInfoRow(
            //   'Characteristic UUID',
            //   _dhtCharacteristic.uuid.toString(),
            // ),
            // _buildInfoRow(
            //   'Service UUID',
            //   _dhtCharacteristic.serviceUuid.toString(),
            // ),
            _buildInfoRow(
              'Connection Status',
              _isConnected ? 'Connected' : 'Disconnected',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
