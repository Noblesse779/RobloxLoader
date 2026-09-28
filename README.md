# RobloxLoader

โปรเจกต์ตัวอย่างสำหรับสร้างเกม Roblox ของคุณเอง ประกอบด้วย:

- **UI Library** (`src/shared/UILib.lua`) — สร้างหน้าต่าง GUI แบบมี Tab / Toggle / Slider / TextBox ลากได้ ใช้ซ้ำได้กับเมนูไหนก็ได้
- **ระบบ Lock-On ต่อสู้แบบเท่าเทียม** (`src/client/LockOnController.client.lua` + `src/server/CombatServer.server.lua`) — ผู้เล่นทุกคนมีตัวช่วยล็อกเป้าเหมือนกัน แต่เซิร์ฟเวอร์เป็นผู้ตัดสินว่าตีโดนจริงไหม (เช็คระยะ, แนวการมองเห็น, cooldown) เพื่อป้องกันไม่ให้ client ที่ถูกดัดแปลงโกงได้
- **ระบบตั้งค่า walk speed แบบ server-authoritative** (`src/server/PlayerSettingsServer.server.lua`) — client แค่ "ขอ" ค่าความเร็ว เซิร์ฟเวอร์เป็นคน clamp และ apply เอง
- **Discord Webhook relay** (`src/server/WebhookRelay.server.lua`) — ส่งข้อความแจ้งเตือนผ่าน Discord webhook โดย URL ถูกเก็บไว้ฝั่งเซิร์ฟเวอร์เท่านั้น ไม่ให้ client กำหนดปลายทางเอง

> หมายเหตุ: repo นี้เคยมีสคริปต์ aimbot (`Roxpox`) และสคริปต์ invisibility (`script.lua`) สำหรับใช้กับเกมของคนอื่น ซึ่งถูกลบออกแล้ว เพราะเป็น exploit ที่ผิด Terms of Service ของ Roblox โค้ดทั้งหมดด้านล่างนี้ออกแบบมาให้ใช้ใน **เกมของคุณเอง** เท่านั้น และมีทุกฝั่งตรวจสอบความถูกต้องที่เซิร์ฟเวอร์ (server-authoritative) เพื่อไม่ให้กลายเป็นช่องโหว่ให้คนอื่นโกงในเกมของคุณ

## โครงสร้างไฟล์

```
src/
  shared/   -> ไปอยู่ใน ReplicatedStorage      (ModuleScript)
  server/   -> ไปอยู่ใน ServerScriptService     (Script)
  client/   -> ไปอยู่ใน StarterPlayerScripts    (LocalScript)
```

| ไฟล์ | ปลายทางใน Studio | ชนิด |
|---|---|---|
| `src/shared/UILib.lua` | ReplicatedStorage | ModuleScript |
| `src/shared/Remotes.lua` | ReplicatedStorage | ModuleScript |
| `src/shared/CombatConfig.lua` | ReplicatedStorage | ModuleScript |
| `src/server/PlayerSettingsServer.server.lua` | ServerScriptService | Script |
| `src/server/WebhookRelay.server.lua` | ServerScriptService | Script |
| `src/server/CombatServer.server.lua` | ServerScriptService | Script |
| `src/client/MenuClient.client.lua` | StarterPlayer > StarterPlayerScripts | LocalScript |
| `src/client/LockOnController.client.lua` | StarterPlayer > StarterPlayerScripts | LocalScript |

## วิธีติดตั้ง

### แบบใช้ Rojo (แนะนำ)

1. ติดตั้ง [Rojo](https://rojo.space/) และ plugin ใน Roblox Studio
2. เปิด place ของคุณ แล้วรัน `rojo serve` ในโฟลเดอร์นี้ จากนั้นกด Connect ใน Studio
3. `default.project.json` จะ sync ไฟล์ทั้งหมดเข้าตำแหน่งที่ถูกต้องให้อัตโนมัติ

### แบบ copy-paste ด้วยมือ

1. เปิด Roblox Studio > Explorer
2. สร้าง ModuleScript ชื่อ `UILib`, `Remotes`, `CombatConfig` ใน **ReplicatedStorage** แล้ววางโค้ดจากไฟล์ที่ตรงกัน
3. สร้าง Script ชื่อ `PlayerSettingsServer`, `WebhookRelay`, `CombatServer` ใน **ServerScriptService**
4. สร้าง LocalScript ชื่อ `MenuClient`, `LockOnController` ใน **StarterPlayer > StarterPlayerScripts**

### เปิดใช้ HttpService (จำเป็นสำหรับ Webhook)

Game Settings > Security > เปิด **Allow HTTP Requests** แล้วใส่ URL ของ Discord webhook ในตัวแปร `DISCORD_WEBHOOK_URL` ที่ต้นไฟล์ `WebhookRelay.server.lua`

## การควบคุมในเกม

- **Right Ctrl** — เปิด/ปิดเมนู
- **Tab** — สลับล็อกเป้าผู้เล่นที่ใกล้ที่สุด
- **คลิกซ้าย** — โจมตีเป้าที่ล็อกไว้ (ถ้าอยู่ในระยะและไม่มีอะไรบัง)

## แนวคิดสำคัญที่สาธิตในโปรเจกต์นี้

- **อย่าเชื่อ client** — ทุกอย่างที่กระทบความเป็นธรรม (ความเร็ว, ดาเมจ) ต้องเช็ค/คำนวณที่เซิร์ฟเวอร์เสมอ client แค่ "ขอ" เท่านั้น
- **RemoteEvent สำหรับสื่อสาร client-server** — ดูตัวอย่างใน `Remotes.lua`
- **UI library แยกจาก game logic** — `UILib.lua` ไม่รู้จักระบบเกมเลย ใช้ประกอบเมนูอะไรก็ได้
