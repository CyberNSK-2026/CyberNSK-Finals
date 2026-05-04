defmodule TypeVaultWeb.Router do
  use TypeVaultWeb, :router

  # ── Browser pipeline (LiveView + session) ───────────────────────────────────
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TypeVaultWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TypeVaultWeb.Plugs.LoadSessionUser
  end

  # ── JSON API pipeline ────────────────────────────────────────────────────────
  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug Guardian.Plug.Pipeline,
      module: TypeVault.Guardian,
      error_handler: TypeVaultWeb.AuthErrorHandler
    plug Guardian.Plug.VerifyHeader, schemes: ["Bearer"]
    plug Guardian.Plug.LoadResource, allow_blank: true
    plug TypeVaultWeb.Plugs.RequireAuth
  end

  pipeline :internal do
    plug :accepts, ["json"]
    plug TypeVaultWeb.Plugs.RequireLocalhost
  end

  # ── Public web pages ─────────────────────────────────────────────────────────
  scope "/", TypeVaultWeb do
    pipe_through :browser

    get "/", PageController, :index

    get    "/login",    WebAuthController, :new_session
    post   "/login",    WebAuthController, :create_session
    get    "/register", WebAuthController, :new_registration
    post   "/register", WebAuthController, :create_registration
    delete "/logout",   WebAuthController, :delete_session

    live "/gallery",           GalleryLive, :index
    live "/studio",            StudioLive,  :index
    live "/studio/:id",        ProjectLive, :show
    live "/studio/:id/export", ExportLive,  :show

    get  "/tools/generate",  ToolsController, :generate_form
    post "/tools/generate",  ToolsController, :generate_tvf

    get "/fonts/:id/download", FontController, :download_file
  end

  # ── Public JSON routes ────────────────────────────────────────────────────────
  scope "/api", TypeVaultWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login",    AuthController, :login

    get "/gallery",          GalleryController, :index
    get "/gallery/featured", GalleryController, :featured
    get "/gallery/tags",     GalleryController, :tags
    get "/gallery/:id",      GalleryController, :show
  end

  # ── Authenticated JSON routes ──────────────────────────────────────────────────
  scope "/api", TypeVaultWeb do
    pipe_through [:api, :authenticated]

    get "/me",  AuthController, :me
    put "/me",  AuthController, :update_profile

    get    "/projects",     ProjectController, :index
    post   "/projects",     ProjectController, :create
    get    "/projects/:id", ProjectController, :show
    put    "/projects/:id", ProjectController, :update
    delete "/projects/:id", ProjectController, :delete
    post   "/projects/:id/publish", ProjectController, :publish

    post   "/projects/:project_id/fonts",             FontController, :upload
    get    "/projects/:project_id/fonts",             FontController, :list
    get    "/projects/:project_id/fonts/:id",         FontController, :show
    delete "/projects/:project_id/fonts/:id",         FontController, :delete
    post   "/projects/:project_id/fonts/:id/preview", FontController, :preview

    post "/projects/:project_id/preview_draft", FontController, :preview_draft

    get    "/projects/:project_id/members",          SharingController, :index
    post   "/projects/:project_id/members",          SharingController, :create
    put    "/projects/:project_id/members/:user_id", SharingController, :update
    delete "/projects/:project_id/members/:user_id", SharingController, :delete

    get "/projects/:project_id/activity", ActivityController, :index

    post "/export",          ExportController, :create
    get  "/export/settings", ExportController, :get_settings
    put  "/export/settings", ExportController, :save_settings
    get  "/export/context",  ExportController, :context

    get    "/export/presets",     PresetController, :index
    post   "/export/presets",     PresetController, :create
    get    "/export/presets/:id", PresetController, :show
    put    "/export/presets/:id", PresetController, :update
    delete "/export/presets/:id", PresetController, :delete
  end

  # ── Internal endpoints — localhost only ──────────────────────────────────────
  scope "/api/internal", TypeVaultWeb do
    pipe_through :internal

    get  "/status",   InternalController, :status
    get  "/projects", InternalController, :list_projects
  end

  if Application.compile_env(:typevault, :dev_routes) do
    import Phoenix.LiveDashboard.Router
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: TypeVaultWeb.Telemetry
    end
  end
end
