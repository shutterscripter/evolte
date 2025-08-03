import 'dart:convert' show jsonEncode;

import 'package:evolt_controller/app/auth/otp_screen.dart';
import 'package:evolt_controller/consts/api_constants.dart';
import 'package:evolt_controller/widgets/snackbars.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class AuthController extends GetxController {
  bool isLoading = false;
  bool isEmailValid = false;
  bool isNameValid = false;

  Future<void> sendOTP(name, email) async {
    isLoading = true;
    update();
    try {
      http
          .post(
            Uri.parse(APIConstants.login),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name, 'email': email}),
          )
          .then((response) {
            print('Response status: ${response.statusCode}');
            print('Response body: ${response.body}');
            if (response.statusCode == 201) {
              isLoading = false;
              Snackbars.showSuccess('OTP sent to $email');

              Get.to(() => OtpScreen(email: email));
            } else {
              isLoading = false;
              Snackbars.showSuccess('OTP sent to $email');

              Get.to(() => OtpScreen(email: email));
            }
          })
          .catchError((error) {
            isLoading = false;

            Snackbars.showError(
              'An error occurred while sending OTP. Please try again.',
            );
          });
    } catch (e) {
      isLoading = false;
      Snackbars.showError(

        'An error occurred while sending OTP. Please try again.',
      );
    }
    update();
  }

  void validateName(String value) {
    isNameValid = value.trim().length >= 2;
    update();
  }

  void validateEmail(String value) {
    isEmailValid = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value);
    update();
  }
}
