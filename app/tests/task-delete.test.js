import { describe, it, expect } from "vitest";
import request from "supertest";
import pool from "../src/db.js";
import app from "../src/server.js";

describe("DELETE /api/tasks/:id", () => {
  it("deletes an existing task", async () => {
    const inserted = await pool.query(
      `INSERT INTO tasks (title, description, status)
       VALUES ($1, $2, $3)
       RETURNING id`,
      ["Task to delete", "Delete test", "pending"],
    );

    const id = inserted.rows[0].id;

    const response = await request(app).delete(`/api/tasks/${id}`);

    expect(response.status).toBe(200);
    expect(response.body.message).toBe("Task deleted successfully");
    expect(String(response.body.data.id)).toBe(String(id));

    const saved = await pool.query("SELECT id FROM tasks WHERE id = $1", [id]);

    expect(saved.rows).toHaveLength(0);
  });

  it("returns 404 when the task does not exist", async () => {
    const response = await request(app).delete("/api/tasks/999999999");

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Task not found");
  });

  it("returns 400 for an invalid task ID", async () => {
    const response = await request(app).delete("/api/tasks/abc");

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("Invalid task ID");
  });
});
