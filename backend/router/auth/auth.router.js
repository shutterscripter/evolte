const express = require("express");
const authController = require("../../controllers/auth/auth.controller");
const router = express.Router();

router.post("/login", authController.login);
router.post("/verify-otp", authController.verifyOTP);

module.exports = router;
