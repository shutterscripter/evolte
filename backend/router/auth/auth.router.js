const express = require("express");
const authController = require("../../controllers/auth/auth.controller");
const upload = require("../../utils/multer/upload_image"); // Use disk storage for images
const router = express.Router();

router.post("/login", authController.login);
router.post("/verify-otp", authController.verifyOTP);
router.post(
  "/upload-profile-picture",
  upload.single("profilePicture"),
  authController.uploadProfilePicture
);
router.post("/profile", authController.getUserInfo);

module.exports = router;
