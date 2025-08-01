require("dotenv").config({ path: ".env.dev", quiet: true });
const express = require("express");

const app = express();
app.use(express.json());

const healthRouter = require("./router/health/health.router");
const authRouter = require("./router/auth/auth.router");
const port = process.env.PORT || 3000;

app.use("/api/v1", healthRouter);
app.use("/api/v1/auth", authRouter);

app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});
