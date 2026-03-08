/**
 * E-Commerce Backend API — Node.js / Express
 *
 * Endpoints:
 *   GET  /health          — Kubernetes liveness probe
 *   GET  /ready           — Kubernetes readiness probe
 *   GET  /metrics         — Prometheus metrics (scraped by kube-prometheus)
 *   GET  /api/products    — List products (cached in Redis)
 *   GET  /api/products/:id — Single product
 *   POST /api/orders      — Create order
 *   POST /api/auth/login  — Authenticate user
 */

const express = require("express");
const mysql = require("mysql2/promise");
const redis = require("redis");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const promClient = require("prom-client");
const morgan = require("morgan");
const helmet = require("helmet");
const cors = require("cors");
const jwt = require("jsonwebtoken");

const app = express();
const PORT = process.env.PORT || 3000;

// ── Prometheus metrics ────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5],
  registers: [register],
});

const httpRequestTotal = new promClient.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status_code"],
  registers: [register],
});

const cacheHits = new promClient.Counter({
  name: "redis_cache_hits_total",
  help: "Total Redis cache hits",
  registers: [register],
});

const cacheMisses = new promClient.Counter({
  name: "redis_cache_misses_total",
  help: "Total Redis cache misses",
  registers: [register],
});

// ── Middleware ────────────────────────────────────────────
app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "10mb" }));
app.use(morgan("combined"));

// Prometheus request timing middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    end({
      method: req.method,
      route: req.route?.path || req.path,
      status_code: res.statusCode,
    });
    httpRequestTotal.inc({
      method: req.method,
      route: req.route?.path || req.path,
      status_code: res.statusCode,
    });
  });
  next();
});

// ── Database & Cache connections ──────────────────────────
let db;
let redisClient;

async function initConnections() {
  // MySQL connection pool — handles reconnections automatically
  db = await mysql.createPool({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT) || 3306,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
    enableKeepAlive: true,
    keepAliveInitialDelay: 0,
  });

  // Redis client
  redisClient = redis.createClient({
    socket: {
      host: process.env.REDIS_HOST || "redis-service",
      port: parseInt(process.env.REDIS_PORT) || 6379,
      reconnectStrategy: (retries) => Math.min(retries * 50, 2000),
    },
  });

  redisClient.on("error", (err) => console.error("Redis error:", err));
  redisClient.on("connect", () => console.log("✅ Redis connected"));

  await redisClient.connect();
  console.log("✅ MySQL pool initialized");
}

// ── Health endpoints ──────────────────────────────────────
// Liveness: am I alive? (restart if this fails)
app.get("/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// Readiness: can I serve traffic? (stop sending traffic if this fails)
app.get("/ready", async (req, res) => {
  try {
    await db.query("SELECT 1");
    await redisClient.ping();
    res.json({ status: "ready", db: "ok", redis: "ok" });
  } catch (err) {
    console.error("Readiness check failed:", err.message);
    res.status(503).json({ status: "not ready", error: err.message });
  }
});

// Prometheus metrics scrape endpoint
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// ── Products API ──────────────────────────────────────────
app.get("/api/products", async (req, res) => {
  try {
    const cacheKey = "products:all";

    // Try cache first
    const cached = await redisClient.get(cacheKey);
    if (cached) {
      cacheHits.inc();
      return res.json(JSON.parse(cached));
    }

    cacheMisses.inc();

    // Query database
    const [rows] = await db.query(
      "SELECT id, name, price, description, image_key FROM products WHERE active = 1 LIMIT 100"
    );

    // Cache for 5 minutes
    await redisClient.setEx(cacheKey, 300, JSON.stringify(rows));

    res.json(rows);
  } catch (err) {
    console.error("GET /api/products error:", err);
    res.status(500).json({ error: "Failed to fetch products" });
  }
});

app.get("/api/products/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const cacheKey = `product:${id}`;

    const cached = await redisClient.get(cacheKey);
    if (cached) {
      cacheHits.inc();
      return res.json(JSON.parse(cached));
    }

    cacheMisses.inc();

    const [rows] = await db.query(
      "SELECT * FROM products WHERE id = ? AND active = 1",
      [id]
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: "Product not found" });
    }

    await redisClient.setEx(cacheKey, 600, JSON.stringify(rows[0]));
    res.json(rows[0]);
  } catch (err) {
    console.error("GET /api/products/:id error:", err);
    res.status(500).json({ error: "Failed to fetch product" });
  }
});

// ── Orders API ────────────────────────────────────────────
app.post("/api/orders", authenticateToken, async (req, res) => {
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const { items } = req.body; // [{ productId, quantity }]
    const userId = req.user.id;

    // Calculate total
    const productIds = items.map((i) => i.productId);
    const [products] = await conn.query(
      "SELECT id, price FROM products WHERE id IN (?)",
      [productIds]
    );

    const productMap = Object.fromEntries(products.map((p) => [p.id, p]));
    const total = items.reduce((sum, item) => {
      return sum + productMap[item.productId].price * item.quantity;
    }, 0);

    // Create order
    const [orderResult] = await conn.query(
      "INSERT INTO orders (user_id, total, status) VALUES (?, ?, ?)",
      [userId, total, "pending"]
    );
    const orderId = orderResult.insertId;

    // Create order items
    const orderItems = items.map((i) => [orderId, i.productId, i.quantity, productMap[i.productId].price]);
    await conn.query(
      "INSERT INTO order_items (order_id, product_id, quantity, price) VALUES ?",
      [orderItems]
    );

    await conn.commit();

    // Invalidate user's order cache
    await redisClient.del(`user:${userId}:orders`);

    res.status(201).json({ orderId, total, status: "pending" });
  } catch (err) {
    await conn.rollback();
    console.error("POST /api/orders error:", err);
    res.status(500).json({ error: "Failed to create order" });
  } finally {
    conn.release();
  }
});

// ── Auth API ──────────────────────────────────────────────
app.post("/api/auth/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    const [rows] = await db.query(
      "SELECT id, email, password_hash FROM users WHERE email = ?",
      [email]
    );

    if (rows.length === 0) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    // In production: use bcrypt.compare for password hashing
    const token = jwt.sign(
      { id: rows[0].id, email: rows[0].email },
      process.env.JWT_SECRET,
      { expiresIn: "24h" }
    );

    res.json({ token });
  } catch (err) {
    console.error("POST /api/auth/login error:", err);
    res.status(500).json({ error: "Authentication failed" });
  }
});

// ── JWT middleware ────────────────────────────────────────
function authenticateToken(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return res.status(401).json({ error: "No token provided" });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ error: "Invalid token" });
    req.user = user;
    next();
  });
}

// ── Startup ───────────────────────────────────────────────
async function start() {
  try {
    await initConnections();
    app.listen(PORT, () => {
      console.log(`🚀 Backend API running on port ${PORT}`);
      console.log(`📊 Metrics available at http://localhost:${PORT}/metrics`);
    });
  } catch (err) {
    console.error("Failed to start server:", err);
    process.exit(1);
  }
}

// Graceful shutdown
process.on("SIGTERM", async () => {
  console.log("SIGTERM received — shutting down gracefully");
  await redisClient.quit();
  await db.end();
  process.exit(0);
});

start();
