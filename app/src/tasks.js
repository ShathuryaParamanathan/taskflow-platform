const express = require("express");
const router = express.Router();
const pool = require("./db");
router.get("/", async (req, res, next) => {
  try {
    const result = await pool.query(
      "SELECT id, title, description, status, created_at, updated_at FROM tasks ORDER BY id DESC",
    );
    res.status(200).json({ data: result.rows });
  } catch (error) {
    next(error);
  }
});
router.post("/", async (req, res, next) => {
  try {
    const { title, description = "", status = "pending" } = req.body;
    if (typeof title !== "string" || !title.trim())
      return res.status(400).json({ error: "title is required" });
    if (title.trim().length > 200)
      return res
        .status(400)
        .json({ error: "title must be 200 characters or fewer" });
    if (typeof description !== "string")
      return res.status(400).json({ error: "description must be a string" });
    if (!["pending", "in_progress", "completed"].includes(status))
      return res.status(400).json({ error: "invalid status" });
    const result = await pool.query(
      "INSERT INTO tasks (title, description, status) VALUES ($1, $2, $3) RETURNING id, title, description, status, created_at, updated_at",
      [title.trim(), description, status],
    );
    res.status(201).json({ data: result.rows[0] });
  } catch (error) {
    next(error);
  }
});
module.exports = router;
