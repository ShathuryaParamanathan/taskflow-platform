import { describe, it, expect } from "vitest";
import request from "supertest";
import app from "../src/server.js";
describe("GET /api/tasks", () => {
  it("returns HTTP 200 and a data array", async () => {
    const response = await request(app).get("/api/tasks");
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty("data");
    expect(Array.isArray(response.body.data)).toBe(true);
  });
  it("returns tasks with expected fields when tasks exist", async () => {
    const response = await request(app).get("/api/tasks");
    expect(response.status).toBe(200);
    if (response.body.data.length > 0) {
      expect(response.body.data[0]).toHaveProperty("id");
      expect(response.body.data[0]).toHaveProperty("title");
      expect(response.body.data[0]).toHaveProperty("status");
    }
  });
});
