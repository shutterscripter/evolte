const express = require("express");
const HealthController = require("../../controllers/health/health.controller");

const router = express.Router();
router.get("/health", HealthController.healthCheck);

module.exports = router;
