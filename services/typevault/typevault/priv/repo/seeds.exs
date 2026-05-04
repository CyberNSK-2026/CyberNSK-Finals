alias TypeVault.{Repo, Accounts, Fonts}

# Demo user for testing
{:ok, demo_user} =
  Accounts.register_user(%{
    "username" => "typevault_demo",
    "email" => "demo@typevault.local",
    "password" => "Demo123456!",
    "bio" => "Official TypeVault demo account"
  })

# Create a public sample project
{:ok, sample_project} =
  Fonts.create_project(
    %{
      "name" => "Inter Mono Sample",
      "description" => "A clean monospaced font for code editors and terminals.",
      "is_public" => true,
      "tags" => ["monospace", "code", "terminal"],
      "license" => "ofl",
      "design_notes" => "Demo notes for seeded sample data."
    },
    demo_user.id
  )

IO.puts("Seeded demo user: #{demo_user.email}")
IO.puts("Seeded sample project: #{sample_project.name}")
