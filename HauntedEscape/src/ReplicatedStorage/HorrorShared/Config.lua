--[[
	Config : ตั้งค่าทั้งหมดของเกม HAUNTED ESCAPE
	อยากปรับความยาก / ความเร็วผี / เสียง แก้ที่ไฟล์นี้ไฟล์เดียว
]]

local Config = {}

Config.GameTitle = "HAUNTED ESCAPE"
Config.GameSubtitle = "หนีให้รอด 4 ด่าน"

-- ===== ล็อบบี้ =====
Config.PartySizes = { 1, 2, 3, 4, 5, 6 } -- แท่นทีม 1-6 คน
Config.LobbyCountdown = 10 -- นับถอยหลังกี่วินาทีเมื่อคนบนแท่นครบ
Config.WaitForPartyTimeout = 25 -- (เซิร์ฟเวอร์เกม) รอเพื่อนเข้ามาให้ครบสูงสุดกี่วินาที
Config.RemoveBaseplate = true -- ลบ Baseplate เดิมของเพลสทิ้งอัตโนมัติ

-- ===== ผู้เล่น =====
Config.WalkSpeed = 14
Config.SprintSpeed = 24
Config.StaminaMax = 100
Config.StaminaDrain = 28 -- ลดต่อวินาทีตอนวิ่ง
Config.StaminaRegen = 16 -- ฟื้นต่อวินาที
Config.RespawnTime = 4
Config.FirstPerson = true -- บังคับมุมมองบุคคลที่หนึ่งในด่าน (ตุ้งแช่จะน่ากลัวกว่า)

-- ===== ตำแหน่งพื้นที่ต่าง ๆ บนแมพ (ห่างกันมากพอจะไม่เห็นกัน) =====
Config.Origins = {
	Lobby = Vector3.new(0, 0, 0),
	[1] = Vector3.new(0, 0, 1000),
	[2] = Vector3.new(0, 0, 2000),
	[3] = Vector3.new(0, 0, 3000),
	[4] = Vector3.new(0, 0, 4000),
	[5] = Vector3.new(0, 0, 5000), -- หน้าจบ
}

Config.Stages = {
	[1] = {
		Name = "ด่าน 1 : ทางเดินป่าช้า",
		Objective = "เดินไปให้สุดทางแล้วเข้าประตูวาป... อย่าหยุดเดิน",
	},
	[2] = {
		Name = "ด่าน 2 : บ้านร้าง",
		Objective = "หากุญแจเพื่อเปิดประตูทางออก (ระวังผีไล่!)",
	},
	[3] = {
		Name = "ด่าน 3 : สุสานต้องสาป",
		Objective = "เก็บเทียนวิญญาณ แล้วนำไปวางที่แท่นบูชากลางสุสาน",
	},
	[4] = {
		Name = "ด่าน 4 : โรงพยาบาลร้าง",
		Objective = "หาฟิวส์ไปใส่เครื่องปั่นไฟที่จุดเริ่มต้น แล้วหนีออกไป",
	},
	[5] = {
		Name = "หนีรอดแล้ว!",
		Objective = "ยินดีด้วย... คุณรอดชีวิตจากคืนนี้",
	},
}

-- ===== ผี =====
-- Count = จำนวนผีเริ่มต้น, ExtraPer = เพิ่มผี 1 ตัวทุก ๆ X คนในทีม
Config.Ghosts = {
	Stage2 = { Count = 1, ExtraPer = 3, Speed = 13, Damage = 35, DetectRange = 90 },
	Stage3 = { Count = 3, ExtraPer = 2, Speed = 11, Damage = 20, DetectRange = 60, Health = 100, RespawnDelay = 12 },
	Boss = { Speed = 10, Damage = 30, DetectRange = 250, Health = 300, HealthPerPlayer = 120, Scale = 2 },
	Stage4 = { Count = 2, ExtraPer = 3, Speed = 15, Damage = 40, DetectRange = 100, RageSpeed = 18 },
	SpawnDelay = 6, -- วินาทีก่อนผีออกมาหลังเข้าด่าน
}

-- ===== อาวุธด่าน 3 =====
Config.Weapon = {
	Name = "ไม้กางเขนศักดิ์สิทธิ์",
	Damage = 34,
	Range = 14,
	Cooldown = 0.6,
}

-- ===== เควส =====
Config.Quest = {
	Candles = 5, -- ด่าน 3
	Fuses = 4, -- ด่าน 4
}

-- ===== รูปภาพ =====
-- อัปโหลดรูปใน Roblox Studio (Asset Manager) แล้วเอา ID มาใส่ เช่น "rbxassetid://1234567890" หรือแค่ตัวเลข
-- เว้นว่างไว้ = ใช้หน้าผีที่วาดด้วยโค้ดแทน
Config.Images = {
	Jumpscare = "", -- รูปหน้าผีเต็มจอตอนตุ้งแช่
	GhostFace = "", -- รูปหน้าที่แปะบนตัวผี 3D (ใช้รูปเดียวกับ Jumpscare ก็ได้)
	Painting = "", -- รูปภาพหลอน ๆ ที่แขวนในล็อบบี้
}

-- ===== เสียง =====
-- ใส่ Sound ID จาก Toolbox / Creator Store ได้เลย เช่น "rbxassetid://1234567890"
-- ถ้าเว้นว่างไว้ เกมยังเล่นได้ปกติ แค่ไม่มีเสียงนั้น
Config.Sounds = {
	Jumpscare = "", -- เสียงกรีดร้องตอนตุ้งแช่
	Whisper = "", -- เสียงกระซิบ
	Heartbeat = "", -- เสียงหัวใจเต้น (เล่นวนตอนผีอยู่ใกล้)
	Ambience = "", -- เสียงบรรยากาศในด่าน (เล่นวน)
	LobbyMusic = "", -- เพลงในล็อบบี้ (เล่นวน)
	Pickup = "", -- เก็บของ
	Door = "", -- ประตูเปิด
	Portal = "", -- วาป
	Hit = "", -- โดนผีตี
	Victory = "", -- หน้าจบ
}

return Config
