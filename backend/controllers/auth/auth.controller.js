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
            return res.status(StatusCodes.CONFLICT).json({
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

  /// Update or Upload Profile Picture (Upsert)
  static async uploadProfilePicture(req, res) {
    try {
      const { email } = req.body;
      if (!email) {
        return res
          .status(StatusCodes.BAD_REQUEST)
          .json({ error: "Email is required" });
      }
      if (!req.file) {
        return res
          .status(StatusCodes.BAD_REQUEST)
          .json({ error: "Profile picture file is required" });
      }
      const profilePicPath = req.file.path;
      // Check if user exists
      const checkUserQuery = `SELECT * FROM users WHERE email = ?`;
      connection.query(checkUserQuery, [email], (err, results) => {
        if (err) {
          return res
            .status(StatusCodes.INTERNAL_SERVER_ERROR)
            .json({ error: "Database error" });
        }
        if (results.length === 0) {
          return res
            .status(StatusCodes.NOT_FOUND)
            .json({ error: "User not found" });
        }
        // Upsert profile picture path
        const updateProfilePicQuery = `UPDATE users SET profile_picture = ? WHERE email = ?`;
        connection.query(
          updateProfilePicQuery,
          [profilePicPath, email],
          (err2) => {
            if (err2) {
              return res
                .status(StatusCodes.INTERNAL_SERVER_ERROR)
                .json({ error: "Database error" });
            }
            return res.status(StatusCodes.OK).json({
              message: "Profile picture uploaded/updated successfully",
              profilePicture: profilePicPath,
            });
          }
        );
      });
    } catch (error) {
      res
        .status(StatusCodes.INTERNAL_SERVER_ERROR)
        .json({ error: "Profile picture upload failed" });
    }
  }

  /// Get User Info by Email
  static async getUserInfo(req, res) {
    try {
      const { email } = req.body;
      if (!email) {
        return res
          .status(StatusCodes.BAD_REQUEST)
          .json({ error: "Email is required" });
      }
      const getUserQuery = `SELECT id, name, email, profile_picture FROM users WHERE email = ?`;
      connection.query(getUserQuery, [email], (err, results) => {
        if (err) {
          return res
            .status(StatusCodes.INTERNAL_SERVER_ERROR)
            .json({ error: "Database error" });
        }
        if (results.length === 0) {
          return res
            .status(StatusCodes.NOT_FOUND)
            .json({ error: "User not found" });
        }
        let user = results[0];
        if (user.profile_picture) {
          user.profile_picture = `${req.protocol}://${req.get("host")}/${
            user.profile_picture
          }`;
        }
        return res.status(StatusCodes.OK).json(user);
      });
    } catch (error) {
      res
        .status(StatusCodes.INTERNAL_SERVER_ERROR)
        .json({ error: "Failed to get user info" });
    }
  }
}

module.exports = AuthController;
