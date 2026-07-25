'use strict';

// forge kontrol paneli — istemci.
//
// Sunucu localhost'a bağlı ve kabuk komutu çalıştırır; bu yüzden tehlikeli
// işler (gerçek yayın) hem burada onay ister hem de sunucuda confirm=YAYINLA
// olmadan reddedilir. İki katman bilinçlidir: tarayıcıdaki onay tek başına
// güvenilmez.

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

const state = {
  base: null,
  projects: [],
  selected: null, // seçili projenin path'i
  running: false, // bir SSE işi sürüyor mu
  es: null, // aktif EventSource
};

// ---------------------------------------------------------------- projeler

async function loadProjects() {
  const list = $('#project-list');
  try {
    const res = await fetch('api/projects');
    const data = await res.json();
    state.base = data.base;
    state.projects = data.projects || [];
    $('#base-path').textContent = data.base;
  } catch (e) {
    list.innerHTML = `<li class="muted pad">Sunucuya ulaşılamadı: ${esc(e)}</li>`;
    return;
  }

  if (state.projects.length === 0) {
    list.innerHTML = `<li class="muted pad">Bu dizinde Flutter projesi yok.<br>Yeni bir tane başlatın.</li>`;
    return;
  }

  list.innerHTML = '';
  for (const p of state.projects) {
    const li = document.createElement('li');
    li.className = 'project-item' + (p.path === state.selected ? ' active' : '');
    li.dataset.path = p.path;
    li.innerHTML = `
      <div class="pi-name">${esc(p.label || p.name)}</div>
      <div class="pi-meta">
        <span>${esc(p.version || '—')}</span>
        <span class="pi-dot ${p.hasIos ? '' : 'off'}">iOS</span>
        <span class="pi-dot ${p.hasAndroid ? '' : 'off'}">And</span>
        ${p.usesAds ? '<span class="pi-dot">Ads</span>' : ''}
      </div>`;
    li.addEventListener('click', () => selectProject(p.path));
    list.appendChild(li);
  }
}

function selectProject(path) {
  state.selected = path;
  const p = state.projects.find((x) => x.path === path);
  if (!p) return;

  $$('.project-item').forEach((el) =>
    el.classList.toggle('active', el.dataset.path === path));

  $('#empty-state').hidden = true;
  $('#project-view').hidden = false;
  showTab('actions'); // proje değişince eyleme dön
  loadReadiness();
  // Yayın onayındaki ön-uçuş uyarıları için ilerleme baştan yüklenir —
  // kullanıcı Yol Haritası sekmesini hiç açmasa bile.
  loadGuideProgress();

  $('#pv-name').textContent = p.label || p.name;
  $('#pv-sub').textContent = `${p.appName || ''}  ·  ${p.path}`;

  const badges = [];
  badges.push(badge(p.version || 'sürüm yok', p.version ? 'on' : ''));
  if (p.hasIos) badges.push(badge('iOS', 'on'));
  if (p.hasAndroid) badges.push(badge('Android', 'on'));
  badges.push(badge(p.usesAds ? 'Reklamlı' : 'Reklamsız', p.usesAds ? 'on' : ''));
  badges.push(badge(p.hasDeploy ? 'deploy.sh ✓' : 'deploy.sh yok',
    p.hasDeploy ? 'ok' : 'warn'));
  $('#pv-badges').innerHTML = badges.join('');

  // Proje değişince eski doctor sonuçlarını gizle.
  $('#doctor-panel').hidden = true;
}

function badge(text, cls = '') {
  return `<span class="badge ${cls}">${esc(text)}</span>`;
}

// ----------------------------------------------------------- yayına hazırlık

async function loadReadiness() {
  const el = $('#readiness');
  el.innerHTML = '<p class="muted small">Yayına hazırlık kontrol ediliyor…</p>';
  let d;
  try {
    d = await (await fetch('api/readiness?path=' + enc(state.selected))).json();
  } catch (e) { el.innerHTML = ''; return; }
  if (d.error) { el.innerHTML = ''; return; }
  state.readiness = d; // Yol Haritası da aynı veriden beslenir

  const icon = { ok: '✓', warn: '⚠', block: '✗', todo: '○' };
  const row = (g) => `
    <li class="rd-row rd-${g.status}">
      <span class="rd-icon">${icon[g.status] || '○'}</span>
      <span class="rd-label">${esc(g.label)}<small>${esc(g.hint)}</small></span>
      <button class="ghost rd-jump" data-jump="${esc(g.jump)}">Git →</button>
    </li>`;

  // Her platformun KENDİ hükmü var: iOS hazırsa Android'i beklemez.
  const cols = Object.values(d.platforms || {}).map((pl) => {
    const v = pl.blockers > 0
      ? `<span class="rd-verdict block">${pl.blockers} engel</span>`
      : (pl.remaining > 0
          ? `<span class="rd-verdict warn">${pl.remaining} madde</span>`
          : '<span class="rd-verdict ok">✓ hazır</span>');
    return `
      <div class="rd-col">
        <div class="rd-col-head"><strong>${esc(pl.title)}</strong>${v}</div>
        <ul class="rd-list">${pl.gates.map(row).join('')}</ul>
      </div>`;
  }).join('');

  const common = (d.common || []).map(row).join('');

  el.innerHTML = `
    <div class="rd-head"><strong>Yayına hazırlık</strong>
      <span class="muted small">iOS ve Android ayrı değerlendirilir</span></div>
    ${common ? `<ul class="rd-list rd-common">${common}</ul>` : ''}
    <div class="rd-cols">${cols}</div>`;

  $$('#readiness .rd-jump').forEach((b) =>
    b.addEventListener('click', () => jumpTo(b.dataset.jump)));
}

function jumpTo(where) {
  switch (where) {
    case 'doctor':
      showTab('actions');
      runDoctor();
      $('#doctor-panel').scrollIntoView({ behavior: 'smooth' });
      break;
    case 'account':
      openAccountDialog();
      break;
    case 'icon':
    case 'config':
      showTab('config');
      setTimeout(() => {
        const t = where === 'icon' ? $('#icon-file') : $('#config-view .cfg-group');
        if (t) t.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 100);
      break;
  }
}

// ------------------------------------------------------------------ doctor

async function runDoctor() {
  const path = state.selected;
  if (!path) return;
  const panel = $('#doctor-panel');
  const summary = $('#doctor-summary');
  const findings = $('#findings');
  panel.hidden = false;
  summary.innerHTML = '<span class="muted">Denetleniyor…</span>';
  findings.innerHTML = '';

  let data;
  try {
    const res = await fetch('api/doctor?path=' + encodeURIComponent(path));
    data = await res.json();
  } catch (e) {
    summary.innerHTML = `<span class="stat blk">Hata: ${esc(e)}</span>`;
    return;
  }
  if (data.error) {
    summary.innerHTML = `<span class="stat blk">${esc(data.error)}</span>`;
    return;
  }

  const s = data.summary;
  summary.innerHTML = `
    <span class="verdict ${s.ready ? 'ready' : 'blocked'}">
      ${s.ready ? '✓ Yayına hazır' : '✗ Engelli'}
    </span>
    <span class="stat blk">${s.blockers} engel</span>
    <span class="stat warn">${s.warnings} uyarı</span>
    ${s.autoFixable ? `<span class="stat">${s.autoFixable} otomatik düzeltilebilir</span>` : ''}`;

  if (!data.findings.length) {
    findings.innerHTML = '<li class="muted pad">Hiç bulgu yok — tertemiz. 🎉</li>';
    return;
  }
  // Ciddiyete göre sırala: engel > uyarı > bilgi.
  const order = { blocker: 0, warning: 1, info: 2 };
  data.findings.sort((a, b) => order[a.severity] - order[b.severity]);

  const findingRow = (f) => `
    <li class="finding ${f.severity}">
      <div class="f-top">
        <span class="f-sev ${f.severity}">${esc(f.severityLabel)}</span>
        <span class="f-tag">${esc(f.source)}</span>
        ${f.autoFixable ? '<span class="f-tag">🩹 auto</span>' : ''}
        <span class="f-title">${esc(f.title)}</span>
      </div>
      <p class="f-why"><strong>Neden:</strong> ${esc(f.why)}</p>
      <p class="f-fix"><strong>Nasıl:</strong> ${esc(f.fix)}</p>
    </li>`;

  // Platforma göre grupla: iOS yayınına gidenle Android'e giden karışmasın.
  const sections = [
    ['ios', '🍎 iOS'],
    ['android', '🤖 Android'],
    ['both', '⚙ Ortak (iki platformu da etkiler)'],
  ];
  findings.innerHTML = sections.map(([key, title]) => {
    const list = data.findings.filter((f) => f.platform === key);
    if (!list.length) return '';
    return `<li class="f-section">${title}</li>` + list.map(findingRow).join('');
  }).join('');
}

// ------------------------------------------------------------ SSE / konsol

function openConsole(title) {
  $('#console-wrap').hidden = false;
  $('#console-title').textContent = title;
  const st = $('#console-status');
  st.textContent = 'çalışıyor…';
  st.className = 'status running';
  const c = $('#console');
  c.classList.remove('idle'); // açılıştaki "henüz işlem yok" yer tutucusu
  c.textContent = '';
  $('#console-wrap').scrollIntoView({ behavior: 'smooth', block: 'end' });
}

function log(text) {
  const el = $('#console');
  el.textContent += text + '\n';
  el.scrollTop = el.scrollHeight;
}

// Yüzen işlem rozeti: konsol ekran dışında kalsa bile işlemin sürdüğü ve
// sonucu (✓/✗) her zaman görünür. Tıklayınca konsola iner.
let _pillTimer = null;
function runPill(kind, text) {
  const pill = $('#run-pill');
  clearTimeout(_pillTimer);
  pill.hidden = false;
  pill.className = kind; // running | ok | fail
  $('#run-pill-text').textContent = text;
  // Başarı kendiliğinden kaybolur; hata, kullanıcı görene kadar kalır.
  if (kind === 'ok') {
    _pillTimer = setTimeout(() => { pill.hidden = true; }, 6000);
  }
}
function hideRunPill() {
  clearTimeout(_pillTimer);
  $('#run-pill').hidden = true;
}

// Bir SSE ucunu açar ve konsola akıtır. Bittiğinde projeleri tazeler.
function stream(url, title) {
  if (state.running) {
    // alert() KULLANMA: kip pencere JS'i dondurur ve akan SSE satırlarının
    // işlenmesini de durdurur — konsol "takıldı" gibi görünürdü.
    runPill('fail', 'Başka bir işlem çalışıyor — bitmesini bekleyin');
    _pillTimer = setTimeout(() => {
      if (state.running) runPill('running', $('#console-title').textContent);
      else hideRunPill();
    }, 3000);
    return;
  }
  state.running = true;
  setBusy(true);
  openConsole(title);
  runPill('running', title);

  const es = new EventSource(url);
  state.es = es;

  es.addEventListener('start', (e) => {
    const d = JSON.parse(e.data);
    log(`$ ${d.cmd}`);
    log(`  (${d.cwd})\n`);
  });
  es.addEventListener('line', (e) => log(JSON.parse(e.data).text));
  es.addEventListener('done', (e) => {
    const d = JSON.parse(e.data);
    const st = $('#console-status');
    st.textContent = d.ok ? '✓ tamamlandı' : `✗ hata (kod ${d.code})`;
    st.className = 'status ' + (d.ok ? 'ok' : 'fail');
    runPill(d.ok ? 'ok' : 'fail',
      (d.ok ? '✓ ' : '✗ ') + $('#console-title').textContent
        + (d.ok ? ' — tamamlandı' : ' — HATA (konsola bak)'));
    finishStream();
    if (d.ok) {
      loadProjects();
      // İş (fix/ikon/deploy) durumu değiştirmiş olabilir — kart bayat kalmasın.
      if (state.selected) loadReadiness();
      // GitHub girişi yeni tamamlanmış olabilir — uyarıyı tazele.
      checkGithub();
    }
  });
  es.onerror = () => {
    // done geldiyse sunucu akışı zaten kapattı; bu normal kapanış olabilir.
    if (state.running) {
      const st = $('#console-status');
      if (st.className.indexOf('running') !== -1) {
        st.textContent = '✗ bağlantı kesildi';
        st.className = 'status fail';
        runPill('fail', '✗ ' + $('#console-title').textContent
          + ' — bağlantı kesildi');
      }
      finishStream();
    }
  };
}

function finishStream() {
  if (state.es) { state.es.close(); state.es = null; }
  state.running = false;
  setBusy(false);
}

function setBusy(busy) {
  $$('#project-view button[data-act]').forEach((b) => (b.disabled = busy));
  $('#new-app-btn').disabled = busy;
}

// ------------------------------------------------------------- eylemler

const enc = encodeURIComponent;

function act(which) {
  const path = state.selected;
  if (!path) return;
  const q = 'path=' + enc(path);

  switch (which) {
    case 'doctor':
      return runDoctor();
    case 'fix-dry':
      return stream('api/fix?' + q, 'Düzeltme (deneme)');
    case 'fix-apply':
      return confirmThen({
        title: 'Düzeltmeleri uygula',
        body: 'forge fix diske yazacak. Yalnızca tek doğru cevabı olan '
          + 'düzeltmeleri uygular (imzalama/kimlik kararlarına dokunmaz).',
      }, () => stream('api/fix?' + q + '&apply=1', 'Düzeltmeler uygulanıyor'));
    case 'update':
      return stream('api/update?' + q, 'flutter pub get');
    case 'upgrade':
      return stream('api/update?' + q + '&upgrade=1', 'flutter pub upgrade');
    // Platform başına ayrı akış: Android'deki bir eksik iOS yayınını
    // bekletmesin (ve tersi).
    case 'build-ios':
      return stream(`api/deploy?${q}&platform=ios&lane=beta`,
        'Build (deneme · iOS)');
    case 'build-android':
      return stream(`api/deploy?${q}&platform=android&lane=beta`,
        'Build (deneme · Android)');
    case 'beta-ios':
      return confirmPublish('beta', 'ios');
    case 'beta-android':
      return confirmPublish('beta', 'android');
    case 'release-ios':
      return confirmPublish('release', 'ios');
    case 'release-android':
      return confirmPublish('release', 'android');
  }
}

function confirmPublish(lane, plat) {
  const path = state.selected;
  const target = lane === 'beta'
    ? (plat === 'android' ? 'Play Store Beta' : 'TestFlight')
    : (plat === 'android' ? 'Play Store Production (taslak)' : 'App Store');

  let body = lane === 'beta'
    ? `<strong>${target}</strong> hedefine gerçek bir yükleme yapılacak `
      + `(${plat}). Testçilere ulaşır; mağazada herkese açılmaz. `
      + `Build numarası artar.`
    : `Build <strong>${target}</strong> hesabına yüklenecek (${plat}). `
      + `<strong>Yayınlanmaz ve incelemeye gönderilmez</strong> — o adımı `
      + `konsolda sen yaparsın. Build numarası artar.`;

  // Ön-uçuş: Yol Haritası'ndaki elle adımlar atlanmışsa build turunu
  // harcamadan ÖNCE uyar. Engellemez — karar insanın; ama sessiz kalmaz.
  const prog = state.guideProgress || {};
  const pre = [];
  if (plat === 'ios' && !prog.p5_asc_record) {
    pre.push('Yol Haritası 5: "App Store Connect\'te uygulama kaydı" işaretli '
      + 'değil — kayıt yoksa yükleme reddedilir.');
  }
  if (plat === 'android' && !prog.p5_play_record) {
    pre.push('Yol Haritası 5: "Play Console\'da uygulama kaydı" işaretli '
      + 'değil — kayıt yoksa yükleme başarısız olur.');
  }
  if (lane === 'release' && !prog.p6_tested) {
    pre.push('Yol Haritası 6: "Gerçek cihazda test edildi" işaretli değil — '
      + 'test etmeden mağazaya yükleme riskli.');
  }
  if (lane === 'release' && plat === 'ios' && !prog.p7_asc_privacy) {
    pre.push('Yol Haritası 7: App Privacy işaretli değil — doldurulmadan '
      + 'incelemeye gönderemezsin.');
  }
  if (pre.length) {
    body += '<span class="preflight">'
      + pre.map((w) => `⚠ ${esc(w)}`).join('<br>') + '</span>';
  }

  confirmThen({
    title: lane === 'beta' ? '🚀 Beta\'ya gönder' : '📦 Mağazaya yükle',
    body: body,
    type: true, // "YAYINLA" yazdır
    notes: true, // sürüm notu kutusu
  }, (notes) => {
    let url = `api/deploy?path=${enc(path)}&platform=${plat}&lane=${lane}`
      + `&dryrun=0&confirm=YAYINLA`;
    if (notes) url += `&notes=${enc(notes)}`;
    stream(url, lane === 'beta' ? `Gönderiliyor: ${target}`
      : `Yükleniyor: ${target}`);
  });
}

// ------------------------------------------------------------- onay kipi

function confirmThen({ title, body, type = false, notes = false }, onOk) {
  const dlg = $('#confirm-dialog');
  $('#confirm-title').textContent = title;
  $('#confirm-body').innerHTML = body;
  const box = $('#confirm-typebox');
  const input = $('#confirm-input');
  const ok = $('#confirm-ok');
  const notesBox = $('#confirm-notes-box');
  const notesInput = $('#confirm-notes');
  box.hidden = !type;
  notesBox.hidden = !notes;
  input.value = '';
  if (notes) notesInput.value = '';
  ok.disabled = type; // yazana kadar kapalı

  if (type) {
    input.oninput = () => { ok.disabled = input.value.trim() !== 'YAYINLA'; };
  }

  dlg.returnValue = '';
  dlg.showModal();
  dlg.onclose = () => {
    if (dlg.returnValue === 'ok') {
      onOk(notes ? notesInput.value.trim() : undefined);
    }
  };
}

// ------------------------------------------------------------- yeni uygulama

function openNewDialog() {
  if (state.running) return;
  $('#new-parent').value = state.base || '';
  $('#new-dialog').showModal();
}

function submitNew(form) {
  const fd = new FormData(form);
  const params = new URLSearchParams();
  for (const k of ['name', 'org', 'appName', 'description', 'parent']) {
    const v = (fd.get(k) || '').toString().trim();
    if (v) params.set(k, v);
  }
  if (fd.get('backend')) params.set('backend', '1');
  // Checkbox: işaretliyse FormData'da "on" gelir, değilse hiç gelmez.
  if (fd.get('github')) {
    params.set('github', '1');
    params.set('visibility', (fd.get('visibility') || 'private').toString());
  }
  stream('api/new?' + params.toString(), `Yeni uygulama: ${params.get('name')}`);
}

// ------------------------------------------------------------- sekmeler

function showTab(which) {
  for (const t of ['actions', 'config', 'guide']) {
    $('#' + t + '-view').hidden = t !== which;
    $('#tab-' + t).classList.toggle('active', t === which);
  }
  if (which === 'config') loadConfig();
  if (which === 'guide') loadGuide();
}

// ----------------------------------------------------------- yapılandırma

async function loadConfig() {
  const path = state.selected;
  const body = $('#config-body');
  body.innerHTML = '<p class="muted pad">Yükleniyor…</p>';
  let data;
  try {
    const res = await fetch('api/config?path=' + enc(path));
    data = await res.json();
  } catch (e) {
    body.innerHTML = `<p class="muted pad">Hata: ${esc(e)}</p>`;
    return;
  }
  if (data.error) {
    body.innerHTML = `<p class="muted pad">${esc(data.error)}</p>`;
    return;
  }
  renderConfig(data);
}

function renderConfig(data) {
  const body = $('#config-body');
  const intro = `<p class="config-intro">Bu uygulamaya <strong>özel</strong>
    anahtarlar. Değerler projenin <code>.env</code> dosyasına yazılır (git'e
    girmez). Apple / Google Play <strong>hesap bilgileri</strong> (Team ID, API
    anahtarı, Play JSON) burada değil —
    <a href="#" id="cfg-goto-account">⚙ Hesap Varsayılanları</a>'nda bir kez
    girilir ve kaydettiğinde bu uygulamanın <code>.env</code>'ine otomatik
    eklenir.</p>`;

  const iconBox = `
    <fieldset class="cfg-group">
      <legend>Uygulama ikonu</legend>
      <p class="cfg-note">Tek bir <strong>1024×1024, saydamsız</strong> PNG bırak —
        iOS + Android ikonu, adaptive ikon ve açılış ekranı otomatik üretilir.
        (Bağımlılıklar kurulu olmalı: gerekirse önce "Güncelle".)</p>
      <div class="cfg-filerow">
        <input type="file" id="icon-file" accept="image/png,image/jpeg" />
        <span id="icon-status" class="cfg-file-no">görsel seç → üret</span>
      </div>
    </fieldset>`;

  const groups = data.groups.map((g) => {
    const help = g.help
      ? `<a class="help" href="${esc(g.help)}" target="_blank" rel="noopener">↗ ${esc(g.helpLabel || 'nereden alınır')}</a>`
      : '';
    const rows = g.fields.map((f) => configField(f)).join('');
    return `
      <fieldset class="cfg-group" data-group="${esc(g.id)}">
        <legend>${esc(g.title)}</legend>
        ${g.note ? `<p class="cfg-note">${esc(g.note)}</p>` : ''}
        ${help}
        <div class="cfg-fields">${rows}</div>
      </fieldset>`;
  }).join('');

  body.innerHTML = `${intro}${iconBox}${groups}
    <div class="cfg-actions">
      <button id="cfg-save" class="primary">Kaydet</button>
      <span id="cfg-status" class="muted"></span>
    </div>`;

  $('#cfg-save').addEventListener('click', saveConfig);
  const goto = $('#cfg-goto-account');
  if (goto) goto.addEventListener('click', (e) => { e.preventDefault(); openAccountDialog(); });
  // Yalnızca yapılandırma dosya alanları (data-key'li); ikon ayrı.
  $$('#config-view input[type=file][data-key]').forEach((inp) =>
    inp.addEventListener('change', () => uploadFile(inp)));
  $('#icon-file').addEventListener('change', generateIcon);
}

async function generateIcon() {
  const input = $('#icon-file');
  const file = input.files[0];
  if (!file) return;
  const status = $('#icon-status');
  status.textContent = 'yükleniyor…';
  status.className = 'cfg-file-no';
  try {
    const up = await fetch('api/icon/upload?path=' + enc(state.selected),
      { method: 'POST', body: file });
    const d = await up.json();
    if (!d.ok) { status.textContent = d.error || 'hata'; return; }
    status.textContent = '✓ yüklendi';
    status.className = 'cfg-file-ok';
    // Üretim uzun sürebilir; canlı konsola akıt.
    stream('api/icon?path=' + enc(state.selected), 'İkon & açılış ekranı üretimi');
  } catch (e) {
    status.textContent = 'hata: ' + e;
  }
}

// account=true: Hesap Varsayılanları kipi (dosyalar ~/.forge'a gider).
function configField(f, account = false) {
  const scope = account ? ' data-scope="account"' : '';
  const fhelp = f.help
    ? ` <a class="help sm" href="${esc(f.help)}" target="_blank" rel="noopener">↗ ${esc(f.helpLabel || 'link')}</a>`
    : '';
  const desc = f.desc ? `<small class="cfg-desc">${esc(f.desc)}</small>` : '';
  // Projede boş ama hesap varsayılanından gelen alan işareti.
  const accTag = (!account && f.fromAccount)
    ? ' <span class="cfg-acc">hesap varsayılanı</span>' : '';
  // Google TEST uygulama kimliği: çalışır ama gelir sıfır.
  const testTag = f.test
    ? ' <span class="cfg-test">⚠ TEST — gelir yok</span>' : '';

  if (f.file) {
    let current;
    if (f.set) {
      current = `<span class="cfg-file-ok">✓ ${esc(f.fileName || 'yüklü')}</span>`;
    } else if (!account && f.accountFileName) {
      current = `<span class="cfg-acc">hesap: ${esc(f.accountFileName)} — kaydedince uygulanır</span>`;
    } else {
      current = `<span class="cfg-file-no">yüklü değil</span>`;
    }
    return `
      <label class="cfg-field">
        <span class="cfg-label">${esc(f.label)}${fhelp}</span>
        <span class="cfg-filerow">
          <input type="file" data-key="${esc(f.key)}"${scope} accept="${esc(f.accept || '')}" />
          ${current}
        </span>
        ${desc}
      </label>`;
  }

  const type = f.secret ? 'password' : 'text';
  const val = f.secret ? '' : esc(f.value || '');
  const ph = f.secret && f.set ? '•••••• (kayıtlı — değiştirmek için yaz)' : esc(f.placeholder || '');
  return `
    <label class="cfg-field">
      <span class="cfg-label">${esc(f.label)}${f.set ? ' <span class="cfg-dot">●</span>' : ''}${accTag}${testTag}${fhelp}</span>
      <input type="${type}" data-key="${esc(f.key)}"${scope} value="${val}"
             placeholder="${ph}" autocomplete="off" spellcheck="false" />
      ${desc}
    </label>`;
}

async function saveConfig() {
  const status = $('#cfg-status');
  const values = {};
  $$('#config-view input:not([type=file])').forEach((inp) => {
    // Sır alanı boşsa dokunma (kayıtlıysa mevcut değeri koru).
    const isSecret = inp.type === 'password';
    if (isSecret && inp.value === '') return;
    values[inp.dataset.key] = inp.value;
  });
  status.textContent = 'Kaydediliyor…';
  try {
    const res = await fetch('api/config?path=' + enc(state.selected), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ values }),
    });
    const data = await res.json();
    if (data.ok) {
      if (data.warnings && data.warnings.length) {
        status.textContent = `✓ Kaydedildi, ama: ${data.warnings.join(' · ')}`;
        status.className = 'fail-text';
      } else {
        status.textContent = `✓ Kaydedildi (${data.saved.length} alan).`;
        status.className = 'ok-text';
      }
      loadReadiness(); // AdMob/anahtar durumu değişti — kart tazelensin
    } else {
      status.textContent = data.error || 'Hata';
      status.className = 'fail-text';
    }
  } catch (e) {
    status.textContent = 'Hata: ' + e;
    status.className = 'fail-text';
  }
}

async function uploadFile(input) {
  const file = input.files[0];
  if (!file) return;
  const key = input.dataset.key;
  const isAccount = input.dataset.scope === 'account';
  const row = input.closest('.cfg-filerow');
  const mark = row.querySelector('.cfg-file-ok, .cfg-file-no, .cfg-acc');
  mark.textContent = 'yükleniyor…';
  const url = isAccount
    ? `api/account/upload?field=${enc(key)}&filename=${enc(file.name)}`
    : `api/config/upload?path=${enc(state.selected)}&field=${enc(key)}&filename=${enc(file.name)}`;
  try {
    const res = await fetch(url, { method: 'POST', body: file });
    const data = await res.json();
    if (data.ok) {
      mark.textContent = '✓ ' + data.fileName;
      mark.className = 'cfg-file-ok';
    } else {
      mark.textContent = data.error || 'hata';
      mark.className = 'cfg-file-no';
    }
  } catch (e) {
    mark.textContent = 'hata: ' + e;
    mark.className = 'cfg-file-no';
  }
}

// -------------------------------------------------- hesap varsayılanları

async function openAccountDialog() {
  const dlg = $('#account-dialog');
  const body = $('#account-body');
  $('#account-status').textContent = '';
  body.innerHTML = '<p class="muted pad">Yükleniyor…</p>';
  dlg.showModal();
  let data;
  try {
    data = await (await fetch('api/account')).json();
  } catch (e) {
    body.innerHTML = `<p class="muted pad">Hata: ${esc(e)}</p>`;
    return;
  }
  body.innerHTML = data.groups.map((g) => {
    const help = g.help
      ? `<a class="help" href="${esc(g.help)}" target="_blank" rel="noopener">↗ ${esc(g.helpLabel || 'nereden alınır')}</a>`
      : '';
    const rows = g.fields.map((f) => configField(f, true)).join('');
    return `<fieldset class="cfg-group"><legend>${esc(g.title)}</legend>
      ${g.note ? `<p class="cfg-note">${esc(g.note)}</p>` : ''}${help}
      <div class="cfg-fields">${rows}</div></fieldset>`;
  }).join('');
  $$('#account-body input[type=file]').forEach((inp) =>
    inp.addEventListener('change', () => uploadFile(inp)));
}

async function saveAccount() {
  const status = $('#account-status');
  const values = {};
  $$('#account-body input:not([type=file])').forEach((inp) => {
    if (inp.type === 'password' && inp.value === '') return;
    values[inp.dataset.key] = inp.value;
  });
  status.textContent = 'Kaydediliyor…';
  try {
    const res = await fetch('api/account', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ values }),
    });
    const data = await res.json();
    status.textContent = data.ok
      ? `✓ Kaydedildi. Yeni uygulamalara otomatik gelecek.`
      : (data.error || 'Hata');
    status.className = data.ok ? 'ok-text' : 'fail-text';
  } catch (e) {
    status.textContent = 'Hata: ' + e;
    status.className = 'fail-text';
  }
}

// ------------------------------------------------------------ yol haritası
//
// Oluşturmadan incelemeye giden SIRALI rehber. İki tür madde var:
//  * otomatik: panelin kendisi izler (readiness verisinden gelir)
//  * elle: konsollarda yapılır; kullanıcı işaretler, sunucu hatırlar.

async function loadGuideProgress() {
  try {
    const d = await (await fetch('api/guide?path=' + enc(state.selected))).json();
    state.guideProgress = d.progress || {};
  } catch (e) { state.guideProgress = {}; }
}

async function loadGuide() {
  const body = $('#guide-body');
  body.innerHTML = '<p class="muted pad">Yükleniyor…</p>';
  await loadGuideProgress();
  if (!state.readiness) await loadReadiness();
  renderGuide();
}

function rdGate(plat, label) {
  const pl = ((state.readiness || {}).platforms || {})[plat];
  return pl ? (pl.gates.find((g) => g.label === label) || null) : null;
}
function rdCommon(label) {
  return ((state.readiness || {}).common || [])
    .find((g) => g.label === label) || null;
}

const GICON = { ok: '✓', warn: '⚠', block: '✗', todo: '○' };
const GKEYS = ['p4_admob_gdpr', 'p5_asc_record', 'p5_play_record',
  'p6_testers', 'p6_tested', 'p7_asc_listing', 'p7_asc_privacy',
  'p7_play_listing', 'p7_play_datasafety', 'p9_ios_submitted',
  'p9_play_published'];

function gAuto(gate, label) {
  const st = gate ? gate.status : 'todo';
  const hint = gate ? gate.hint : 'proje verisinden izlenir';
  return `<li class="gd-item gd-${st}"><span class="gd-ic">${GICON[st] || '○'}</span>
    <span class="gd-txt"><span class="gd-lbl">${label}</span><small>${esc(hint)} — panel otomatik izler</small></span></li>`;
}
function gCheck(key, label, hint) {
  const done = !!(state.guideProgress || {})[key];
  return `<li class="gd-item ${done ? 'gd-ok' : 'gd-todo'}">
    <label class="gd-checkrow"><input type="checkbox" data-gkey="${key}" ${done ? 'checked' : ''} />
    <span class="gd-txt"><span class="gd-lbl">${label}</span><small>${hint}</small></span></label></li>`;
}
function gInfo(label, hint) {
  return `<li class="gd-item gd-info"><span class="gd-ic">·</span>
    <span class="gd-txt"><span class="gd-lbl">${label}</span><small>${hint}</small></span></li>`;
}
function gDetails(summary, html) {
  return `<li class="gd-item gd-detbox"><details><summary>${summary}</summary>
    <div class="gd-detbody">${html}</div></details></li>`;
}
function gPhase(n, title, pre, inner) {
  return `<section class="gd-phase">
    <h3><span class="gd-n">${n}</span> ${title}</h3>
    ${pre ? `<p class="gd-pre">⛓ Önce bitmesi gereken: ${pre}</p>` : ''}
    <ul class="gd-list">${inner}</ul>
  </section>`;
}
const L = (u, t) => `<a href="${u}" target="_blank" rel="noopener">${t} ↗</a>`;

function renderGuide() {
  const prog = state.guideProgress || {};
  const done = GKEYS.filter((k) => prog[k]).length;

  const ascFields = gDetails('📋 App Store Connect — doldurulacak TÜM alanlar (aç)', `
    <ol>
      <li><strong>Ad</strong> (30 karakter) ve <strong>Alt Başlık</strong> (30) — aramada en güçlü sinyal.</li>
      <li><strong>Kategori</strong> — birincil (+ isteğe bağlı ikincil).</li>
      <li><strong>Ekran görüntüleri</strong> — iPhone <strong>6.9″</strong> seti zorunlu; iPad destekliyorsan <strong>13″</strong> seti de. Simülatörde Cmd+S ile çek; 3-5 görsel önerilir.</li>
      <li><strong>Tanıtım Metni</strong> (170 — incelemesiz güncellenebilir) ve <strong>Açıklama</strong> (4000).</li>
      <li><strong>Anahtar Kelimeler</strong> (100 karakter, virgülle; ad/alt başlıkta geçeni tekrar etme).</li>
      <li><strong>Destek URL</strong> (zorunlu), Pazarlama URL (isteğe bağlı).</li>
      <li><strong>Gizlilik Politikası URL</strong> (zorunlu — reklamlı uygulamada kesinlikle).</li>
      <li><strong>Yaş Sınıflandırması</strong> — anketi içeriğe göre dürüstçe doldur.</li>
      <li><strong>Fiyat ve Erişilebilirlik</strong> — ücretsiz + ülkeler.</li>
      <li><strong>İnceleme Bilgileri</strong> — iletişim; girişli uygulamada demo hesap; gerekirse not.</li>
    </ol>
    <p>${L('https://appstoreconnect.apple.com/apps', 'App Store Connect › Apps')}</p>`);

  const ascPrivacy = gDetails('🔒 App Privacy — AdMob kullanan uygulama için cevaplar (aç)', `
    <p>ASC › App Privacy › "Veri topluyor musunuz?" → <strong>Evet</strong>. AdMob için:</p>
    <ol>
      <li><strong>Identifiers → Device ID</strong> — amaç: <em>Third-Party Advertising</em>.</li>
      <li><strong>Usage Data → Advertising Data</strong> (+ Product Interaction) — amaç: <em>Third-Party Advertising</em>.</li>
      <li>"Linked to the user" → hesap sistemi yoksa <strong>Hayır</strong>.</li>
      <li><strong>Tracking</strong> → şablon ATT izni içerdiği için <strong>Evet</strong> (kişiselleştirilmiş reklam); yalnızca bağlamsal reklama geçersen Hayır.</li>
    </ol>
    <p>Resmi eşleme: ${L('https://support.google.com/admob/answer/10787069', 'AdMob → Apple gizlilik rehberi')}.
    Beyanın <code>PrivacyInfo.xcprivacy</code> ile tutarlı olması gerekir — forge şablonu reklamı zaten beyan eder.</p>`);

  const playFields = gDetails('🤖 Play Console — doldurulacak TÜM alanlar (aç)', `
    <ol>
      <li><strong>Store listing</strong> — kısa açıklama (80), tam açıklama (4000), ikon 512×512, feature graphic 1024×500, en az 2 telefon ekran görüntüsü.</li>
      <li><strong>Gizlilik politikası URL</strong> (zorunlu).</li>
      <li><strong>Data safety</strong> formu — AdMob: "Device or other IDs" <em>toplanır ve paylaşılır</em>, amaç <em>Advertising</em>. Eşleme: ${L('https://support.google.com/admob/answer/10787469', 'AdMob → Play data safety rehberi')}.</li>
      <li><strong>İçerik derecelendirmesi</strong> — IARC anketi.</li>
      <li><strong>Hedef kitle</strong> — 13+ öner (çocuk hedefi AdMob aile politikası gerektirir); <strong>"Reklam içerir" → Evet</strong>.</li>
      <li><strong>App access</strong> — girişli ise test hesabı ver; değilse "tümü erişilebilir".</li>
      <li><strong>Ülkeler ve fiyat</strong>.</li>
    </ol>
    <p>${L('https://play.google.com/console', 'Play Console')}</p>`);

  $('#guide-body').innerHTML = `
    <p class="config-intro">Uygulamayı <strong>oluşturduğun andan incelemeye
    gönderdiğin ana</strong> kadar izlenecek sıra. ✓/⚠ işaretli maddeleri panel
    kendisi izler; kutucuklu maddeleri konsollarda yapıp sen işaretlersin —
    panel hatırlar. <strong>${done}/${GKEYS.length}</strong> elle adım tamam.</p>

    ${gPhase(1, 'Hesap kurulumu — bir kez, bütün uygulamalar için', null,
      gAuto(rdGate('ios', 'App Store Connect anahtarı'), 'App Store Connect API anahtarı')
      + gAuto(rdGate('android', 'Google Play anahtarı'), 'Google Play servis hesabı JSON')
      + gInfo('GitHub bağlantısı', '<code>gh auth login</code> bir kez — panel yeni projeleri otomatik GitHub\'a bağlar.')
      + gInfo('Nereye girilir?', 'Soldaki ⚙ Hesap Varsayılanları — her yeni uygulamaya otomatik gelir.'))}

    ${gPhase(2, 'Uygulamayı oluştur', '1. adım (hesap anahtarları)',
      gInfo('Panel → ＋ Yeni uygulama', 'Mağazaya hazır iskelet + git + GitHub repo. <strong>--org\'u doğru seç: paket kimliği yayından sonra DEĞİŞMEZ.</strong>')
      + gInfo('Backend gerekiyorsa', '"Backend ekle" kutusunu işaretle — FastAPI + PostgreSQL + fotoğraf saklama hazır gelir.'))}

    ${gPhase(3, 'Geliştir', null,
      gInfo('Kodla ve dene', '<code>cd app && flutter run</code>. Paket ekleyince panelden 🔄 Güncelle.')
      + gAuto(rdGate('ios', 'Mağaza denetimi'), 'Doctor — iOS temiz mi')
      + gAuto(rdGate('android', 'Mağaza denetimi'), 'Doctor — Android temiz mi')
      + gInfo('Alışkanlık', 'Doctor\'ı sık çalıştır; engeli biriktirme — çoğunu 🩹 Düzeltmeleri uygula kapatır.'))}

    ${gPhase(4, 'Yayın kimlikleri ve yapılandırma', null,
      gAuto(rdCommon('Uygulama ikonu'), 'Uygulama ikonu — Yapılandırma sekmesinden tek görsel yükle')
      + gInfo('iOS imzalama', 'Xcode\'da Runner → Signing & Capabilities → <strong>Team</strong> seç (bir kez). Doctor "takım seçili değil" engeli kalkınca tamamdır.')
      + gAuto(rdGate('android', 'Sürüm imzalama (key.properties)'), 'Android imzalama anahtarı')
      + gInfo('AdMob\'da uygulamayı aç', L('https://apps.admob.com', 'apps.admob.com') + ' → Uygulama ekle → <strong>uygulama kimliğini (~)</strong> ve <strong>birim kimliklerini (/)</strong> Yapılandırma sekmesine gir.')
      + gAuto(rdGate('ios', 'AdMob uygulama kimliği'), 'AdMob uygulama kimliği — iOS')
      + gAuto(rdGate('android', 'AdMob uygulama kimliği'), 'AdMob uygulama kimliği — Android')
      + gCheck('p4_admob_gdpr', 'AdMob GDPR (UMP) mesajı yayınlandı',
        'apps.admob.com → Privacy &amp; messaging → GDPR mesajını oluştur ve <strong>yayınla</strong>. Yoksa AB\'de reklam gösterilmez.'))}

    ${gPhase(5, 'Mağaza kayıtlarını aç — elle, uygulama başına bir kez', '4. adımdaki kimlikler kesinleşmiş olmalı',
      gCheck('p5_asc_record', 'App Store Connect\'te uygulama kaydı açıldı',
        L('https://developer.apple.com/account/resources/identifiers/list', 'Identifiers') + '\'a bundle id\'yi kaydet → '
        + L('https://appstoreconnect.apple.com/apps', 'ASC › Apps') + ' → ＋ New App → ad, dil, bundle id, SKU. <strong>Kayıt yoksa panelin yüklemesi reddedilir.</strong>')
      + gCheck('p5_play_record', 'Play Console\'da uygulama kaydı açıldı',
        L('https://play.google.com/console', 'Play Console') + ' → Create app → ad, dil, ücretsiz.'))}

    ${gPhase(6, 'Beta ve gerçek testte doğrula', 'Yayına hazırlık sütunu "hazır" + 5. adım işaretli',
      gInfo('Panel → 🚀 TestFlight\'a gönder / Play Beta\'ya gönder', 'Build derlenir ve testçilere çıkar. Beta\'da test reklam kimliği meşrudur.')
      + gCheck('p6_testers', 'TestFlight\'ta testçi eklendi',
        'ASC → uygulama → TestFlight → Internal Testing → kendini (ve testçileri) ekle. Build işlenince (5-30 dk) telefona düşer.')
      + gCheck('p6_tested', 'Gerçek cihazda test edildi',
        'Açılış, ana akış, bildirimler, reklam yerleşimi. <strong>Mağazaya test etmeden yükleme.</strong>'))}

    ${gPhase(7, 'Mağaza listelemesini doldur — elle', '6. adım (build işlenmiş olmalı ki sürüme ekleyebilesin)',
      ascFields + ascPrivacy + playFields
      + gCheck('p7_asc_listing', 'ASC listeleme alanları dolduruldu', 'Yukarıdaki 📋 listesindeki her şey.')
      + gCheck('p7_asc_privacy', 'ASC App Privacy dolduruldu', 'Yukarıdaki 🔒 cevaplarıyla.')
      + gCheck('p7_play_listing', 'Play store listing dolduruldu', 'Görseller + açıklamalar + ülkeler.')
      + gCheck('p7_play_datasafety', 'Play Data safety + içerik derecelendirmesi dolduruldu', 'AdMob eşlemesiyle.'))}

    ${gPhase(8, 'Mağazaya yükle — panel (yalnızca gerekiyorsa)', '6 (test) ve 7 (listeleme) tamam',
      gInfo('Önce şunu bil: TestFlight ve App Store build\'leri AYNI havuzdur',
        'Test ettiğin build\'i değiştirmeden yayınlayacaksan <strong>bu adımı atla</strong> — 9. adımda o build\'i doğrudan sürüme eklersin. Yeniden yüklemek test etmediğin YENİ bir build üretir.')
      + gInfo('iOS: 📦 App Store\'a yükle — kod değiştiyse', 'Yeni build\'i ASC havuzuna koyar, <strong>incelemeye gönderilmez</strong>. Üretimde uyarılar da engeldir (--strict): test AdMob kimliğiyle mağazaya çıkamazsın — bilinçli.')
      + gInfo('Android: 📦 Play\'e yükle (taslak)', 'App Bundle Production\'a taslak gider, <strong>yayınlanmaz</strong>. Android\'de kanallar ayrıdır: beta\'da test ettiysen Production\'a bu adımla yüklemen gerekir.'))}

    ${gPhase(9, 'İncelemeye gönder — son adım, insan işi', '8\'deki yükleme bitmiş ve build konsolda görünür olmalı',
      gCheck('p9_ios_submitted', 'iOS: incelemeye gönderildi',
        'ASC → uygulama → sürüm sayfası → <strong>Build</strong> bölümünde ＋ → <strong>test ettiğin</strong> (ya da 8\'de yüklediğin) build\'i seç → "What\'s New" yaz → <strong>Add for Review → Submit</strong>. Genelde 24-48 saatte sonuçlanır; ret gelirse Resolution Center\'dan düzeltip yeniden gönder.')
      + gCheck('p9_play_published', 'Android: Play taslağı yayınlandı',
        'Play Console → Production → taslak sürümü aç → notları kontrol et → <strong>kademeli yayın</strong> başlat (%10 önerilir, sorun yoksa artır).'))}

    <p class="gd-done">🎉 9/9 bitince uygulaman incelemededir. Sonraki sürümlerde
    yalnızca 3 → 6 → 8 → 9 tekrarlanır; 1-2-4-5-7 tek seferlikti.</p>`;

  $$('#guide-body input[data-gkey]').forEach((cb) =>
    cb.addEventListener('change', async () => {
      try {
        await fetch('api/guide?path=' + enc(state.selected), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ key: cb.dataset.gkey, done: cb.checked }),
        });
      } catch (e) { /* sonraki yüklemede eski hâline döner */ }
      if (cb.checked) state.guideProgress[cb.dataset.gkey] = true;
      else delete state.guideProgress[cb.dataset.gkey];
      renderGuide();
    }));
}

// ------------------------------------------------------------- github

// Açılışta gh durumunu sorar: kurulu değilse ya da giriş yapılmamışsa kenar
// çubuğunda uyarı gösterir — sorun proje oluşturma anına kalmaz.
async function checkGithub() {
  const banner = $('#gh-banner');
  const text = $('#gh-banner-text');
  const btn = $('#gh-login-btn');
  try {
    const res = await fetch('api/github/status');
    const d = await res.json();
    if (d.installed && d.authenticated) {
      banner.hidden = true;
      return;
    }
    banner.hidden = false;
    if (!d.installed) {
      text.textContent =
        'GitHub CLI (gh) kurulu değil. Terminalde: brew install gh';
      btn.hidden = true;
    } else {
      text.textContent =
        'GitHub girişi yapılmamış. Giriş yapın ki yeni projeler GitHub\'a bağlanabilsin.';
      btn.hidden = false;
    }
  } catch {
    // Sunucuya ulaşılamıyorsa proje listesi zaten hata gösteriyor.
  }
}

function ghLogin() {
  // Cihaz akışı: gh tek seferlik kodu konsola basar, doğrulama bu sayfada
  // yapılır. Sekmeyi tıklama anında açmak gerekir (popup engeli).
  window.open('https://github.com/login/device', '_blank');
  stream('api/github/login', 'GitHub girişi — konsoldaki kodu açılan sayfaya girin');
}

// ------------------------------------------------------------- yardımcı

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ------------------------------------------------------------- bağlama

document.addEventListener('DOMContentLoaded', () => {
  loadProjects();
  checkGithub();

  $('#refresh-btn').addEventListener('click', loadProjects);
  $('#gh-login-btn').addEventListener('click', ghLogin);
  $('#new-app-btn').addEventListener('click', openNewDialog);
  $('#account-btn').addEventListener('click', openAccountDialog);
  $('#account-save').addEventListener('click', saveAccount);
  $('#account-close').addEventListener('click', () => $('#account-dialog').close());
  $('#console-clear').addEventListener('click', () => ($('#console').textContent = ''));
  $('#run-pill').addEventListener('click', () => {
    $('#console-wrap').scrollIntoView({ behavior: 'smooth', block: 'end' });
    if (!state.running) hideRunPill();
  });

  $$('#project-view button[data-act]').forEach((b) =>
    b.addEventListener('click', () => act(b.dataset.act)));

  $$('.tab').forEach((t) =>
    t.addEventListener('click', () => showTab(t.dataset.tab)));

  // GitHub kutusu kapalıysa görünürlük seçimini gizle.
  const ghCheck = $('#gh-check');
  const ghVis = $('#gh-vis-label');
  const syncGh = () => { ghVis.style.display = ghCheck.checked ? '' : 'none'; };
  ghCheck.addEventListener('change', syncGh);
  syncGh();

  $('#new-form').addEventListener('submit', (e) => {
    // method="dialog": submit değeri "create" ise gönder.
    if (e.submitter && e.submitter.value === 'create') {
      // Tarayıcı doğrulaması geçmezse dialog kapanmaz; burada geçmiştir.
      setTimeout(() => submitNew(e.target), 0);
    }
  });
});
