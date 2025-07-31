import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Snackbars {
  static void showError(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(Get.context!).colorScheme.error,
      ),
    );
  }

  static void showSuccess(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(Get.context!).colorScheme.primary,
      ),
    );
  }

  static void showInfo(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Theme.of(Get.context!).colorScheme.onPrimary)),
        backgroundColor: Theme.of(Get.context!).primaryColor,
      ),
    );
  }
}
