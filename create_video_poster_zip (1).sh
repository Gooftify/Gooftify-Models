#!/usr/bin/env bash
set -euo pipefail
OUTDIR="video-poster"

rm -rf "$OUTDIR" video-poster.zip
mkdir -p "$OUTDIR"/public
echo "Creating project in ./$OUTDIR ..."

cat > "$OUTDIR/package.json" <<'JSON'
{
  "name": "video-poster",
  "version": "1.0.0",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "multer": "^1.4.5-lts.1",
    "sqlite3": "^5.1.6"
  }
}
JSON

cat > "$OUTDIR/.env.example" <<'ENV'
# Copy this to .env and set your own values
ADMIN_USERNAME=you
ADMIN_PASSWORD=yourpassword
SESSION_SECRET=change_this_secret
PORT=3000
ENV

cat > "$OUTDIR/.gitignore" <<'GI'
node_modules/
uploads/
thumbnails/
data.sqlite
.env
GI

cat > "$OUTDIR/README.md" <<'MD'
# Video Poster

A minimal Node.js + Express app to upload videos with optional thumbnails and titles. Single admin account controlled via environment variables.

Setup:
1. Copy `.env.example` to `.env` and set values.
2. Install dependencies:
   npm install
3. Start the server:
   npm start
4. Open http://localhost:3000

Notes:
- Uploaded files are stored in `uploads/` and `thumbnails/`.
- For production use, don't store credentials in .env; use a proper user system and cloud storage for files.
MD

cat > "$OUTDIR/LICENSE" <<'LIC'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
...
(Use this as a placeholder; replace with the full MIT text if you want)
LIC

cat > "$OUTDIR/db.js" <<'JS'
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbFile = path.join(__dirname, 'data.sqlite');
const db = new sqlite3.Database(dbFile);

db.serialize(() => {
  db.run(`
    CREATE TABLE IF NOT EXISTS videos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      video_path TEXT NOT NULL,
      thumb_path TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);
});

module.exports = db;
JS

cat > "$OUTDIR/server.js" <<'JS'
require('dotenv').config();
const express = require('express');
const session = require('express-session');
const bcrypt = require('bcryptjs');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'you';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'yourpassword'; // plaintext in env
const SESSION_SECRET = process.env.SESSION_SECRET || 'secret';

// Hash the admin password once in-memory
const adminPasswordHash = bcrypt.hashSync(ADMIN_PASSWORD, 10);

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(session({
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false }
}));

app.use(express.static(path.join(__dirname, 'public')));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/thumbnails', express.static(path.join(__dirname, 'thumbnails')));

['uploads', 'thumbnails'].forEach(dir => {
  const p = path.join(__dirname, dir);
  if (!fs.existsSync(p)) fs.mkdirSync(p);
});

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    if (file.fieldname === 'video') cb(null, path.join(__dirname, 'uploads'));
    else if (file.fieldname === 'thumbnail') cb(null, path.join(__dirname, 'thumbnails'));
    else cb(null, path.join(__dirname, 'uploads'));
  },
  filename: (req, file, cb) => {
    const safe = Date.now() + '-' + file.originalname.replace(/\s+/g, '-');
    cb(null, safe);
  }
});
const upload = multer({ storage, limits: { fileSize: 1024 * 1024 * 1024 } });

function ensureLoggedIn(req, res, next) {
  if (req.session && req.session.loggedIn) return next();
  return res.status(401).json({ error: 'Not authorized' });
}

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (username === ADMIN_USERNAME && bcrypt.compareSync(password, adminPasswordHash)) {
    req.session.loggedIn = true;
    req.session.username = username;
    return res.json({ ok: true });
  }
  return res.status(401).json({ error: 'Invalid credentials' });
});

app.post('/logout', (req, res) => {
  req.session.destroy(() => res.json({ ok: true }));
});

app.post('/api/upload', ensureLoggedIn, upload.fields([
  { name: 'video', maxCount: 1 },
  { name: 'thumbnail', maxCount: 1 }
]), (req, res) => {
  const title = (req.body.title || '').trim();
  if (!title) return res.status(400).json({ error: 'Title is required' });
  if (!req.files || !req.files.video || req.files.video.length === 0) {
    return res.status(400).json({ error: 'Video file is required' });
  }

  const videoFile = req.files.video[0];
  const thumbFile = req.files.thumbnail && req.files.thumbnail[0] ? req.files.thumbnail[0] : null;

  const videoPath = '/uploads/' + path.basename(videoFile.path);
  const thumbPath = thumbFile ? '/thumbnails/' + path.basename(thumbFile.path) : null;

  db.run(
    `INSERT INTO videos (title, video_path, thumb_path) VALUES (?, ?, ?)`,
    [title, videoPath, thumbPath],
    function (err) {
      if (err) {
        console.error(err);
        return res.status(500).json({ error: 'DB error' });
      }
      return res.json({ ok: true, id: this.lastID });
    }
  );
});

app.get('/api/videos', (req, res) => {
  db.all(`SELECT id, title, video_path, thumb_path, created_at FROM videos ORDER BY created_at DESC`, [], (err, rows) => {
    if (err) return res.status(500).json({ error: 'DB error' });
    res.json(rows);
  });
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
JS

cat > "$OUTDIR/public/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>My Videos</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div class="container">
    <h1>My Video Poster</h1>

    <div id="auth">
      <form id="loginForm">
        <input name="username" placeholder="username" required />
        <input name="password" type="password" placeholder="password" required />
        <button type="submit">Log in</button>
      </form>
      <button id="logoutBtn" style="display:none">Log out</button>
    </div>

    <section id="uploader" style="display:none">
      <h2>Upload Video</h2>
      <form id="uploadForm">
        <input name="title" placeholder="Title" required />
        <div>
          <label>Video file (.mp4, .webm etc):</label>
          <input name="video" type="file" accept="video/*" required />
        </div>
        <div>
          <label>Thumbnail (optional):</label>
          <input name="thumbnail" type="file" accept="image/*" />
        </div>
        <button type="submit">Upload</button>
      </form>
      <div id="uploadStatus"></div>
    </section>

    <section id="videos">
      <h2>Videos</h2>
      <div id="list"></div>
    </section>
  </div>

  <script src="script.js"></script>
</body>
</html>
HTML

cat > "$OUTDIR/public/styles.css" <<'CSS'
body { font-family: Arial, Helvetica, sans-serif; margin: 0; padding: 1rem; background:#f5f5f5; }
.container { max-width:900px; margin:0 auto; background:white; padding:1rem 1.5rem; border-radius:6px; box-shadow:0 2px 8px rgba(0,0,0,0.08); }
h1,h2 { color:#333; }
#list { display:flex; flex-wrap:wrap; gap:1rem; }
.card { width: 280px; border:1px solid #eee; border-radius:6px; overflow:hidden; background:#fff; }
.card img { width:100%; height:160px; object-fit:cover; }
.card .info { padding:0.5rem; }
video { width:100%; height:auto; display:block; }
input,button { padding:8px; margin-top:6px; }
CSS

cat > "$OUTDIR/public/script.js" <<'JS'
// simple frontend logic
async function $(sel){ return document.querySelector(sel); }
function createEl(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }

async function fetchVideos(){
  const res = await fetch('/api/videos');
  const list = await res.json();
  const container = await $('#list');
  container.innerHTML = '';
  list.forEach(v=>{
    const card = createEl('div','card');
    if (v.thumb_path) {
      const img = createEl('img');
      img.src = v.thumb_path;
      card.appendChild(img);
    } else {
      const vid = createEl('video');
      vid.src = v.video_path;
      vid.controls = true;
      vid.style.height = '160px';
      card.appendChild(vid);
    }
    const info = createEl('div','info');
    const title = createEl('div');
    title.textContent = v.title;
    const when = createEl('div');
    when.textContent = new Date(v.created_at).toLocaleString();
    info.appendChild(title);
    info.appendChild(when);

    const playBtn = createEl('button');
    playBtn.textContent = 'Play';
    playBtn.onclick = () => {
      const p = createEl('video');
      p.src = v.video_path;
      p.controls = true;
      p.style.width = '100%';
      if (card.querySelector('video')) card.replaceChild(p, card.querySelector('video'));
      else {
        const img = card.querySelector('img');
        if (img) card.replaceChild(p, img);
      }
    };
    info.appendChild(playBtn);

    card.appendChild(info);
    container.appendChild(card);
  });
}

document.addEventListener('DOMContentLoaded', ()=>{
  const loginForm = document.getElementById('loginForm');
  const logoutBtn = document.getElementById('logoutBtn');
  const uploadSection = document.getElementById('uploader');
  const uploadForm = document.getElementById('uploadForm');
  const status = document.getElementById('uploadStatus');

  loginForm.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const fd = new FormData(loginForm);
    const body = { username: fd.get('username'), password: fd.get('password') };
    const res = await fetch('/login', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) });
    if (res.ok) {
      loginForm.style.display = 'none';
      logoutBtn.style.display = 'inline';
      uploadSection.style.display = 'block';
    } else {
      alert('Login failed');
    }
  });

  logoutBtn.addEventListener('click', async ()=>{
    await fetch('/logout', { method:'POST' });
    uploadSection.style.display = 'none';
    logoutBtn.style.display = 'none';
    loginForm.style.display = 'block';
  });

  uploadForm.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const fd = new FormData(uploadForm);
    status.textContent = 'Uploading...';
    const res = await fetch('/api/upload', { method:'POST', body: fd });
    if (res.ok) {
      status.textContent = 'Uploaded!';
      uploadForm.reset();
      fetchVideos();
    } else if (res.status === 401) {
      status.textContent = 'Not authorized. Log in first.';
    } else {
      const err = await res.json().catch(()=>({error:'upload failed'}));
      status.textContent = 'Error: ' + (err.error || 'Upload failed');
    }
    setTimeout(()=> status.textContent = '', 3000);
  });

  fetchVideos();
});
JS

echo "All files created. Creating zip archive..."
zip -r "video-poster.zip" "$OUTDIR" >/dev/null

echo "Done. Created video-poster.zip and folder ./$OUTDIR"
echo "Next: unzip video-poster.zip, copy .env.example to .env and set values, then run 'npm install' and 'npm start'."