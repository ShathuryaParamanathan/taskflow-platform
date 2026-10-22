const fs = require("fs");
const { Client } = require("pg");

const config = {
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
};

async function main() {
  let connected = false;

  for (let attempt = 1; attempt <= 30; attempt++) {
    const client = new Client(config);

    try {
      await client.connect();
      connected = true;
      console.log("PostgreSQL is ready");

      const migration = fs.readFileSync(
        "migrations/001_create_tasks.sql",
        "utf8",
      );

      await client.query(migration);
      console.log("Database migration completed");

      await client.end();
      return;
    } catch (error) {
      try {
        await client.end();
      } catch {}

      if (connected) throw error;

      console.log(`Waiting for PostgreSQL (${attempt}/30)`);
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }

  throw new Error("PostgreSQL did not become ready");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
