const nodemailer = require("nodemailer");
const { log } = require("mercedlogger");

const { GMAIL_ID, GMAIL_PASSWORD } = process.env;

class OTPController {
  static async sendOTP(senderEmail) {
    try {
      // Generate OTP
      const otp = Math.floor(1000 + Math.random() * 9000);
      log.yellow("OTP", "Generated OTP:", otp);

      // Configure nodemailer transporter
      const transporter = nodemailer.createTransport({
        host: "mail.sunshineiot.in",
        port: 465,
        secure: true, // Use SSL
        auth: {
          user: GMAIL_ID,
          pass: GMAIL_PASSWORD,
        },
      });
      log.yellow("OTP", "Transporter created");
      const htmlContent = `
                <div style="font-family: Helvetica,Arial,sans-serif;min-width:1000px;overflow:auto;line-height:2">
                  <div style="margin:50px auto;width:70%;padding:20px 0">
                    <div style="border-bottom:1px solid #eee">
                      <a href="#" style="font-size:1.4em;color: #00466a;text-decoration:none;font-weight:600">E-Volte</a>
                    </div>
                    <p style="font-size:1.1em">Hi,</p>
                    <p>Thank you for choosing <strong>E-Volte</strong>. Use the following OTP to complete your Sign Up procedures. OTP is valid for 5 minutes.</p>
                    <h2 style="background: #00466a; margin: 0 auto; width: max-content; padding: 0 10px; color: #fff; border-radius: 4px;">${otp}</h2>
                    <p style="font-size:0.9em;">Regards,<br />E-Volte Team</p>
                    <hr style="border:none;border-top:1px solid #eee" />
                    <div style="float:right;padding:8px 0;color:#aaa;font-size:0.8em;line-height:1;font-weight:300">
                      <p>Sunshine iotronics Pvt. Ltd.</p>
                      <p>Manjari, Pune</p>
                    </div>
                  </div>
                </div>
            `;

      // Email options
      const mailOptions = {
        from: GMAIL_ID,
        to: senderEmail,
        subject: `E-Volte OTP is ${otp}`,
        html: htmlContent,
      };

      log.yellow("OTP", "Mail options created");
      // Send email
      await transporter.sendMail(mailOptions);
      log.yellow("OTP", "Mail sent successfully");
      return otp; // Return the OTP
    } catch (error) {
      console.error("Error sending OTP:", error);
      throw new Error("Failed to send OTP");
    }
  }
}

module.exports = OTPController;
