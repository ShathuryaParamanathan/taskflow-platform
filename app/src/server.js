
const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Health check GET API
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    message: "TaskFlow API is running",
    timestamp: new Date().toISOString(),
  });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`TaskFlow API running on port ${PORT}`);
  });
}

module.exports = app;
