const continentLabels = {
  asia: "เอเชีย", europe: "ยุโรป", america: "อเมริกา",
  africa: "แอฟริกา", oceania: "โอเชียเนีย"
};

const cardGrid = document.getElementById("cardGrid");
const noResults = document.getElementById("noResults");
const searchInput = document.getElementById("searchInput");
const searchBtn = document.getElementById("searchBtn");
const filterBar = document.getElementById("filterBar");

let destinations = [];
let currentFilter = "all";
let currentQuery = "";

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str ?? "";
  return div.innerHTML;
}

async function loadDestinations() {
  try {
    const res = await fetch("/api/destinations");
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    destinations = await res.json();
  } catch (err) {
    cardGrid.innerHTML = `<p class="no-results">โหลดข้อมูลไม่สำเร็จ กรุณาลองใหม่ภายหลัง</p>`;
    console.error("Failed to load destinations:", err);
    return;
  }
  renderCards();
}

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

  filtered.forEach((d) => {
    const card = document.createElement("article");
    card.className = "dest-card";
    card.innerHTML = `
      <div class="dest-img-wrap">
        <img src="${escapeHtml(d.image_url)}" alt="${escapeHtml(d.name)}" loading="lazy"
             onerror="this.parentElement.style.background='linear-gradient(135deg,#0b7285,#ff6b4a)'; this.remove();">
        <span class="dest-continent-tag">${escapeHtml(continentLabels[d.continent] || d.continent)}</span>
      </div>
      <div class="dest-body">
        <h3>${escapeHtml(d.flag)} ${escapeHtml(d.name)}</h3>
        <div class="dest-country">${escapeHtml(d.country)}</div>
        <p class="dest-desc">${escapeHtml(d.description)}</p>
        <div class="dest-footer">
          <span class="dest-rating">★ ${Number(d.rating).toFixed(1)}</span>
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
  modalImage.src = d.image_url;
  modalImage.alt = d.name;
  modalFlag.textContent = d.flag;
  modalTitle.textContent = `${d.name}, ${d.country}`;
  modalDesc.textContent = d.description;
  modalFacts.innerHTML = `
    <li><strong>ทวีป</strong>${escapeHtml(continentLabels[d.continent] || d.continent)}</li>
    <li><strong>คะแนนรีวิว</strong>★ ${Number(d.rating).toFixed(1)}</li>
    <li><strong>ช่วงเวลาที่ดีที่สุด</strong>${escapeHtml(d.best_time)}</li>
    <li><strong>สกุลเงิน</strong>${escapeHtml(d.currency)}</li>
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

loadDestinations();
