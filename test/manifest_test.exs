defmodule MastheadCli.ManifestTest do
  use ExUnit.Case, async: true

  alias MastheadCli.Manifest

  describe "parse/1" do
    test "parses a valid manifest" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],"metadata":[]})
      assert {:ok, %Manifest{name: "X", slug: "x", version: "1.0.0"}} = Manifest.parse(json)
    end

    test "collects all validation errors" do
      json = ~s({"slug":"Bad Slug!"})
      assert {:error, errors} = Manifest.parse(json)
      assert Enum.any?(errors, &(&1 =~ "name"))
      assert Enum.any?(errors, &(&1 =~ "slug"))
      assert Enum.any?(errors, &(&1 =~ "version"))
    end

    test "rejects invalid JSON" do
      assert {:error, [msg]} = Manifest.parse("{not json")
      assert msg =~ "invalid JSON"
    end

    test "requires options for select tokens" do
      json =
        ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[{"key":"k","label":"L","type":"select","default":"a"}]})

      assert {:error, errors} = Manifest.parse(json)
      assert Enum.any?(errors, &(&1 =~ "options"))
    end
  end

  describe "effective_tokens/2" do
    setup do
      {:ok, m} =
        Manifest.from_map(%{
          "name" => "X",
          "slug" => "x",
          "version" => "1.0.0",
          "tokens" => [
            %{"key" => "accent", "label" => "A", "type" => "color", "default" => "#000"},
            %{"key" => "width", "label" => "W", "type" => "length", "default" => "880px"}
          ]
        })

      %{manifest: m}
    end

    test "merges defaults with overrides", %{manifest: m} do
      assert %{"accent" => "#fff", "width" => "880px"} =
               Manifest.effective_tokens(m, %{"accent" => "#fff"})
    end

    test "drops unknown override keys", %{manifest: m} do
      tokens = Manifest.effective_tokens(m, %{"bogus" => "x"})
      refute Map.has_key?(tokens, "bogus")
    end

    test "blank overrides fall back to default", %{manifest: m} do
      assert %{"accent" => "#000"} = Manifest.effective_tokens(m, %{"accent" => ""})
    end
  end

  describe "effective_metadata/2" do
    setup do
      {:ok, m} =
        Manifest.from_map(%{
          "name" => "X",
          "slug" => "x",
          "version" => "1.0.0",
          "metadata" => [
            %{"key" => "show", "label" => "Show", "type" => "boolean", "default" => true},
            %{"key" => "n", "label" => "N", "type" => "number", "default" => 3}
          ]
        })

      %{manifest: m}
    end

    test "coerces declared types", %{manifest: m} do
      assert %{"show" => false, "n" => 7} =
               Manifest.effective_metadata(m, %{"show" => "false", "n" => "7"})
    end

    test "preserves unknown keys (theme-switch resilience)", %{manifest: m} do
      assert %{"legacy" => "kept"} = Manifest.effective_metadata(m, %{"legacy" => "kept"})
    end
  end
end
