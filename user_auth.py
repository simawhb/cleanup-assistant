"""用户注册登录系统 - SQLite 存储"""
import sqlite3
import hashlib
import secrets
import os
import time
from pathlib import Path

DB_PATH = Path(__file__).parent / "users.db"

def get_db():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            token TEXT UNIQUE,
            token_expires REAL,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            last_login TEXT
        );
        CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT,
            action TEXT,
            detail TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        );
    """)
    conn.commit()
    conn.close()

def hash_password(password, salt="cleanup2026"):
    return hashlib.sha256((salt + password).encode()).hexdigest()

def register(username, password):
    if not username or not password:
        return {"error": "username and password required"}
    if len(username) < 3:
        return {"error": "username must be >= 3 chars"}
    if len(password) < 6:
        return {"error": "password must be >= 6 chars"}
    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO users (username, password_hash) VALUES (?, ?)",
            (username, hash_password(password))
        )
        conn.commit()
        add_log(username, "register", "new account created")
        return {"ok": True, "message": "registered"}
    except sqlite3.IntegrityError:
        return {"error": "username already exists"}
    finally:
        conn.close()

def login(username, password):
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM users WHERE username=? AND password_hash=?",
        (username, hash_password(password))
    ).fetchone()
    if not row:
        conn.close()
        return {"error": "invalid credentials"}
    token = secrets.token_urlsafe(32)
    expires = time.time() + 86400
    conn.execute(
        "UPDATE users SET token=?, token_expires=?, last_login=datetime('now','localtime') WHERE username=?",
        (token, expires, username)
    )
    conn.commit()
    conn.close()
    add_log(username, "login", "successful login")
    return {"ok": True, "token": token, "expires": expires}

def verify_token(token):
    if not token:
        return None
    conn = get_db()
    row = conn.execute(
        "SELECT username, token_expires FROM users WHERE token=?",
        (token,)
    ).fetchone()
    conn.close()
    if not row:
        return None
    if row["token_expires"] and row["token_expires"] < time.time():
        return None
    return row["username"]

def add_log(username, action, detail=""):
    conn = get_db()
    conn.execute(
        "INSERT INTO logs (username, action, detail) VALUES (?, ?, ?)",
        (username, action, detail)
    )
    conn.commit()
    conn.close()

def get_logs(limit=50):
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM logs ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]

def get_users():
    conn = get_db()
    rows = conn.execute(
        "SELECT id, username, created_at, last_login FROM users ORDER BY id"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]

# Auto-init on import
init_db()
