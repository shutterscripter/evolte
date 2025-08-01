class HealthController {
  static async healthCheck(req, res) {
    res.status(200).json({
      message: "Humans are terrible at reading minds, but we can read code!",
    });
  }
}
module.exports = HealthController;
