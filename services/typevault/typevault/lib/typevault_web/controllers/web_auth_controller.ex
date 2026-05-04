defmodule TypeVaultWeb.WebAuthController do
  use TypeVaultWeb, :controller

  alias TypeVault.{Accounts, Guardian}

  # ── Login ──────────────────────────────────────────────────────────────────

  def new_session(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, auth_page("Sign in to TypeVault", login_form(conn)))
  end

  def create_session(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)
        conn
        |> put_session(:current_user_id, user.id)
        |> put_session(:tv_token, token)
        |> put_flash(:info, "Welcome back, #{user.username}!")
        |> redirect(to: "/studio")

      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> put_resp_content_type("text/html")
        |> send_resp(401, auth_page("Sign in to TypeVault", login_form(conn, email)))
    end
  end

  def create_session(conn, _), do: redirect(conn, to: "/login")

  # ── Register ───────────────────────────────────────────────────────────────

  def new_registration(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, auth_page("Create your TypeVault account", register_form(conn)))
  end

  def create_registration(conn, params) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)
        conn
        |> put_session(:current_user_id, user.id)
        |> put_session(:tv_token, token)
        |> put_flash(:info, "Welcome to TypeVault, #{user.username}!")
        |> redirect(to: "/studio")

      {:error, changeset} ->
        errors = format_errors(changeset)
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(422, auth_page("Create your TypeVault account", register_form(conn, params, errors)))
    end
  end

  # ── Logout ──────────────────────────────────────────────────────────────────

  def delete_session(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp auth_page(title, form_html) do
    flash_html =
      """
      <style>
        .flash-info  { background:#1e3a5f; color:#93c5fd; border:1px solid rgba(147,197,253,.2); }
        .flash-error { background:#3b1219; color:#fca5a5; border:1px solid rgba(252,165,165,.2); }
      </style>
      """

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>#{title}</title>
      <script src="https://cdn.tailwindcss.com"></script>
      #{flash_html}
    </head>
    <body style="background:#09090f;color:#e2e8f0;min-height:100vh;display:flex;flex-direction:column;">

      <nav style="border-bottom:1px solid rgba(255,255,255,.07);padding:0 1.5rem;">
        <div style="max-width:1280px;margin:0 auto;height:58px;display:flex;align-items:center;justify-content:space-between;">
          <a href="/" style="font-size:1.05rem;font-weight:800;letter-spacing:-.03em;text-decoration:none;background:linear-gradient(135deg,#a78bfa,#06b6d4);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;">TypeVault</a>
        </div>
      </nav>

      <div style="flex:1;display:flex;align-items:center;justify-content:center;padding:2rem;">
        #{form_html}
      </div>

      <footer style="text-align:center;padding:1rem;color:#475569;font-size:.75rem;">
        © 2024 TypeVault, Inc.
      </footer>
    </body>
    </html>
    """
  end

  defp login_form(conn, prefill \\ "") do
    csrf = Plug.CSRFProtection.get_csrf_token()
    flash_html = render_flash(conn)

    """
    <div style="width:100%;max-width:400px;">
      #{flash_html}
      <div style="background:#13131f;border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:2.5rem;">
        <h1 style="font-size:1.5rem;font-weight:700;letter-spacing:-.02em;margin-bottom:.4rem;">Sign in</h1>
        <p style="color:#64748b;font-size:.875rem;margin-bottom:2rem;">Enter your credentials to continue.</p>

        <form method="POST" action="/login" style="display:flex;flex-direction:column;gap:1.1rem;">
          <input type="hidden" name="_csrf_token" value="#{csrf}"/>

          <div>
            <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Email</label>
            <input type="email" name="email" value="#{prefill}" required
              style="width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
              onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"/>
          </div>

          <div>
            <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Password</label>
            <input type="password" name="password" required
              style="width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
              onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"/>
          </div>

          <button type="submit"
            style="width:100%;padding:.8rem;background:#7c3aed;border:none;border-radius:9px;color:#fff;font-size:.95rem;font-weight:600;cursor:pointer;margin-top:.25rem;"
            onmouseover="this.style.background='#6d28d9'" onmouseout="this.style.background='#7c3aed'">
            Sign in
          </button>
        </form>

        <p style="text-align:center;color:#64748b;font-size:.82rem;margin-top:1.5rem;">
          Don't have an account?
          <a href="/register" style="color:#a78bfa;text-decoration:none;font-weight:500;">Create one free →</a>
        </p>
      </div>
    </div>
    """
  end

  defp register_form(conn, prefill \\ %{}, errors \\ "") do
    csrf = Plug.CSRFProtection.get_csrf_token()
    flash_html = render_flash(conn)

    err_html = if errors != "", do: """
      <div style="background:#3b1219;border:1px solid rgba(252,165,165,.2);border-radius:8px;padding:.75rem 1rem;color:#fca5a5;font-size:.82rem;margin-bottom:1rem;">#{errors}</div>
    """, else: ""

    """
    <div style="width:100%;max-width:420px;">
      #{flash_html}
      <div style="background:#13131f;border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:2.5rem;">
        <h1 style="font-size:1.5rem;font-weight:700;letter-spacing:-.02em;margin-bottom:.4rem;">Create account</h1>
        <p style="color:#64748b;font-size:.875rem;margin-bottom:2rem;">Start designing type today. Free forever.</p>

        #{err_html}

        <form method="POST" action="/register" style="display:flex;flex-direction:column;gap:1.1rem;">
          <input type="hidden" name="_csrf_token" value="#{csrf}"/>

          <div style="display:grid;grid-template-columns:1fr 1fr;gap:.75rem;">
            <div>
              <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Username</label>
              <input type="text" name="username" value="#{Map.get(prefill, "username", "")}" required
                style="width:100%;padding:.7rem .9rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
                onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"/>
            </div>
            <div>
              <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Email</label>
              <input type="email" name="email" value="#{Map.get(prefill, "email", "")}" required
                style="width:100%;padding:.7rem .9rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
                onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"/>
            </div>
          </div>

          <div>
            <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Password</label>
            <input type="password" name="password" required minlength="8"
              style="width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
              onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"/>
          </div>

          <div>
            <label style="display:block;font-size:.8rem;color:#94a3b8;margin-bottom:.4rem;font-weight:500;">Bio <span style="color:#475569;font-weight:400;">(optional)</span></label>
            <input type="text" name="bio" placeholder="Typeface designer, lettering artist…"
              style="width:100%;padding:.7rem 1rem;background:#09090f;border:1px solid rgba(255,255,255,.1);border-radius:9px;color:#e2e8f0;font-size:.9rem;outline:none;"
              onfocus="this.style.borderColor='#7c3aed'" onblur="this.style.borderColor='rgba(255,255,255,.1)'"/>
          </div>

          <button type="submit"
            style="width:100%;padding:.8rem;background:#7c3aed;border:none;border-radius:9px;color:#fff;font-size:.95rem;font-weight:600;cursor:pointer;margin-top:.25rem;"
            onmouseover="this.style.background='#6d28d9'" onmouseout="this.style.background='#7c3aed'">
            Create free account
          </button>
        </form>

        <p style="text-align:center;color:#64748b;font-size:.82rem;margin-top:1.5rem;">
          Already have an account?
          <a href="/login" style="color:#a78bfa;text-decoration:none;font-weight:500;">Sign in →</a>
        </p>
      </div>
    </div>
    """
  end

  defp render_flash(conn) do
    info  = Phoenix.Flash.get(conn.assigns[:flash] || %{}, :info)
    error = Phoenix.Flash.get(conn.assigns[:flash] || %{}, :error)

    cond do
      info  -> ~s(<div class="flash-info" style="border-radius:8px;padding:.75rem 1rem;margin-bottom:1rem;font-size:.85rem;">#{info}</div>)
      error -> ~s(<div class="flash-error" style="border-radius:8px;padding:.75rem 1rem;margin-bottom:1rem;font-size:.85rem;">#{error}</div>)
      true  -> ""
    end
  end
end
