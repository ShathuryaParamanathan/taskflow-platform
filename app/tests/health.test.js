
import { describe, it, expect } from "vitest";
import request from "supertest";
import app from "../src/server.js";

describe("GET /health", () => {
  it("should return HTTP 200 and healthy status", async () => {
    const response = await request(app).get("/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("healthy");
    expect(response.body.message).toBe("TaskFlow API is running");
  });
});
