import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from database import init_db
from routers import auth, files, integrations, notifications, reports, share, tickets, users


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    os.makedirs("/uploads", exist_ok=True)
    yield


app = FastAPI(
    title="ServiceDesk",
    version="1.0.0",
    lifespan=lifespan,
    docs_url=None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(tickets.router)
app.include_router(reports.router)
app.include_router(integrations.router)
app.include_router(notifications.router)
app.include_router(share.router)
app.include_router(users.router)
app.include_router(files.router)

static_dir = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")


@app.get("/", response_class=HTMLResponse)
async def index():
    html_path = os.path.join(os.path.dirname(__file__), "static", "index.html")
    if os.path.exists(html_path):
        with open(html_path) as f:
            return HTMLResponse(f.read())
    return HTMLResponse("<h1>ServiceDesk API</h1>")


@app.get("/health")
async def health():
    return {"ok": True, "service": "servicedesk"}


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
