const state = { challengeToken: null, user: null, view: "overview" };
const login = document.querySelector("#login");
const workspace = document.querySelector("#workspace");
const content = document.querySelector("#content");
const statusLine = document.querySelector("#status");
const days = document.querySelector("#days");

const escapeHTML = (value) => String(value ?? "").replace(/[&<>'"]/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
})[character]);

const csrfToken = () => document.cookie.split(";").map((item) => item.trim())
  .find((item) => item.startsWith("bikegogogo_admin_csrf="))?.split("=").slice(1).join("=");

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "content-type": "application/json",
      ...(options.method && options.method !== "GET" ? { "x-csrf-token": decodeURIComponent(csrfToken() ?? "") } : {}),
      ...options.headers
    }
  });
  if (response.status === 401) showLogin();
  const body = response.status === 204 ? null : await response.json();
  if (!response.ok) throw new Error(body?.message || body?.error || "请求失败");
  return body;
}

function showLogin() {
  login.hidden = false;
  workspace.hidden = true;
  state.user = null;
}

function showWorkspace(user) {
  state.user = user;
  login.hidden = true;
  workspace.hidden = false;
  document.querySelector("#admin-name").textContent = `${user.username} · ${user.role}`;
  document.querySelectorAll(".admin-only").forEach((item) => item.hidden = user.role !== "admin");
}

document.querySelector("#login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const error = document.querySelector("#login-error");
  const submit = document.querySelector("#login-submit");
  error.textContent = "";
  submit.disabled = true;
  try {
    if (!state.challengeToken) {
      const result = await api("/admin/api/v1/auth/login", {
        method: "POST",
        body: JSON.stringify({
          username: document.querySelector("#username").value,
          password: document.querySelector("#password").value
        })
      });
      state.challengeToken = result.challengeToken;
      document.querySelector("#totp-row").hidden = false;
      document.querySelector("#totp").required = true;
      document.querySelector("#totp").focus();
      submit.textContent = "验证并登录";
    } else {
      const result = await api("/admin/api/v1/auth/totp/verify", {
        method: "POST",
        body: JSON.stringify({
          challengeToken: state.challengeToken,
          code: document.querySelector("#totp").value
        })
      });
      state.challengeToken = null;
      showWorkspace(result.user);
      await loadView();
    }
  } catch (failure) {
    error.textContent = failure.message;
    if (state.challengeToken) {
      state.challengeToken = null;
      document.querySelector("#totp-row").hidden = true;
      submit.textContent = "继续";
    }
  } finally {
    submit.disabled = false;
  }
});

const kpi = (label, value, unit = "") => `
  <article class="kpi"><div class="label">${escapeHTML(label)}</div>
  <div class="value">${escapeHTML(value)}<span class="unit">${escapeHTML(unit)}</span></div></article>`;

const metricList = (items) => `<dl class="metric-list">${items.map(([label, value]) =>
  `<div><dt>${escapeHTML(label)}</dt><dd>${escapeHTML(value)}</dd></div>`).join("")}</dl>`;

const bars = (series) => {
  const max = Math.max(1, ...series.map((item) => Number(item.value)));
  return `<div class="bar-chart">${series.map((item) => {
    const height = Math.max(2, Number(item.value) / max * 100);
    return `<div class="bar" style="height:${height}%" data-tip="${escapeHTML(item.date)} · ${escapeHTML(item.value)}"></div>`;
  }).join("")}</div>`;
};

const panel = (title, body) => `<section class="panel"><h2>${escapeHTML(title)}</h2>${body}</section>`;
const dateTime = (value) => new Intl.DateTimeFormat("zh-CN", {
  dateStyle: "medium", timeStyle: "short", hour12: false
}).format(new Date(value));

async function renderOverview() {
  const data = await api(`/admin/api/v1/overview?days=${days.value}`);
  const k = data.kpis;
  content.innerHTML = `
    <div class="kpi-grid">
      ${kpi("累计用户", k.totalUsers, "人")}${kpi("新增用户", k.newUsers, "人")}
      ${kpi("DAU / MAU", `${k.dau} / ${k.mau}`, "人")}${kpi("有效骑行", k.validRides, "次")}
      ${kpi("总里程", k.totalDistanceKilometers, "km")}${kpi("移动时长", k.totalMovingHours, "小时")}
      ${kpi("Watch 骑行占比", k.watchRidePercent, "%")}${kpi("语音响应率", k.voiceResponsePercent, "%")}
    </div>
    <div class="panel-grid">
      ${panel("新增用户趋势", bars(data.series.registrations))}
      ${panel("有效骑行趋势", bars(data.series.rides))}
    </div>
    ${panel("数据状态", metricList([
      ["业务数据更新时间", dateTime(data.freshness.businessStateUpdatedAt)],
      ["业务状态修订号", data.freshness.revision],
      ["已累计运营事件", data.quality.total],
      ["事件错误数", data.quality.errors],
      ["API p95", data.quality.p95Milliseconds ? `${Math.round(data.quality.p95Milliseconds)} ms` : "暂无"]
    ]))}`;
  statusLine.textContent = `统计范围 ${dateTime(data.period.from)} 至 ${dateTime(data.period.to)}`;
}

async function renderRides() {
  const data = await api(`/admin/api/v1/rides?days=${days.value}`);
  content.innerHTML = `
    <div class="kpi-grid">
      ${kpi("上传记录", data.totals.uploaded, "条")}${kpi("有效骑行", data.totals.valid, "次")}
      ${kpi("总里程", data.totals.totalDistanceKilometers, "km")}${kpi("移动时长", data.totals.totalMovingHours, "小时")}
      ${kpi("平均里程", data.totals.averageDistanceKilometers, "km")}${kpi("平均时长", data.totals.averageMovingMinutes, "分钟")}
      ${kpi("轨迹覆盖", data.coverage.trackPercent, "%")}${kpi("心率覆盖", data.coverage.heartRatePercent, "%")}
    </div>
    <div class="panel-grid">
      ${panel("记录来源", metricList(data.sources.map((item) => [item.label, `${item.count} 次`])))}
      ${panel("距离分布", metricList(data.distanceBuckets.map((item) => [item.label, `${item.count} 次`])))}
    </div>
    ${panel("骑行趋势", bars(data.series))}`;
  statusLine.textContent = `业务数据更新于 ${dateTime(data.freshness)}`;
}

async function renderSocial() {
  const data = await api(`/admin/api/v1/social?days=${days.value}`);
  content.innerHTML = `
    <div class="kpi-grid">
      ${kpi("好友关系", data.friends.relationships, "对")}${kpi("好友申请", data.friends.sent, "次")}
      ${kpi("小队总数", data.groups.total, "个")}${kpi("平均成员", data.groups.averageMembers, "人")}
      ${kpi("语音邀请", data.voice.invitations, "次")}${kpi("语音响应率", data.voice.responsePercent, "%")}
      ${kpi("生产推送设备", data.push.production, "台")}${kpi("测试推送设备", data.push.sandbox, "台")}
    </div>
    <div class="panel-grid">
      ${panel("好友申请", metricList([
        ["已接受", data.friends.accepted], ["已拒绝", data.friends.rejected], ["待处理", data.friends.pending]
      ]))}
      ${panel("语音邀请", metricList([
        ["好友语音", data.voice.friendInvitations], ["小队语音", data.voice.groupInvitations],
        ["有响应", data.voice.responded], ["已取消", data.voice.cancelled]
      ]))}
    </div>`;
  statusLine.textContent = `业务数据更新于 ${dateTime(data.freshness)}`;
}

async function renderQuality() {
  const data = await api(`/admin/api/v1/quality?days=${days.value}`);
  content.innerHTML = `
    <div class="kpi-grid">
      ${kpi("运营事件", data.total, "条")}${kpi("错误事件", data.errors, "条")}
      ${kpi("错误率", data.errorRatePercent, "%")}${kpi("API p95", data.p95Milliseconds ? Math.round(data.p95Milliseconds) : "暂无", data.p95Milliseconds ? "ms" : "")}
    </div>
    ${panel("事件分布", data.events.length ? metricList(data.events.map((item) => [item.name, item.count])) : '<p class="empty">尚未收到运营事件</p>')}`;
  statusLine.textContent = data.note;
}

const userRows = (users) => users.map((user) => `<tr>
  <td><button class="user-link" data-user-id="${escapeHTML(user.id)}">${escapeHTML(user.displayName)}</button></td><td>${escapeHTML(user.friendCode)}</td>
  <td><span class="badge">${escapeHTML(user.authProvider)}</span></td>
  <td>${escapeHTML(dateTime(user.createdAt))}</td><td>${escapeHTML(user.rideCount)}</td>
  <td>${escapeHTML(user.totalDistanceKilometers)} km</td><td>${escapeHTML(user.friendCount)}</td>
  <td>${escapeHTML(user.groupCount)}</td>
</tr>`).join("");

async function renderUsers(query = "") {
  const data = await api(`/admin/api/v1/users?q=${encodeURIComponent(query)}&page=1&pageSize=50`);
  content.innerHTML = `
    <section id="user-detail" class="panel" hidden></section>
    <section class="panel">
      <div class="table-toolbar"><input id="user-query" value="${escapeHTML(query)}" placeholder="按用户 ID、好友码或昵称搜索"><button id="user-search" class="secondary">搜索</button></div>
      <div class="table-wrap"><table><thead><tr><th>昵称</th><th>好友码</th><th>账户</th><th>注册时间</th><th>骑行</th><th>里程</th><th>好友</th><th>小队</th></tr></thead>
      <tbody>${userRows(data.users)}</tbody></table></div>
    </section>`;
  statusLine.textContent = `共找到 ${data.total} 位用户，敏感身份、位置和健康明细已隐藏。`;
  document.querySelector("#user-search").addEventListener("click", () => renderUsers(document.querySelector("#user-query").value));
  document.querySelector("#user-query").addEventListener("keydown", (event) => {
    if (event.key === "Enter") renderUsers(event.currentTarget.value);
  });
  document.querySelectorAll(".user-link").forEach((button) => button.addEventListener("click", async () => {
    const detail = document.querySelector("#user-detail");
    detail.hidden = false;
    detail.innerHTML = '<p class="empty">正在读取用户摘要...</p>';
    try {
      const result = await api(`/admin/api/v1/users/${encodeURIComponent(button.dataset.userId)}`);
      const user = result.user;
      detail.innerHTML = `<div class="panel-heading"><h2>${escapeHTML(user.displayName)}</h2><button id="close-user-detail" class="icon-button" aria-label="关闭用户摘要">×</button></div>
        ${metricList([
          ["好友码", user.friendCode], ["账户类型", user.authProvider],
          ["注册时间", dateTime(user.createdAt)], ["最近更新", dateTime(user.updatedAt)],
          ["骑行记录", `${user.rideCount} 条`], ["累计里程", `${user.totalDistanceKilometers} km`],
          ["好友关系", `${user.friendCount} 位`], ["所在小队", `${user.groupCount} 个`],
          ["有效会话", `${user.activeSessionCount} 个`]
        ])}`;
      document.querySelector("#close-user-detail").addEventListener("click", () => { detail.hidden = true; });
      detail.scrollIntoView({ behavior: "smooth", block: "start" });
    } catch (error) {
      detail.innerHTML = `<p class="empty">${escapeHTML(error.message)}</p>`;
    }
  }));
}

async function renderAudit() {
  const data = await api("/admin/api/v1/audit-logs");
  content.innerHTML = panel("最近 100 条审计记录", `<div class="table-wrap"><table><thead><tr><th>时间</th><th>管理员</th><th>操作</th><th>对象</th><th>结果</th></tr></thead><tbody>${data.logs.map((log) => `<tr>
    <td>${escapeHTML(dateTime(log.createdAt))}</td><td>${escapeHTML(log.username || "系统")}</td>
    <td>${escapeHTML(log.action)}</td><td>${escapeHTML(log.targetType || "-")} ${escapeHTML(log.targetId || "")}</td>
    <td><span class="badge ${log.result === "failure" ? "error" : ""}">${escapeHTML(log.result)}</span></td>
  </tr>`).join("")}</tbody></table></div>`);
  statusLine.textContent = "管理员登录和用户支持查询均会留痕。";
}

const views = {
  overview: ["运营总览", renderOverview], rides: ["骑行运营", renderRides],
  social: ["好友与小队", renderSocial], quality: ["应用质量", renderQuality],
  users: ["用户支持", renderUsers], audit: ["审计日志", renderAudit]
};

async function loadView() {
  content.innerHTML = '<p class="empty">正在读取运营数据...</p>';
  statusLine.textContent = "";
  document.querySelector("#page-title").textContent = views[state.view][0];
  try { await views[state.view][1](); }
  catch (error) { content.innerHTML = `<p class="empty">${escapeHTML(error.message)}</p>`; }
}

document.querySelectorAll(".nav-item").forEach((button) => button.addEventListener("click", () => {
  document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
  button.classList.add("active");
  state.view = button.dataset.view;
  void loadView();
}));
document.querySelector("#refresh").addEventListener("click", () => loadView());
days.addEventListener("change", () => loadView());
document.querySelector("#logout").addEventListener("click", async () => {
  try { await api("/admin/api/v1/auth/session", { method: "DELETE" }); } finally { showLogin(); }
});

api("/admin/api/v1/auth/me").then((result) => {
  showWorkspace(result.user);
  return loadView();
}).catch(showLogin);
