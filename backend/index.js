require("dotenv").config({ path: ".env.dev", quiet: true });
const express = require("express");
const path = require("path");
const fs = require("fs");

const app = express();
app.use(express.json());

const uploadsDir = path.join(__dirname, "uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir);
}
app.use("/uploads", express.static("uploads"));

const healthRouter = require("./router/health/health.router");
const authRouter = require("./router/auth/auth.router");
const port = process.env.PORT || 3000;

app.use("/api/v1", healthRouter);
app.use("/api/v1/auth", authRouter);

app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});
