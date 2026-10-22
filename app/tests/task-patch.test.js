
import { describe, it, expect } from "vitest";
import request from "supertest";
import pool from "../src/db.js";
import app from "../src/server.js";

describe("PATCH /api/tasks/:id", () => {
  it("updates only the provided field", async () => {
    const inserted = await pool.query(
      `INSERT INTO tasks (title, description, status)
       VALUES ($1, $2, $3)
       RETURNING id`,
      ["Original title", "Keep this description", "pending"],
    );

    const id = inserted.rows[0].id;

    try {
      const response = await request(app)
        .patch(`/api/tasks/${id}`)
        .send({ status: "in_progress" });

      expect(response.status).toBe(200);
      expect(response.body.data.status).toBe("in_progress");
      expect(response.body.data.title).toBe("Original title");
      expect(response.body.data.description).toBe("Keep this description");

      const saved = await pool.query(
        "SELECT title, description, status FROM tasks WHERE id = $1",
        [id],
      );

      expect(saved.rows[0].title).toBe("Original title");
      expect(saved.rows[0].description).toBe("Keep this description");
      expect(saved.rows[0].status).toBe("in_progress");
    } finally {
      await pool.query("DELETE FROM tasks WHERE id = $1", [id]);
    }
  });

  it("rejects an invalid status", async () => {
    const response = await request(app)
      .patch("/api/tasks/1")
      .send({ status: "unknown" });

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("Invalid status");
  });

  it("returns 404 when the task does not exist", async () => {
    const response = await request(app)
      .patch("/api/tasks/999999999")
      .send({ status: "completed" });

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Task not found");
  });
});
