import 'package:evolt_controller/app/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              Get.offAll(() => const LoginScreen());
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      leading: Icon(icon, color: iconColor ?? Theme.of(Get.context!).primaryColor, size: 24.sp),
      title: Text(title, style: TextStyle(fontSize: 16.sp)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            _buildSettingsTile(
              icon: Icons.notifications_active_rounded,
              title: 'Notifications',
              onTap: () {
                // Navigate to notifications settings
              },
            ),
            _buildSettingsTile(
              icon: Icons.lock_rounded,
              title: 'Privacy',
              onTap: () {
                // Navigate to privacy settings
              },
            ),
            _buildSettingsTile(
              icon: Icons.info_rounded,
              title: 'About',
              onTap: () {
                // Navigate to privacy settings
              },
            ),
            const Divider(height: 32),
            _buildSettingsTile(
              icon: Icons.logout_rounded,
              title: 'Logout',
              iconColor: Colors.redAccent,
              onTap: () => _showLogoutDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}
