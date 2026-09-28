# เที่ยวรอบโลก

เว็บไซต์รวมสถานที่ท่องเที่ยวทั่วโลก พร้อมระบบแอดมินสำหรับจัดการข้อมูล (เพิ่ม/แก้ไข/ลบสถานที่)

## โครงสร้างโปรเจกต์

```
travel-website/
├── server/       Express API + auth (Node.js, SQLite)
├── public/       เว็บไซต์หลักที่ผู้ใช้ทั่วไปเห็น
└── admin/        หน้าแอดมิน (เข้าสู่ระบบ + แดชบอร์ดจัดการข้อมูล)
```

เซิร์ฟเวอร์ตัวเดียวให้บริการทั้งสามส่วน: หน้าเว็บหลักที่ `/`, หน้าแอดมินที่ `/admin`, และ REST API ที่ `/api/*`.

## เริ่มต้นใช้งาน (local)

```bash
cd travel-website/server
npm install
cp .env.example .env
```

แก้ไข `.env`:
- `JWT_SECRET` — สุ่มค่าใหม่ด้วย `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`
- `ADMIN_USERNAME` / `ADMIN_PASSWORD` — บัญชีแอดมินคนแรก (ตั้งรหัสผ่านที่คาดเดายาก)

จากนั้นสร้างฐานข้อมูลและบัญชีแอดมิน (รันครั้งเดียว):

```bash
npm run seed
```

**สำคัญ:** หลัง seed สำเร็จ ให้ลบค่า `ADMIN_PASSWORD` ออกจาก `.env` (หรือเว้นว่างไว้) เพื่อไม่ให้สคริปต์พยายามสร้างบัญชีซ้ำ และเพื่อไม่ให้รหัสผ่านค้างอยู่ในไฟล์

เริ่มเซิร์ฟเวอร์:

```bash
npm start
```

เปิดเบราว์เซอร์ไปที่:
- เว็บไซต์หลัก: http://localhost:3000
- หน้าแอดมิน: http://localhost:3000/admin

## ฟีเจอร์

- **หน้าเว็บหลัก** — ค้นหา, กรองตามทวีป, ดูรายละเอียดสถานที่ (ข้อมูลดึงจาก API แบบ real-time)
- **ระบบแอดมิน** — เข้าสู่ระบบด้วย JWT เก็บใน httpOnly cookie, แดชบอร์ดเพิ่ม/แก้ไข/ลบสถานที่ท่องเที่ยวได้ทันทีโดยไม่ต้องแก้โค้ด
- **ความปลอดภัย** — รหัสผ่านเข้ารหัสด้วย bcrypt, จำกัดจำนวนครั้งการ login (rate limit), ตรวจสอบข้อมูลนำเข้าทุกช่อง (validation), Content-Security-Policy ผ่าน Helmet

## Deploy ขึ้นโฮสต์จริง

ต้องใช้โฮสต์ที่รันเซิร์ฟเวอร์ Node.js ได้ต่อเนื่อง (ไม่ใช่ static hosting เฉยๆ) เช่น [Render](https://render.com), [Railway](https://railway.app), [Fly.io](https://fly.io) หรือ VPS ทั่วไป

ขั้นตอนคร่าวๆ (ยกตัวอย่าง Render):
1. Push โค้ดนี้ขึ้น GitHub (ทำแล้ว)
2. สร้าง Web Service ใหม่บน Render ชี้ไปที่ repo นี้ โดยตั้ง **Root Directory** เป็น `travel-website/server`
3. Build Command: `npm install` — Start Command: `npm start`
4. ตั้งค่า Environment Variables บนแดชบอร์ดของ Render: `JWT_SECRET`, `NODE_ENV=production`, `ADMIN_USERNAME`, `ADMIN_PASSWORD` (ใส่เฉพาะตอน deploy ครั้งแรกเพื่อ seed แล้วค่อยลบออก)
5. เพิ่ม **Persistent Disk** mount ไว้ที่โฟลเดอร์ของ `server/` (หรือกำหนด `DB_PATH` ไปยัง disk ที่ mount ไว้) ไม่งั้นข้อมูลจะหายเมื่อ deploy ใหม่ เพราะ SQLite เก็บเป็นไฟล์
6. รัน `npm run seed` ครั้งแรกผ่าน Shell ของ Render (หรือใน deploy hook) เพื่อสร้างบัญชีแอดมินและข้อมูลตั้งต้น

หลัง deploy แล้วเข้าใช้งานได้ที่ `https://<your-app>.onrender.com` และหน้าแอดมินที่ `https://<your-app>.onrender.com/admin`
