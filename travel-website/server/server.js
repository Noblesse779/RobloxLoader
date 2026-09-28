require("dotenv").config();
const path = require("path");
const express = require("express");
const helmet = require("helmet");
const cookieParser = require("cookie-parser");

if (!process.env.JWT_SECRET) {
  console.error("Missing JWT_SECRET in environment (.env). Refusing to start.");
  process.exit(1);
}

const authRoutes = require("./routes/auth");
const destinationRoutes = require("./routes/destinations");

const app = express();
app.set("trust proxy", 1);

app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        imgSrc: ["'self'", "https://images.unsplash.com", "data:"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
      },
    },
  })
);
app.use(express.json({ limit: "100kb" }));
app.use(cookieParser());

app.use("/api/auth", authRoutes);
app.use("/api/destinations", destinationRoutes);

app.use(express.static(path.join(__dirname, "..", "public")));
app.use("/admin", express.static(path.join(__dirname, "..", "admin")));

app.use((req, res) => {
  res.status(404).json({ error: "ไม่พบหน้านี้" });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Travel website server running on http://localhost:${PORT}`);
});
