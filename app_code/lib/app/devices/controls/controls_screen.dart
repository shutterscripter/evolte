import 'dart:async';
import 'dart:convert';

import 'package:evolt_controller/widgets/snackbars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';

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
  static const int _highTemperatureThresholdC = 45;

  late BluetoothCharacteristic _writeCharacteristic;
  bool _isConnected = false;
  bool _isSending = false;
  bool _isGpioOn = false;
  bool? _pendingGpioOn;
  int? _temperatureC;
  int? _humidity;
  bool _dhtOk = false;
  bool _isLoading = true;
  String _lastReceivedData = '';
  Timer? _statusTimer;
  double _swipeProgress = 0;

  @override
  void initState() {
    super.initState();
    _writeCharacteristic = widget.dhtCharacteristic;
    _checkConnection();
    _listenToDevice();
    _startStatusPolling();
    _readDeviceStatus();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _checkConnection() {
    if (!mounted) return;
    setState(() {
      _isConnected = _writeCharacteristic.device.isConnected;
    });
  }

  void _listenToDevice() async {
    try {
      await _writeCharacteristic.setNotifyValue(true);
      _writeCharacteristic.lastValueStream.listen((value) {
        if (!mounted || value.isEmpty) return;
        _lastReceivedData = utf8.decode(value);
        _parseDeviceStatus(_lastReceivedData);
      }, onError: (_) {});
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to listen to device: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  void _parseDeviceStatus(String data) {
    final Map<String, String> values = {};
    for (final part in data.split(';')) {
      final segments = part.split(':');
      if (segments.length >= 2) {
        values[segments.first.trim()] = segments.sublist(1).join(':').trim();
      }
    }

    if (!values.containsKey('GPIO_13') || !mounted) {
      debugPrint('Unknown data format: $data');
      return;
    }

    final bool nextGpioOn = values['GPIO_13'] == '1';
    final bool commandConfirmed =
        _pendingGpioOn == null || nextGpioOn == _pendingGpioOn;

    setState(() {
      if (commandConfirmed) {
        _isGpioOn = nextGpioOn;
        _pendingGpioOn = null;
        _isSending = false;
      }
      _temperatureC = int.tryParse(values['TEMP_C'] ?? '');
      _humidity = int.tryParse(values['HUMIDITY'] ?? '');
      _dhtOk = values['DHT_OK'] == '1';
      _isLoading = false;
      _swipeProgress = (_pendingGpioOn ?? _isGpioOn) ? 1 : 0;
    });
  }

  void _startStatusPolling() {
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isConnected && mounted) {
        _readDeviceStatus();
      }
    });
  }

  Future<void> _readDeviceStatus() async {
    try {
      final BluetoothCharacteristic characteristicToRead =
          widget.readCharacteristic ?? _writeCharacteristic;
      final List<int> value = await characteristicToRead.read();
      final String data = utf8.decode(value);
      _parseDeviceStatus(data);
    } catch (e) {
      debugPrint('Error reading device status: $e');
    }
  }

  Future<void> _sendCommand(String command) async {
    if (!_isConnected) {
      Snackbars.showError('Device not connected');
      return;
    }

    final bool targetOn = command == 'LIGHT ON';
    setState(() {
      _isSending = true;
      _pendingGpioOn = targetOn;
      _swipeProgress = targetOn ? 1 : 0;
    });

    try {
      await _writeCharacteristic.write(utf8.encode(command));
      await Future.delayed(const Duration(milliseconds: 350));
      await _readDeviceStatus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _pendingGpioOn = null;
          _swipeProgress = _isGpioOn ? 1 : 0;
        });
      }
      Snackbars.showError('Failed to send command, try again');
    }
  }

  Future<void> _toggleLight() async {
    await _sendCommand(_isGpioOn ? 'LIGHT OFF' : 'LIGHT ON');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool displayedGpioOn = _pendingGpioOn ?? _isGpioOn;
    final bool isHighTemperature =
        (_temperatureC ?? 0) >= _highTemperatureThresholdC;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Get.back(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _writeCharacteristic.device.platformName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Device overview',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 20.w),
            child: _buildStatusChip(theme),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isSending) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 24.h),
                        if (isHighTemperature) ...[
                          _buildTemperatureWarning(theme),
                          SizedBox(height: 12.h),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                theme,
                                label: 'Temperature',
                                value: _temperatureC != null
                                    ? '${_temperatureC}°C'
                                    : '--',
                                icon: Icons.thermostat_rounded,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: _buildMetricCard(
                                theme,
                                label: 'Humidity',
                                value: _humidity != null ? '${_humidity}%' : '--',
                                icon: Icons.water_drop_rounded,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        _buildControlPanel(theme, displayedGpioOn),
                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTemperatureWarning(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
            size: 22.sp,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'High temperature warning',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Current temperature is ${_temperatureC}°C. Please check the device and surrounding environment.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final Color bg = _isConnected
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.errorContainer;
    final Color fg = _isConnected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onErrorContainer;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          SizedBox(width: 8.w),
          Text(
            _isConnected ? 'Connected' : 'Offline',
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildMetricCard(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 20.sp),
          SizedBox(height: 14.h),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(ThemeData theme, bool displayedGpioOn) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildSwipeControl(theme, displayedGpioOn)],
      ),
    );
  }

  Widget _buildSwipeControl(ThemeData theme, bool displayedGpioOn) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double thumbSize = 52;
        final double width = constraints.maxWidth;
        final double maxDrag = width - thumbSize - 12.w;
        final double left = 6.w + (_swipeProgress * maxDrag);
        final bool canInteract = _isConnected && !_isSending;
        final Color trackColor = displayedGpioOn
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer;
        final Color thumbColor = displayedGpioOn
            ? theme.colorScheme.error
            : theme.colorScheme.primary;

        return Container(
          height: 64.h,
          decoration: BoxDecoration(
            color: canInteract
                ? trackColor
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18.r),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Text(
                  _isSending
                      ? 'Updating...'
                      : displayedGpioOn
                      ? 'Swipe left to turn off'
                      : 'Swipe right to turn on',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: canInteract
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                left: left,
                child: GestureDetector(
                  onHorizontalDragUpdate: canInteract
                      ? (details) {
                          setState(() {
                            _swipeProgress =
                                (_swipeProgress + (details.delta.dx / maxDrag))
                                    .clamp(0.0, 1.0);
                          });
                        }
                      : null,
                  onHorizontalDragEnd: canInteract
                      ? (_) async {
                          final bool targetOn = _swipeProgress > 0.5;
                          final bool changed = targetOn != _isGpioOn;
                          setState(() {
                            _swipeProgress = targetOn ? 1 : 0;
                          });
                          if (changed) {
                            await _toggleLight();
                          }
                        }
                      : null,
                  child: Container(
                    width: thumbSize.w,
                    height: thumbSize.w,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: _isSending
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Icon(
                            displayedGpioOn
                                ? Icons.keyboard_double_arrow_left_rounded
                                : Icons.keyboard_double_arrow_right_rounded,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHealthCard(ThemeData theme) {
    final Color tone = _dhtOk
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    final String title = _dhtOk ? 'Stable' : 'Recovering';
    final String body = _dhtOk
        ? 'DHT11 is responding normally.'
        : 'Keeping the last valid reading until the next successful sample.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sensors_rounded, color: tone, size: 20.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
