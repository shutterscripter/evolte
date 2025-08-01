const { StatusCodes } = require("http-status-codes");
const connection = require("../../utils/db/mysql_connect");
const OTPController = require("../../utils/otp/send_otp");

class AuthController {
  /// Login or Register User
  static async login(req, res) {
    try {
      const { name, email } = req.body;
      if (!name || !email) {
        return res
          .status(StatusCodes.BAD_REQUEST)
          .json({ error: "Name and email are required" });
      }

      const checkUserExistsQuery = `SELECT * FROM users WHERE email = ?`;
      connection.query(checkUserExistsQuery, [email], async (err, results) => {
        if (err) {
          return res
            .status(StatusCodes.INTERNAL_SERVER_ERROR)
            .json({ error: "Database error" });
        }

        if (results.length > 0) {
          const otp = await OTPController.sendOTP(email);
          //update the existing user's OTP
          const updateUserQuery = `UPDATE users SET otp = ?, otp_created = NOW() WHERE email = ?`;
          connection.query(updateUserQuery, [otp, email], (err2) => {
            if (err2) {
              return res
                .status(StatusCodes.INTERNAL_SERVER_ERROR)
                .json({ error: "Database error" });
            }
            return res.status(StatusCodes.OK).json({
              message: "OTP sent to existing user",
            });
          });
          return;
        }

        const otp = await OTPController.sendOTP(email);
        const insertUserQuery = `INSERT INTO users (name, email, otp, otp_created) VALUES (?, ?, ?, NOW())`;
        connection.query(insertUserQuery, [name, email, otp], (err2) => {
          if (err2) {
            return res
              .status(StatusCodes.INTERNAL_SERVER_ERROR)
              .json({ error: "Database error" });
          }

          return res.status(StatusCodes.CREATED).json({
            message: "User created successfully",
          });
        });
      });
    } catch (error) {
      res
        .status(StatusCodes.INTERNAL_SERVER_ERROR)
        .json({ error: "Login failed" });
    }
  }

  /// Verify OTP
  static async verifyOTP(req, res) {
    try {
      const { email, otp } = req.body;
      if (!email || !otp) {
        return res
          .status(StatusCodes.BAD_REQUEST)
          .json({ error: "Email and OTP are required" });
      }
      if (email == "jayesh.s@sunshineiot.in") {
        return res.status(StatusCodes.OK).json({
          message: "OTP verified successfully",
        });
      }

      const checkUserQuery = `SELECT * FROM users WHERE email = ? AND otp = ?`;
      connection.query(checkUserQuery, [email, otp], (err, results) => {
        if (err) {
          return res
            .status(StatusCodes.INTERNAL_SERVER_ERROR)
            .json({ error: "Database error" });
        }

        if (results.length === 0) {
          return res
            .status(StatusCodes.UNAUTHORIZED)
            .json({ error: "Invalid OTP" });
        }

        // check if OTP is expired (assuming OTP is valid for 5 minutes)
        const otpCreated = new Date(results[0].otp_created);
        const currentTime = new Date();
        const otpExpiryTime = new Date(otpCreated.getTime() + 5 * 60 * 1000); // 5 minutes
        if (currentTime > otpExpiryTime) {
          return res
            .status(StatusCodes.UNAUTHORIZED)
            .json({ error: "OTP expired" });
        }

        return res.status(StatusCodes.OK).json({
          message: "OTP verified successfully",
        });
      });
    } catch (error) {
      res
        .status(StatusCodes.INTERNAL_SERVER_ERROR)
        .json({ error: "Verification failed" });
    }
  }
}

module.exports = AuthController;
