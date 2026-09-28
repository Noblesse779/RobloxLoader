const destinations = [
  {
    name: "โตเกียว", country: "ญี่ปุ่น", flag: "🇯🇵", continent: "asia",
    desc: "มหานครที่ผสมผสานเทคโนโลยีล้ำสมัยกับวัฒนธรรมดั้งเดิม เต็มไปด้วยวัด ย่านช้อปปิ้ง และอาหารระดับโลก",
    img: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best: "มี.ค. - พ.ค.", currency: "เยน (JPY)"
  },
  {
    name: "บาหลี", country: "อินโดนีเซีย", flag: "🇮🇩", continent: "asia",
    desc: "เกาะสวรรค์แห่งวัด ทุ่งนาขั้นบันได และชายหาดสุดโรแมนติก เหมาะกับทั้งพักผ่อนและผจญภัย",
    img: "https://images.unsplash.com/photo-1537996194471-e657df975ab4?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best: "เม.ย. - ต.ค.", currency: "รูเปียห์ (IDR)"
  },
  {
    name: "กรุงเทพฯ", country: "ไทย", flag: "🇹🇭", continent: "asia",
    desc: "เมืองหลวงที่มีชีวิตชีวา วัดวาอารามสวยงาม ตลาดกลางคืน และอาหารสตรีทฟู้ดระดับตำนาน",
    img: "https://images.unsplash.com/photo-1508009603885-50cf7c579365?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best: "พ.ย. - ก.พ.", currency: "บาท (THB)"
  },
  {
    name: "ปารีส", country: "ฝรั่งเศส", flag: "🇫🇷", continent: "europe",
    desc: "นครแห่งแสงสี หอไอเฟล พิพิธภัณฑ์ลูฟวร์ และร้านคาเฟ่ริมถนนที่ชวนหลงใหล",
    img: "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best: "เม.ย. - มิ.ย.", currency: "ยูโร (EUR)"
  },
  {
    name: "ซานโตรินี", country: "กรีซ", flag: "🇬🇷", continent: "europe",
    desc: "เกาะสีขาว-ฟ้าสุดคลาสสิกกลางทะเลอีเจียน ชมพระอาทิตย์ตกที่สวยที่สุดในโลก",
    img: "https://images.unsplash.com/photo-1613395877344-13d4a8e0d49e?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best: "พ.ค. - ก.ย.", currency: "ยูโร (EUR)"
  },
  {
    name: "โรม", country: "อิตาลี", flag: "🇮🇹", continent: "europe",
    desc: "นครโบราณที่มีประวัติศาสตร์กว่าสองพันปี บ้านของโคลอสเซียมและวาติกัน",
    img: "https://images.unsplash.com/photo-1552832230-c0197dd311b5?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best: "เม.ย. - มิ.ย.", currency: "ยูโร (EUR)"
  },
  {
    name: "นิวยอร์ก", country: "สหรัฐอเมริกา", flag: "🇺🇸", continent: "america",
    desc: "มหานครที่ไม่เคยหลับใหล เต็มไปด้วยตึกระฟ้า บรอดเวย์ และพิพิธภัณฑ์ระดับโลก",
    img: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best: "ก.ย. - พ.ย.", currency: "ดอลลาร์ (USD)"
  },
  {
    name: "ริโอ เดอ จาเนโร", country: "บราซิล", flag: "🇧🇷", continent: "america",
    desc: "เมืองแห่งจังหวะแซมบ้า ชายหาดโคปาคาบานา และเทือกเขาที่มีรูปปั้นพระคริสต์",
    img: "https://images.unsplash.com/photo-1483729558449-99ef09a8c325?auto=format&fit=crop&w=800&q=80",
    rating: 4.6, best: "ธ.ค. - มี.ค.", currency: "เรียล (BRL)"
  },
  {
    name: "มาชูปิกชู", country: "เปรู", flag: "🇵🇪", continent: "america",
    desc: "นครโบราณของชาวอินคาบนยอดเขาแอนดีส หนึ่งในเจ็ดสิ่งมหัศจรรย์ของโลก",
    img: "https://images.unsplash.com/photo-1587595431973-160d0d94add1?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best: "พ.ค. - ก.ย.", currency: "โซล (PEN)"
  },
  {
    name: "เคปทาวน์", country: "แอฟริกาใต้", flag: "🇿🇦", continent: "africa",
    desc: "เมืองริมทะเลสุดงดงามใต้เขาโต๊ะ รวมธรรมชาติ ไวน์ และประวัติศาสตร์ไว้ในที่เดียว",
    img: "https://images.unsplash.com/photo-1580060839134-75a5edca2e99?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best: "พ.ย. - มี.ค.", currency: "แรนด์ (ZAR)"
  },
  {
    name: "มาราเกช", country: "โมร็อกโก", flag: "🇲🇦", continent: "africa",
    desc: "เมืองสีแดงแห่งทะเลทรายซาฮารา ตลาดสุดคึกคักและพระราชวังโบราณ",
    img: "https://images.unsplash.com/photo-1489493887464-892be6d1daae?auto=format&fit=crop&w=800&q=80",
    rating: 4.5, best: "มี.ค. - พ.ค.", currency: "ดีแรห์ม (MAD)"
  },
  {
    name: "ไคโร", country: "อียิปต์", flag: "🇪🇬", continent: "africa",
    desc: "บ้านของมหาพีระมิดกีซาและสฟิงซ์ เมืองแห่งอารยธรรมโบราณอันยิ่งใหญ่",
    img: "https://images.unsplash.com/photo-1568322445389-f64ac2515020?auto=format&fit=crop&w=800&q=80",
    rating: 4.6, best: "ต.ค. - เม.ย.", currency: "ปอนด์อียิปต์ (EGP)"
  },
  {
    name: "ซิดนีย์", country: "ออสเตรเลีย", flag: "🇦🇺", continent: "oceania",
    desc: "เมืองท่าสุดทันสมัย บ้านของโรงอุปรากรซิดนีย์และชายหาดโบนไดสุดชิค",
    img: "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best: "ก.ย. - พ.ย.", currency: "ดอลลาร์ออสเตรเลีย (AUD)"
  },
  {
    name: "โบราโบรา", country: "เฟรนช์โปลินีเซีย", flag: "🇵🇫", continent: "oceania",
    desc: "เกาะสวรรค์กลางมหาสมุทรแปซิฟิก บ้านของบังกะโลเหนือน้ำสีเทอร์ควอยซ์",
    img: "https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=800&q=80",
    rating: 4.9, best: "พ.ค. - ต.ค.", currency: "ฟรังก์ (XPF)"
  },
  {
    name: "ควีนส์ทาวน์", country: "นิวซีแลนด์", flag: "🇳🇿", continent: "oceania",
    desc: "เมืองหลวงแห่งกีฬาผาดโผน ล้อมรอบด้วยภูเขาและทะเลสาบสุดตระการตา",
    img: "https://images.unsplash.com/photo-1589871173980-5c353e691f9c?auto=format&fit=crop&w=800&q=80",
    rating: 4.7, best: "ธ.ค. - ก.พ.", currency: "ดอลลาร์นิวซีแลนด์ (NZD)"
  },
  {
    name: "เรคยาวิก", country: "ไอซ์แลนด์", flag: "🇮🇸", continent: "europe",
    desc: "ประตูสู่แสงเหนือ น้ำตก และธารน้ำแข็ง เมืองหลวงที่เล็กแต่เปี่ยมเสน่ห์",
    img: "https://images.unsplash.com/photo-1504829857797-ddff29c27927?auto=format&fit=crop&w=800&q=80",
    rating: 4.8, best: "มิ.ย. - ส.ค. / ก.ย. - มี.ค.", currency: "โครนาไอซ์แลนด์ (ISK)"
  }
];

const continentLabels = {
  asia: "เอเชีย", europe: "ยุโรป", america: "อเมริกา",
  africa: "แอฟริกา", oceania: "โอเชียเนีย"
};

const cardGrid = document.getElementById("cardGrid");
const noResults = document.getElementById("noResults");
const searchInput = document.getElementById("searchInput");
const searchBtn = document.getElementById("searchBtn");
const filterBar = document.getElementById("filterBar");

let currentFilter = "all";
let currentQuery = "";

function renderCards() {
  const query = currentQuery.trim().toLowerCase();
  const filtered = destinations.filter(d => {
    const matchesFilter = currentFilter === "all" || d.continent === currentFilter;
    const matchesQuery = !query ||
      d.name.toLowerCase().includes(query) ||
      d.country.toLowerCase().includes(query);
    return matchesFilter && matchesQuery;
  });

  cardGrid.innerHTML = "";
  noResults.hidden = filtered.length > 0;

  filtered.forEach((d, i) => {
    const card = document.createElement("article");
    card.className = "dest-card";
    card.innerHTML = `
      <div class="dest-img-wrap">
        <img src="${d.img}" alt="${d.name}" loading="lazy"
             onerror="this.parentElement.style.background='linear-gradient(135deg,#0b7285,#ff6b4a)'; this.remove();">
        <span class="dest-continent-tag">${continentLabels[d.continent]}</span>
      </div>
      <div class="dest-body">
        <h3>${d.flag} ${d.name}</h3>
        <div class="dest-country">${d.country}</div>
        <p class="dest-desc">${d.desc}</p>
        <div class="dest-footer">
          <span class="dest-rating">★ ${d.rating.toFixed(1)}</span>
          <span>ดูรายละเอียด →</span>
        </div>
      </div>
    `;
    card.addEventListener("click", () => openModal(d));
    cardGrid.appendChild(card);
  });
}

filterBar.addEventListener("click", (e) => {
  const btn = e.target.closest(".filter-btn");
  if (!btn) return;
  document.querySelectorAll(".filter-btn").forEach(b => b.classList.remove("active"));
  btn.classList.add("active");
  currentFilter = btn.dataset.filter;
  renderCards();
});

searchBtn.addEventListener("click", () => {
  currentQuery = searchInput.value;
  renderCards();
  document.getElementById("destinations").scrollIntoView({ behavior: "smooth" });
});

searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") searchBtn.click();
});

// Modal
const modal = document.getElementById("modal");
const modalImage = document.getElementById("modalImage");
const modalFlag = document.getElementById("modalFlag");
const modalTitle = document.getElementById("modalTitle");
const modalDesc = document.getElementById("modalDesc");
const modalFacts = document.getElementById("modalFacts");
const modalClose = document.getElementById("modalClose");

function openModal(d) {
  modalImage.src = d.img;
  modalImage.alt = d.name;
  modalFlag.textContent = d.flag;
  modalTitle.textContent = `${d.name}, ${d.country}`;
  modalDesc.textContent = d.desc;
  modalFacts.innerHTML = `
    <li><strong>ทวีป</strong>${continentLabels[d.continent]}</li>
    <li><strong>คะแนนรีวิว</strong>★ ${d.rating.toFixed(1)}</li>
    <li><strong>ช่วงเวลาที่ดีที่สุด</strong>${d.best}</li>
    <li><strong>สกุลเงิน</strong>${d.currency}</li>
  `;
  modal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeModal() {
  modal.hidden = true;
  document.body.style.overflow = "";
}

modalClose.addEventListener("click", closeModal);
modal.addEventListener("click", (e) => { if (e.target === modal) closeModal(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeModal(); });

// Nav toggle (mobile)
const navToggle = document.getElementById("navToggle");
const navLinks = document.querySelector(".nav-links");
navToggle.addEventListener("click", () => navLinks.classList.toggle("open"));
navLinks.querySelectorAll("a").forEach(a =>
  a.addEventListener("click", () => navLinks.classList.remove("open"))
);

// Newsletter form
const newsletterForm = document.getElementById("newsletterForm");
const formMessage = document.getElementById("formMessage");
newsletterForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const email = document.getElementById("emailInput").value;
  formMessage.textContent = `ขอบคุณ! เราจะส่งแรงบันดาลใจการเดินทางไปที่ ${email}`;
  newsletterForm.reset();
});

renderCards();
