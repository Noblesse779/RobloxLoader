const express = require("express");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");

const router = express.Router();

const CONTINENTS = ["asia", "europe", "america", "africa", "oceania"];

function validatePayload(body, { partial = false } = {}) {
  const errors = [];
  const data = {};

  const fields = {
    name: { required: true, maxLength: 100 },
    country: { required: true, maxLength: 100 },
    flag: { required: false, maxLength: 8 },
    continent: { required: true, oneOf: CONTINENTS },
    description: { required: true, maxLength: 1000 },
    image_url: { required: true, maxLength: 2000 },
    best_time: { required: false, maxLength: 100 },
    currency: { required: false, maxLength: 100 },
  };

  for (const [key, rule] of Object.entries(fields)) {
    const raw = body[key];
    if (raw === undefined) {
      if (rule.required && !partial) errors.push(`ต้องระบุ ${key}`);
      continue;
    }
    const value = typeof raw === "string" ? raw.trim() : raw;
    if (rule.required && (!value || value.length === 0)) {
      errors.push(`${key} ห้ามว่าง`);
      continue;
    }
    if (typeof value === "string" && value.length > rule.maxLength) {
      errors.push(`${key} ยาวเกินไป (สูงสุด ${rule.maxLength} ตัวอักษร)`);
      continue;
    }
    if (rule.oneOf && !rule.oneOf.includes(value)) {
      errors.push(`${key} ต้องเป็นหนึ่งใน: ${rule.oneOf.join(", ")}`);
      continue;
    }
    data[key] = value;
  }

  if (body.rating !== undefined) {
    const rating = Number(body.rating);
    if (Number.isNaN(rating) || rating < 0 || rating > 5) {
      errors.push("rating ต้องเป็นตัวเลขระหว่าง 0-5");
    } else {
      data.rating = rating;
    }
  } else if (!partial) {
    errors.push("ต้องระบุ rating");
  }

  try {
    if (data.image_url) new URL(data.image_url);
  } catch {
    errors.push("image_url ต้องเป็น URL ที่ถูกต้อง");
  }

  return { data, errors };
}

// Public: list destinations, optional ?continent= & ?q=
router.get("/", (req, res) => {
  const { continent, q } = req.query;
  let sql = "SELECT * FROM destinations WHERE 1=1";
  const params = [];

  if (continent && CONTINENTS.includes(continent)) {
    sql += " AND continent = ?";
    params.push(continent);
  }
  if (q) {
    sql += " AND (name LIKE ? OR country LIKE ?)";
    const like = `%${q}%`;
    params.push(like, like);
  }
  sql += " ORDER BY id ASC";

  const rows = db.prepare(sql).all(...params);
  res.json(rows);
});

router.get("/:id", (req, res) => {
  const row = db.prepare("SELECT * FROM destinations WHERE id = ?").get(req.params.id);
  if (!row) return res.status(404).json({ error: "ไม่พบสถานที่นี้" });
  res.json(row);
});

// Admin: create
router.post("/", requireAuth, (req, res) => {
  const { data, errors } = validatePayload(req.body || {});
  if (errors.length) return res.status(400).json({ error: errors.join(", ") });

  const stmt = db.prepare(`
    INSERT INTO destinations (name, country, flag, continent, description, image_url, rating, best_time, currency)
    VALUES (@name, @country, @flag, @continent, @description, @image_url, @rating, @best_time, @currency)
  `);
  const info = stmt.run({
    flag: "",
    best_time: "",
    currency: "",
    ...data,
  });
  const created = db.prepare("SELECT * FROM destinations WHERE id = ?").get(info.lastInsertRowid);
  res.status(201).json(created);
});

// Admin: update
router.put("/:id", requireAuth, (req, res) => {
  const existing = db.prepare("SELECT * FROM destinations WHERE id = ?").get(req.params.id);
  if (!existing) return res.status(404).json({ error: "ไม่พบสถานที่นี้" });

  const { data, errors } = validatePayload(req.body || {}, { partial: true });
  if (errors.length) return res.status(400).json({ error: errors.join(", ") });
  if (Object.keys(data).length === 0) {
    return res.status(400).json({ error: "ไม่มีข้อมูลที่จะอัปเดต" });
  }

  const merged = { ...existing, ...data, updated_at: new Date().toISOString() };
  db.prepare(`
    UPDATE destinations SET
      name = @name, country = @country, flag = @flag, continent = @continent,
      description = @description, image_url = @image_url, rating = @rating,
      best_time = @best_time, currency = @currency, updated_at = @updated_at
    WHERE id = @id
  `).run(merged);

  const updated = db.prepare("SELECT * FROM destinations WHERE id = ?").get(req.params.id);
  res.json(updated);
});

// Admin: delete
router.delete("/:id", requireAuth, (req, res) => {
  const info = db.prepare("DELETE FROM destinations WHERE id = ?").run(req.params.id);
  if (info.changes === 0) return res.status(404).json({ error: "ไม่พบสถานที่นี้" });
  res.status(204).end();
});

module.exports = router;
