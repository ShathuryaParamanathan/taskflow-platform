import { describe, it, expect } from "vitest";
import request from "supertest";
import pool from "../src/db.js";
import app from "../src/server.js";

describe("GET /api/tasks/:id", () => {
  it("returns a task when the ID exists", async () => {
    const inserted = await pool.query(
      `INSERT INTO tasks (title, description, status)
       VALUES ($1, $2, $3)
       RETURNING id`,
      ["GET-by-ID test task", "Test description", "pending"]
    );

    const id = inserted.rows[0].id;

    try {
      const response = await request(app).get(`/api/tasks/${id}`);

      expect(response.status).toBe(200);
      expect(response.body.data.title).toBe("GET-by-ID test task");
      expect(String(response.body.data.id)).toBe(String(id));
    } finally {
      await pool.query("DELETE FROM tasks WHERE id = $1", [id]);
    }
  });

  it("returns 404 when the task does not exist", async () => {
    const response = await request(app).get("/api/tasks/999999999");

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Task not found");
  });

  it("returns 400 for an invalid task ID", async () => {
    const response = await request(app).get("/api/tasks/abc");

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("Invalid task ID");
  });
});