const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;
app.use(express.json());
app.get("/health", (req, res) => {
  res
    .status(200)
    .json({
      status: "healthy",
      message: "TaskFlow API is running",
      timestamp: new Date().toISOString(),
    });
});
app.use("/api/tasks", require("./tasks"));
app.use((error, req, res, next) => {
  console.error(error);
  res.status(500).json({ error: "Internal server error" });
});
if (require.main === module) {
  app.listen(PORT, () => console.log(`TaskFlow API running on port ${PORT}`));
}
module.exports = app;
