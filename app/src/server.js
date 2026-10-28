const express = require("express");
const cors = require("cors");
const app = express();
const PORT = process.env.PORT || 3000;

const swaggerUi = require("swagger-ui-express");
const fs = require("fs");
const path = require("path");
const yaml = require("yaml");

const openApiDocument = yaml.parse(
  fs.readFileSync(path.join(__dirname, "../openapi.yaml"), "utf8"),
);

// CORS configuration
const allowedOrigins = [
  "http://localhost:3000",
  "http://taskflow-dev-alb-878046829.ap-south-1.elb.amazonaws.com",
];

app.use(
  cors({
    origin: allowedOrigins,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
  }),
);

app.use(express.json());

// Health check
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    message: "TaskFlow API is running",
    timestamp: new Date().toISOString(),
  });
});

// Swagger UI
app.use("/api-docs", swaggerUi.serve, swaggerUi.setup(openApiDocument));

// Task routes
app.use("/api/tasks", require("./routes/task.routes"));

// Error handler
app.use((error, req, res, next) => {
  console.error(error);
  res.status(500).json({ error: "Internal server error" });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`TaskFlow API running on port ${PORT}`);
  });
}

module.exports = app;
