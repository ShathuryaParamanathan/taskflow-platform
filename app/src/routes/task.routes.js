const express = require("express");
const router = express.Router();
const pool = require("../db");
//Get all tasks
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
//Create a new task
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
//Get a task by ID
router.get("/:id", async (req, res, next) => {
  try {
    const id = req.params.id;

    if (!/^[1-9]\d*$/.test(id)) {
      return res.status(400).json({
        error: "Invalid task ID",
      });
    }

    const result = await pool.query(
      `SELECT id, title, description, status, created_at, updated_at
       FROM tasks
       WHERE id = $1`,
      [id],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: "Task not found",
      });
    }

    res.status(200).json({
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
});
//Update a task by ID
router.put("/:id", async (req, res, next) => {
  try {
    const { id } = req.params;

    if (!/^[1-9]\d*$/.test(id)) {
      return res.status(400).json({ error: "Invalid task ID" });
    }

    const { title, description, status } = req.body;

    if (typeof title !== "string" || !title.trim()) {
      return res.status(400).json({ error: "title is required" });
    }

    if (title.trim().length > 200) {
      return res
        .status(400)
        .json({ error: "title must be 200 characters or fewer" });
    }

    if (typeof description !== "string") {
      return res.status(400).json({ error: "description must be a string" });
    }

    if (!["pending", "in_progress", "completed"].includes(status)) {
      return res.status(400).json({ error: "invalid status" });
    }

    const result = await pool.query(
      `UPDATE tasks
       SET title = $1,
           description = $2,
           status = $3,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING id, title, description, status, created_at, updated_at`,
      [title.trim(), description, status, id],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Task not found" });
    }

    return res.status(200).json({ data: result.rows[0] });
  } catch (error) {
    next(error);
  }
});
//Only update specific fields of a task by ID
router.patch("/:id", async (req, res, next) => {
  try {
    const { id } = req.params;

    if (!/^[1-9]\d*$/.test(id)) {
      return res.status(400).json({ error: "Invalid task ID" });
    }

    const allowedFields = ["title", "description", "status"];
    const incoming = req.body;

    if (
      !incoming ||
      typeof incoming !== "object" ||
      Array.isArray(incoming)
    ) {
      return res.status(400).json({ error: "Invalid request body" });
    }

    const fields = Object.keys(incoming);

    if (fields.length === 0) {
      return res.status(400).json({ error: "Provide at least one field to update" });
    }

    if (fields.some((field) => !allowedFields.includes(field))) {
      return res.status(400).json({ error: "Unknown field provided" });
    }

    if (
      "title" in incoming &&
      (typeof incoming.title !== "string" ||
        !incoming.title.trim() ||
        incoming.title.trim().length > 200)
    ) {
      return res.status(400).json({ error: "Invalid title" });
    }

    if (
      "description" in incoming &&
      typeof incoming.description !== "string"
    ) {
      return res.status(400).json({ error: "description must be a string" });
    }

    if (
      "status" in incoming &&
      !["pending", "in_progress", "completed"].includes(incoming.status)
    ) {
      return res.status(400).json({ error: "Invalid status" });
    }

    const currentResult = await pool.query(
      `SELECT id, title, description, status, created_at, updated_at
       FROM tasks WHERE id = $1`,
      [id],
    );

    if (currentResult.rows.length === 0) {
      return res.status(404).json({ error: "Task not found" });
    }

    const current = currentResult.rows[0];
    const changedFields = fields.filter((field) => {
      const newValue =
        field === "title" ? incoming.title.trim() : incoming[field];

      return current[field] !== newValue;
    });

    if (changedFields.length === 0) {
      return res.status(200).json({ data: current });
    }

    const values = [];
    const setClauses = changedFields.map((field, index) => {
      const value =
        field === "title" ? incoming.title.trim() : incoming[field];

      values.push(value);
      return `${field} = $${index + 1}`;
    });

    values.push(id);

    const result = await pool.query(
      `UPDATE tasks
       SET ${setClauses.join(", ")},
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $${values.length}
       RETURNING id, title, description, status, created_at, updated_at`,
      values,
    );

    return res.status(200).json({ data: result.rows[0] });
  } catch (error) {
    next(error);
  }
});
//Delete a task by ID
router.delete("/:id", async (req, res, next) => {
  try {
    const { id } = req.params;

    if (!/^[1-9]\d*$/.test(id)) {
      return res.status(400).json({
        error: "Invalid task ID",
      });
    }

    const result = await pool.query(
      `DELETE FROM tasks
       WHERE id = $1
       RETURNING id, title, description, status, created_at, updated_at`,
      [id],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: "Task not found",
      });
    }

    return res.status(200).json({
      message: "Task deleted successfully",
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
