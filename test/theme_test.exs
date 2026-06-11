defmodule MastheadCli.ThemeTest do
  use ExUnit.Case, async: true

  alias MastheadCli.{FixtureTheme, Theme}

  test "loads a complete theme" do
    {dir, theme} = FixtureTheme.load!()
    on_exit(fn -> File.rm_rf!(dir) end)

    assert theme.manifest.slug == "test-theme"
    assert theme.asset_base == "/assets"

    assert Map.keys(theme.templates) |> Enum.sort() ==
             [:blog, :index, :layout, :not_found, :page, :post]
  end

  test "reports a missing manifest" do
    dir = Path.join(System.tmp_dir!(), "empty_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:error, {:missing, msg}} = Theme.load(dir)
    assert msg =~ "manifest.json"
  end

  test "reports an invalid manifest" do
    {:error, {:manifest, errors}} = wait_error(%{"manifest.json" => ~s({"slug":"!!"})})
    assert is_list(errors)
    assert Enum.any?(errors, &(&1 =~ "name"))
  end

  test "reports a missing template" do
    dir = FixtureTheme.create!()
    File.rm!(Path.join([dir, "templates", "post.liquid"]))
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:error, {:templates, errors}} = Theme.load(dir)
    assert {:post, msg} = List.keyfind(errors, :post, 0)
    assert msg =~ "missing"
  end

  test "reports a template parse error" do
    dir = FixtureTheme.create!(%{"templates/index.liquid" => "{% if %}"})
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:error, {:templates, errors}} = Theme.load(dir)
    assert List.keyfind(errors, :index, 0)
  end

  defp wait_error(overrides) do
    dir = FixtureTheme.create!(overrides)
    on_exit(fn -> File.rm_rf!(dir) end)
    Theme.load(dir)
  end
end
