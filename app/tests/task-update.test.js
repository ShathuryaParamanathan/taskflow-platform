import { describe, it, expect } from "vitest";
import request from "supertest";
import pool from "../src/db.js";
import app from "../src/server.js";

describe("PUT /api/tasks/:id", () => {
  it("updates an existing task", async () => {
    const inserted = await pool.query(
      `INSERT INTO tasks (title, description, status)
       VALUES ($1, $2, $3)
       RETURNING id`,
      ["Original title", "Original description", "pending"],
    );

    const id = inserted.rows[0].id;

    try {
      const response = await request(app).put(`/api/tasks/${id}`).send({
        title: "Updated title",
        description: "Updated description",
        status: "in_progress",
      });

      expect(response.status).toBe(200);
      expect(response.body.data.title).toBe("Updated title");
      expect(response.body.data.description).toBe("Updated description");
      expect(response.body.data.status).toBe("in_progress");
    } finally {
      await pool.query("DELETE FROM tasks WHERE id = $1", [id]);
    }
  });

  it("returns 404 when the task does not exist", async () => {
    const response = await request(app).put("/api/tasks/999999999").send({
      title: "Updated title",
      description: "Updated description",
      status: "pending",
    });

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Task not found");
  });

  it("returns 400 for an invalid task ID", async () => {
    const response = await request(app).put("/api/tasks/abc").send({
      title: "Updated title",
      description: "Updated description",
      status: "pending",
    });

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("Invalid task ID");
  });
});
