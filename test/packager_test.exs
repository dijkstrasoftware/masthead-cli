defmodule MastheadCli.PackagerTest do
  use ExUnit.Case, async: true

  alias MastheadCli.{FixtureTheme, Packager}

  # Read the in-archive file names from a zip on disk.
  defp zip_names(path) do
    {:ok, list} = :zip.list_dir(String.to_charlist(path))

    for {:zip_file, name, _info, _comment, _offset, _comp} <- list,
        do: List.to_string(name)
  end

  defp out_dir do
    d = Path.join(System.tmp_dir!(), "mh_pkg_out_#{System.unique_integer([:positive])}")
    File.mkdir_p!(d)
    d
  end

  test "packages the canonical files and excludes dev-only content" do
    dir =
      FixtureTheme.create!(%{
        "assets/logo.svg" => "<svg/>",
        "assets/font.woff2" => "woff",
        "assets/notes.txt" => "should be skipped",
        "preview.json" => ~s({"site":{"name":"x"}}),
        "preview/posts/a.md" => "draft",
        "README.md" => "# readme"
      })

    out = out_dir()

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(out)
    end)

    assert {:ok, summary} = Packager.package(dir, out)
    assert File.regular?(summary.path)
    assert summary.path == Path.join(out, "test-theme-1.0.0.zip")

    names = zip_names(summary.path)

    # Canonical theme files present.
    assert "manifest.json" in names
    assert "theme.css" in names
    assert "templates/index.liquid" in names
    assert "templates/layout.liquid" in names
    assert "templates/not_found.liquid" in names
    assert "assets/logo.svg" in names
    assert "assets/font.woff2" in names

    # Dev-only + disallowed files excluded.
    refute "preview.json" in names
    refute Enum.any?(names, &String.starts_with?(&1, "preview/"))
    refute "README.md" in names
    refute "assets/notes.txt" in names

    # The skipped asset is surfaced as a warning.
    assert Enum.any?(summary.warnings, &(&1 =~ "notes.txt"))
  end

  test "refuses to package a theme with template errors" do
    dir = FixtureTheme.create!(%{"templates/index.liquid" => "{% if %}"})
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:error, msg} = Packager.package(dir, out_dir())
    assert msg =~ "Template problems"
  end

  test "refuses to package an invalid manifest" do
    dir = FixtureTheme.create!(%{"manifest.json" => ~s({"slug":"!!"})})
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:error, msg} = Packager.package(dir, out_dir())
    assert msg =~ "manifest.json is invalid"
  end

  test "honors an explicit .zip output path" do
    dir = FixtureTheme.create!()
    out = out_dir()
    target = Path.join(out, "custom-name.zip")

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(out)
    end)

    assert {:ok, %{path: ^target}} = Packager.package(dir, target)
    assert File.regular?(target)
  end

  test "treats a non-.zip out path as a directory and names the file" do
    dir = FixtureTheme.create!()
    out = Path.join(out_dir(), "nested/sub")

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(out)
    end)

    assert {:ok, summary} = Packager.package(dir, out)
    assert summary.path == Path.join(out, "test-theme-1.0.0.zip")
    assert File.regular?(summary.path)
  end

  describe "--bump" do
    test "bugfix bumps the patch and rewrites manifest.json + zip name" do
      dir = FixtureTheme.create!()
      out = out_dir()

      on_exit(fn ->
        File.rm_rf!(dir)
        File.rm_rf!(out)
      end)

      assert {:ok, summary} = Packager.package(dir, out, "bugfix")
      assert summary.bump == %{level: "bugfix", from: "1.0.0", to: "1.0.1"}
      assert summary.version == "1.0.1"
      assert summary.path == Path.join(out, "test-theme-1.0.1.zip")

      # The version is bumped on disk (in the code), not just in the zip.
      assert File.read!(Path.join(dir, "manifest.json")) =~ ~s("version": "1.0.1")
    end

    test "minor bumps the minor and zeroes the patch" do
      dir = FixtureTheme.create!()
      on_exit(fn -> File.rm_rf!(dir) end)
      assert {:ok, %{version: "1.1.0"}} = Packager.package(dir, out_dir(), "minor")
    end

    test "major bumps the major and zeroes minor + patch" do
      dir = FixtureTheme.create!()
      on_exit(fn -> File.rm_rf!(dir) end)
      assert {:ok, %{version: "2.0.0"}} = Packager.package(dir, out_dir(), "major")
    end

    test "nil leaves the version untouched" do
      dir = FixtureTheme.create!()
      on_exit(fn -> File.rm_rf!(dir) end)
      assert {:ok, %{version: "1.0.0", bump: nil}} = Packager.package(dir, out_dir(), nil)
      assert File.read!(Path.join(dir, "manifest.json")) =~ ~s("version": "1.0.0")
    end

    test "errors on a non-SemVer current version" do
      manifest = ~s({"name":"X","slug":"x","version":"v1","tokens":[],"metadata":[]})
      dir = FixtureTheme.create!(%{"manifest.json" => manifest})
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, msg} = Packager.package(dir, out_dir(), "minor")
      assert msg =~ "not valid SemVer"
    end
  end

  test "warns when the slug is reserved" do
    dir = FixtureTheme.create!(%{"manifest.json" => reserved_manifest()})
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, summary} = Packager.package(dir, out_dir())
    assert Enum.any?(summary.warnings, &(&1 =~ "reserved"))
  end

  defp reserved_manifest do
    ~s({"name":"Default","slug":"default","version":"1.0.0","tokens":[],"metadata":[]})
  end
end
