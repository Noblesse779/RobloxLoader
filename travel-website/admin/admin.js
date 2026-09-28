const continentLabels = {
  asia: "เอเชีย", europe: "ยุโรป", america: "อเมริกา",
  africa: "แอฟริกา", oceania: "โอเชียเนีย"
};

async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  let body = null;
  const text = await res.text();
  if (text) {
    try { body = JSON.parse(text); } catch { body = null; }
  }
  if (!res.ok) {
    const error = new Error((body && body.error) || `HTTP ${res.status}`);
    error.status = res.status;
    throw error;
  }
  return body;
}

// ---------- Login page ----------
const loginForm = document.getElementById("loginForm");
if (loginForm) {
  const message = document.getElementById("message");

  api("/api/auth/me").then(() => {
    window.location.href = "/admin/dashboard.html";
  }).catch(() => {});

  loginForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    message.textContent = "";
    const username = document.getElementById("username").value.trim();
    const password = document.getElementById("password").value;
    try {
      await api("/api/auth/login", {
        method: "POST",
        body: JSON.stringify({ username, password }),
      });
      window.location.href = "/admin/dashboard.html";
    } catch (err) {
      message.textContent = err.message || "เข้าสู่ระบบไม่สำเร็จ";
    }
  });
}

// ---------- Dashboard page ----------
const destTableBody = document.getElementById("destTableBody");
if (destTableBody) {
  const whoami = document.getElementById("whoami");
  const destCount = document.getElementById("destCount");
  const listMessage = document.getElementById("listMessage");
  const logoutBtn = document.getElementById("logoutBtn");
  const addBtn = document.getElementById("addBtn");

  const formOverlay = document.getElementById("formOverlay");
  const formClose = document.getElementById("formClose");
  const cancelBtn = document.getElementById("cancelBtn");
  const destForm = document.getElementById("destForm");
  const formTitle = document.getElementById("formTitle");
  const formMessage = document.getElementById("formMessage");
  const destIdInput = document.getElementById("destId");

  const fieldIds = ["name", "flag", "country", "continent", "description", "image_url", "rating", "best_time", "currency"];

  async function requireLogin() {
    try {
      const me = await api("/api/auth/me");
      whoami.textContent = `👤 ${me.username}`;
    } catch {
      window.location.href = "/admin/";
    }
  }

  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str ?? "";
    return div.innerHTML;
  }

  async function loadDestinations() {
    listMessage.textContent = "";
    try {
      const rows = await api("/api/destinations");
      destCount.textContent = rows.length;
      destTableBody.innerHTML = rows.map(d => `
        <tr>
          <td>${escapeHtml(d.flag)} ${escapeHtml(d.name)}</td>
          <td>${escapeHtml(d.country)}</td>
          <td>${escapeHtml(continentLabels[d.continent] || d.continent)}</td>
          <td>★ ${Number(d.rating).toFixed(1)}</td>
          <td class="row-actions">
            <button class="icon-btn" data-edit="${d.id}">แก้ไข</button>
            <button class="icon-btn danger" data-delete="${d.id}">ลบ</button>
          </td>
        </tr>
      `).join("");
      destTableBody.dataset.rows = JSON.stringify(rows);
    } catch (err) {
      listMessage.textContent = err.message || "โหลดข้อมูลไม่สำเร็จ";
    }
  }

  function openForm(dest) {
    formMessage.textContent = "";
    destForm.reset();
    if (dest) {
      formTitle.textContent = "แก้ไขสถานที่";
      destIdInput.value = dest.id;
      fieldIds.forEach(id => {
        if (document.getElementById(id)) document.getElementById(id).value = dest[id] ?? "";
      });
    } else {
      formTitle.textContent = "เพิ่มสถานที่ใหม่";
      destIdInput.value = "";
    }
    formOverlay.hidden = false;
  }

  function closeForm() { formOverlay.hidden = true; }

  addBtn.addEventListener("click", () => openForm(null));
  formClose.addEventListener("click", closeForm);
  cancelBtn.addEventListener("click", closeForm);
  formOverlay.addEventListener("click", (e) => { if (e.target === formOverlay) closeForm(); });

  destTableBody.addEventListener("click", (e) => {
    const editId = e.target.dataset.edit;
    const deleteId = e.target.dataset.delete;
    if (editId) {
      const rows = JSON.parse(destTableBody.dataset.rows || "[]");
      const dest = rows.find(r => String(r.id) === editId);
      if (dest) openForm(dest);
    } else if (deleteId) {
      handleDelete(deleteId);
    }
  });

  async function handleDelete(id) {
    if (!confirm("ยืนยันการลบสถานที่นี้หรือไม่?")) return;
    try {
      await api(`/api/destinations/${id}`, { method: "DELETE" });
      await loadDestinations();
    } catch (err) {
      listMessage.textContent = err.message || "ลบไม่สำเร็จ";
    }
  }

  destForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    formMessage.textContent = "";
    const payload = {};
    fieldIds.forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      payload[id] = id === "rating" ? Number(el.value) : el.value.trim();
    });

    const id = destIdInput.value;
    try {
      if (id) {
        await api(`/api/destinations/${id}`, { method: "PUT", body: JSON.stringify(payload) });
      } else {
        await api("/api/destinations", { method: "POST", body: JSON.stringify(payload) });
      }
      closeForm();
      await loadDestinations();
    } catch (err) {
      formMessage.textContent = err.message || "บันทึกไม่สำเร็จ";
    }
  });

  logoutBtn.addEventListener("click", async () => {
    await api("/api/auth/logout", { method: "POST" }).catch(() => {});
    window.location.href = "/admin/";
  });

  requireLogin().then(loadDestinations);
}
