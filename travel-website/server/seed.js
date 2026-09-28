require("dotenv").config();
const bcrypt = require("bcryptjs");
const db = require("./db");

const destinations = [
  { name: "โตเกียว", country: "ญี่ปุ่น", flag: "🇯🇵", continent: "asia",
    description: "มหานครที่ผสมผสานเทคโนโลยีล้ำสมัยกับวัฒนธรรมดั้งเดิม เต็มไปด้วยวัด ย่านช้อปปิ้ง และอาหารระดับโลก",
    image_url: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best_time: "มี.ค. - พ.ค.", currency: "เยน (JPY)" },
  { name: "บาหลี", country: "อินโดนีเซีย", flag: "🇮🇩", continent: "asia",
    description: "เกาะสวรรค์แห่งวัด ทุ่งนาขั้นบันได และชายหาดสุดโรแมนติก เหมาะกับทั้งพักผ่อนและผจญภัย",
    image_url: "https://images.unsplash.com/photo-1537996194471-e657df975ab4?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best_time: "เม.ย. - ต.ค.", currency: "รูเปียห์ (IDR)" },
  { name: "กรุงเทพฯ", country: "ไทย", flag: "🇹🇭", continent: "asia",
    description: "เมืองหลวงที่มีชีวิตชีวา วัดวาอารามสวยงาม ตลาดกลางคืน และอาหารสตรีทฟู้ดระดับตำนาน",
    image_url: "https://images.unsplash.com/photo-1508009603885-50cf7c579365?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best_time: "พ.ย. - ก.พ.", currency: "บาท (THB)" },
  { name: "ปารีส", country: "ฝรั่งเศส", flag: "🇫🇷", continent: "europe",
    description: "นครแห่งแสงสี หอไอเฟล พิพิธภัณฑ์ลูฟวร์ และร้านคาเฟ่ริมถนนที่ชวนหลงใหล",
    image_url: "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best_time: "เม.ย. - มิ.ย.", currency: "ยูโร (EUR)" },
  { name: "ซานโตรินี", country: "กรีซ", flag: "🇬🇷", continent: "europe",
    description: "เกาะสีขาว-ฟ้าสุดคลาสสิกกลางทะเลอีเจียน ชมพระอาทิตย์ตกที่สวยที่สุดในโลก",
    image_url: "https://images.unsplash.com/photo-1613395877344-13d4a8e0d49e?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best_time: "พ.ค. - ก.ย.", currency: "ยูโร (EUR)" },
  { name: "โรม", country: "อิตาลี", flag: "🇮🇹", continent: "europe",
    description: "นครโบราณที่มีประวัติศาสตร์กว่าสองพันปี บ้านของโคลอสเซียมและวาติกัน",
    image_url: "https://images.unsplash.com/photo-1552832230-c0197dd311b5?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best_time: "เม.ย. - มิ.ย.", currency: "ยูโร (EUR)" },
  { name: "นิวยอร์ก", country: "สหรัฐอเมริกา", flag: "🇺🇸", continent: "america",
    description: "มหานครที่ไม่เคยหลับใหล เต็มไปด้วยตึกระฟ้า บรอดเวย์ และพิพิธภัณฑ์ระดับโลก",
    image_url: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best_time: "ก.ย. - พ.ย.", currency: "ดอลลาร์ (USD)" },
  { name: "ริโอ เดอ จาเนโร", country: "บราซิล", flag: "🇧🇷", continent: "america",
    description: "เมืองแห่งจังหวะแซมบ้า ชายหาดโคปาคาบานา และเทือกเขาที่มีรูปปั้นพระคริสต์",
    image_url: "https://images.unsplash.com/photo-1483729558449-99ef09a8c325?auto=format&fit=crop&w=800&q=80",
    rating: 4.6, best_time: "ธ.ค. - มี.ค.", currency: "เรียล (BRL)" },
  { name: "มาชูปิกชู", country: "เปรู", flag: "🇵🇪", continent: "america",
    description: "นครโบราณของชาวอินคาบนยอดเขาแอนดีส หนึ่งในเจ็ดสิ่งมหัศจรรย์ของโลก",
    image_url: "https://images.unsplash.com/photo-1587595431973-160d0d94add1?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best_time: "พ.ค. - ก.ย.", currency: "โซล (PEN)" },
  { name: "เคปทาวน์", country: "แอฟริกาใต้", flag: "🇿🇦", continent: "africa",
    description: "เมืองริมทะเลสุดงดงามใต้เขาโต๊ะ รวมธรรมชาติ ไวน์ และประวัติศาสตร์ไว้ในที่เดียว",
    image_url: "https://images.unsplash.com/photo-1580060839134-75a5edca2e99?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best_time: "พ.ย. - มี.ค.", currency: "แรนด์ (ZAR)" },
  { name: "มาราเกช", country: "โมร็อกโก", flag: "🇲🇦", continent: "africa",
    description: "เมืองสีแดงแห่งทะเลทรายซาฮารา ตลาดสุดคึกคักและพระราชวังโบราณ",
    image_url: "https://images.unsplash.com/photo-1489493887464-892be6d1daae?auto=format&fit=crop&w=800&q=80",
    rating: 4.5, best_time: "มี.ค. - พ.ค.", currency: "ดีแรห์ม (MAD)" },
  { name: "ไคโร", country: "อียิปต์", flag: "🇪🇬", continent: "africa",
    description: "บ้านของมหาพีระมิดกีซาและสฟิงซ์ เมืองแห่งอารยธรรมโบราณอันยิ่งใหญ่",
    image_url: "https://images.unsplash.com/photo-1568322445389-f64ac2515020?auto=format&fit=crop&w=800&q=80",
    rating: 4.6, best_time: "ต.ค. - เม.ย.", currency: "ปอนด์อียิปต์ (EGP)" },
  { name: "ซิดนีย์", country: "ออสเตรเลีย", flag: "🇦🇺", continent: "oceania",
    description: "เมืองท่าสุดทันสมัย บ้านของโรงอุปรากรซิดนีย์และชายหาดโบนไดสุดชิค",
    image_url: "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best_time: "ก.ย. - พ.ย.", currency: "ดอลลาร์ออสเตรเลีย (AUD)" },
  { name: "โบราโบรา", country: "เฟรนช์โปลินีเซีย", flag: "🇵🇫", continent: "oceania",
    description: "เกาะสวรรค์กลางมหาสมุทรแปซิฟิก บ้านของบังกะโลเหนือน้ำสีเทอร์ควอยซ์",
    image_url: "https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best_time: "พ.ค. - ต.ค.", currency: "ฟรังก์ (XPF)" },
  { name: "ควีนส์ทาวน์", country: "นิวซีแลนด์", flag: "🇳🇿", continent: "oceania",
    description: "เมืองหลวงแห่งกีฬาผาดโผน ล้อมรอบด้วยภูเขาและทะเลสาบสุดตระการตา",
    image_url: "https://images.unsplash.com/photo-1589871173980-5c353e691f9c?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best_time: "ธ.ค. - ก.พ.", currency: "ดอลลาร์นิวซีแลนด์ (NZD)" },
  { name: "เรคยาวิก", country: "ไอซ์แลนด์", flag: "🇮🇸", continent: "europe",
    description: "ประตูสู่แสงเหนือ น้ำตก และธารน้ำแข็ง เมืองหลวงที่เล็กแต่เปี่ยมเสน่ห์",
    image_url: "https://images.unsplash.com/photo-1504829857797-ddff29c27927?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best_time: "มิ.ย. - ส.ค. / ก.ย. - มี.ค.", currency: "โครนาไอซ์แลนด์ (ISK)" }
];

function seedDestinations() {
  const count = db.prepare("SELECT COUNT(*) AS n FROM destinations").get().n;
  if (count > 0) {
    console.log(`Destinations already seeded (${count} rows) — skipping.`);
    return;
  }
  const insert = db.prepare(`
    INSERT INTO destinations (name, country, flag, continent, description, image_url, rating, best_time, currency)
    VALUES (@name, @country, @flag, @continent, @description, @image_url, @rating, @best_time, @currency)
  `);
  const insertMany = db.transaction((rows) => rows.forEach((row) => insert.run(row)));
  insertMany(destinations);
  console.log(`Seeded ${destinations.length} destinations.`);
}

function seedAdmin() {
  const username = process.env.ADMIN_USERNAME || "admin";
  const password = process.env.ADMIN_PASSWORD;

  const existing = db.prepare("SELECT id FROM admins WHERE username = ?").get(username);
  if (existing) {
    console.log(`Admin user "${username}" already exists — skipping.`);
    return;
  }
  if (!password) {
    console.log(
      'No ADMIN_PASSWORD set — skipping admin creation. Set ADMIN_USERNAME/ADMIN_PASSWORD in .env and re-run "npm run seed".'
    );
    return;
  }
  const hash = bcrypt.hashSync(password, 12);
  db.prepare("INSERT INTO admins (username, password_hash) VALUES (?, ?)").run(username, hash);
  console.log(`Created admin user "${username}". Remember to keep the password safe and rotate it.`);
}

seedDestinations();
seedAdmin();
