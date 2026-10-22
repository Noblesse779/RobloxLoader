# 👻 HAUNTED ESCAPE : หนีให้รอด 4 ด่าน

แมพผี Roblox มีล็อบบี้เลือกทีม 1–6 คน และ 4 ด่าน + หน้าจบ
**สร้างด้วยโค้ดทั้งหมด** ไม่ต้องหา Model/Asset เพิ่ม กด Play แล้วแมพจะสร้างเองอัตโนมัติ

---

## 🗺️ ในเกมมีอะไรบ้าง

| พื้นที่ | รายละเอียด |
|---|---|
| **ล็อบบี้** | ห้องโถงคฤหาสน์ผี มี **แท่นทีม 1, 2, 3, 4, 5, 6 คน** ยืนบนแท่นให้ครบจำนวน → นับถอยหลัง 10 วิ → วาปทั้งทีมเข้าเกม (เซิร์ฟเวอร์ส่วนตัวของทีม) |
| **ด่าน 1 : ทางเดินป่าช้า** | ทางเดินยาว ~420 studs ในป่ามืด มี **จุดตุ้งแช่ 7 จุด** (หน้าผีโผล่เต็มจอ, ผีพุ่งใส่, ไฟดับ, ผีหล่นจากฟ้า, ผีอยู่ข้างหลัง) เดินสุดทางเข้า **ประตูวาป** ไปด่าน 2 |
| **ด่าน 2 : บ้านร้าง** | เขาวงกตในบ้านมืด ๆ **หากุญแจ** (สุ่มอยู่บนโต๊ะตามทางตัน) แล้วไปไขประตูทางออก มี **ผีวิ่งไล่** (Pathfinding) เก็บกุญแจแล้วผีจะโกรธเร็วขึ้น |
| **ด่าน 3 : สุสานต้องสาป** | ได้ **ไม้กางเขนศักดิ์สิทธิ์ สู้กับผีได้** (คลิก) ผีมีหลอดเลือด ตายแล้วเกิดใหม่ **เควส: เก็บเทียนวิญญาณ 5 เล่ม** ไปวางที่แท่นบูชา → **บอสผีเจ้าที่** ออกมา ปราบได้ประตูวาปเปิด |
| **ด่าน 4 : โรงพยาบาลร้าง** | เขาวงกตใหญ่ มี **ตุ้งแช่ 9 จุด + ผีวิ่งไล่ + หาฟิวส์ 4 อัน** ใส่เครื่องปั่นไฟ → ไฟแดงเตือนภัย ประตูเปิด ผีคลั่ง วิ่งหนีไปประตูวาป! |
| **หน้าจบ** | ทุ่งหญ้ายามเช้า ป้าย "คุณรอดแล้ว!" + หน้าจอสรุปเวลาที่ใช้ + ปุ่ม **กลับล็อบบี้** |

**ระบบอื่น ๆ**
- `Shift` วิ่ง (มีสตามิน่า) · `F` เปิด/ปิดไฟฉาย · มือถือมีปุ่มให้กด
- มุมมองบุคคลที่หนึ่งในด่าน (ปิดได้ใน Config)
- ผีอยู่ใกล้ → ขอบจอแดงกะพริบ + เสียงหัวใจเต้น
- ตาย → เกิดใหม่ที่จุดเริ่มด่านเดิม · คนในทีมเข้าประตูวาป = **วาปไปพร้อมกันทั้งทีม**
- จำนวนผีเพิ่มตามขนาดทีม, เลือดบอสเพิ่มตามจำนวนคน

---

## 🚀 วิธีติดตั้ง (เลือก 1 วิธี)

### วิธีที่ 1 : เปิดไฟล์สำเร็จรูป (ง่ายสุด)
1. ดาวน์โหลดไฟล์ **`HauntedEscape.rbxlx`**
2. ดับเบิลคลิกเปิดด้วย **Roblox Studio** (หรือ File → Open from File)
3. กด **Play** ได้เลย

### วิธีที่ 2 : ก๊อปสคริปต์ใส่เพลสเดิม
สร้างตามโครงนี้ใน Explorer แล้ววางโค้ดจากโฟลเดอร์ `src/` (ชื่อต้องตรงเป๊ะ)

```
ReplicatedStorage
└─ HorrorShared            (Folder)
   ├─ Config               (ModuleScript)  ← src/ReplicatedStorage/HorrorShared/Config.lua
   └─ GhostModel           (ModuleScript)  ← .../GhostModel.lua
ServerScriptService
└─ HorrorServer            (Script)        ← src/ServerScriptService/HorrorServer/init.server.lua
   ├─ MapBuilder           (ModuleScript)  ← .../MapBuilder.lua
   ├─ Ghosts               (ModuleScript)  ← .../Ghosts.lua
   ├─ Remotes              (ModuleScript)  ← .../Remotes.lua
   ├─ Run                  (ModuleScript)  ← .../Run.lua
   └─ Lobby                (ModuleScript)  ← .../Lobby.lua
StarterPlayer
└─ StarterPlayerScripts
   └─ HorrorClient         (LocalScript)   ← src/StarterPlayer/StarterPlayerScripts/HorrorClient.client.lua
```
> สคริปต์จะลบ `Baseplate` เดิมทิ้งให้อัตโนมัติ (ปิดได้ที่ `Config.RemoveBaseplate`)

### วิธีที่ 3 : Rojo
```
rojo serve      # แล้วกด Connect ใน Rojo plugin
rojo build -o HauntedEscape.rbxlx
```
ถ้าแก้โค้ดใน `src/` แล้วอยากได้ไฟล์ .rbxlx ใหม่โดยไม่ใช้ Rojo: `python3 build_place.py`

---

## 🧪 การเทส

- **เทสคนเดียวใน Studio:** กด Play → เดินไปยืนแท่น **"1 คน"** → รอ 10 วิ
- **เทสหลายคน:** แท็บ Test → Clients and Servers → เลือก 2–6 คน → ให้ทุกตัวไปยืนแท่นเดียวกัน
- ใน Studio เกมจะเล่นใน **เซิร์ฟเวอร์เดียวกัน** (Studio วาปข้ามเซิร์ฟเวอร์ไม่ได้)

## 🌐 เวลาเผยแพร่ (Publish) จริง
1. File → **Publish to Roblox**
2. เข้าเกมจริง: ล็อบบี้จะวาปแต่ละทีมไป **Reserved Server ของทีมเอง** อัตโนมัติ (ใช้ PlaceId เดียวกัน ไม่ต้องสร้างเพลสที่ 2)
3. ถ้าวาปไม่ได้ด้วยเหตุผลใดก็ตาม เกมจะเริ่มในเซิร์ฟเวอร์ล็อบบี้แทน (เล่นได้ทีละทีม)

---

## 🖼️ ใส่รูปผี (ทำให้ตุ้งแช่น่ากลัวขึ้นมาก)
1. ใน Studio เปิด **View → Asset Manager** → กด **Bulk Import** → เลือกรูป
2. คลิกขวาที่รูป → **Copy Asset ID**
3. วางใน `Config.lua` ส่วน `Config.Images`
```lua
Config.Images = {
	Jumpscare = "rbxassetid://xxxxxxxx", -- หน้าผีเต็มจอ
	GhostFace = "rbxassetid://xxxxxxxx", -- หน้าบนตัวผี 3D
	Painting  = "rbxassetid://xxxxxxxx", -- รูปแขวนผนังล็อบบี้
}
```
> ถ้าก๊อปสคริปต์ใส่เพลสเอง (ไม่ได้เปิดจากไฟล์ .rbxlx) ให้ตั้ง **Lighting → Technology = Future** เองด้วย เงาจะสวยขึ้นมาก

## 🔊 ใส่เสียง (แนะนำมาก!)
เปิด `Config.lua` ส่วน `Config.Sounds` ใส่ Sound ID จาก Creator Store เช่น

```lua
Config.Sounds = {
	Jumpscare = "rbxassetid://xxxxxxxx", -- เสียงกรีดร้อง
	Whisper   = "rbxassetid://xxxxxxxx",
	Heartbeat = "rbxassetid://xxxxxxxx",
	Ambience  = "rbxassetid://xxxxxxxx",
	...
}
```
เว้นว่างไว้ก็เล่นได้ แค่จะไม่มีเสียง (ตุ้งแช่ยังมีภาพ + จอสั่น + แฟลชแดง)

## ⚙️ ปรับความยาก (`Config.lua`)
- `Config.Ghosts.StageX.Speed / Damage / DetectRange / Count` — ความเร็ว ดาเมจ ระยะมองเห็น จำนวนผี
- `Config.Ghosts.Boss.Health` — เลือดบอส
- `Config.Weapon.Damage / Range / Cooldown` — ไม้กางเขน
- `Config.Quest.Candles / Fuses` — จำนวนของที่ต้องหา
- `Config.SprintSpeed / StaminaMax` — การวิ่ง
- `Config.FirstPerson = false` — ถ้าไม่อยากล็อกมุมมองบุคคลที่หนึ่ง
- `Config.Stages` — ชื่อด่าน/ข้อความเป้าหมาย
