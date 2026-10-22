const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;
app.use(express.json());
const swaggerUi = require("swagger-ui-express");
const fs = require("fs");
const path = require("path");
const yaml = require("yaml");

const openApiDocument = yaml.parse(
  fs.readFileSync(path.join(__dirname, "../openapi.yaml"), "utf8"),
);
// Health Check Endpoint
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    message: "TaskFlow API is running",
    timestamp: new Date().toISOString(),
  });
});
// Swagger UI setup
app.use("/api-docs", swaggerUi.serve, swaggerUi.setup(openApiDocument));
// Task Routes
app.use("/api/tasks", require("./routes/task.routes"));
app.use((error, req, res, next) => {
  console.error(error);
  res.status(500).json({ error: "Internal server error" });
});
if (require.main === module) {
  app.listen(PORT, () => console.log(`TaskFlow API running on port ${PORT}`));
}

module.exports = app;
