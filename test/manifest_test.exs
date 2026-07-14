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

  describe "object/list tokens (tokens and metadata share one type set)" do
    setup do
      {:ok, manifest} =
        Manifest.parse(~s({
          "name":"X","slug":"x","version":"1.0.0",
          "tokens":[
            {"key":"hero","label":"Hero","type":"object","fields":[
              {"key":"title","label":"T","type":"string","default":"Default title"},
              {"key":"boxed","label":"B","type":"boolean","default":true}]},
            {"key":"links","label":"Links","type":"list","item_label":"Link",
             "default":[{"label":"Home"}],
             "fields":[
               {"key":"label","label":"L","type":"string","default":""},
               {"key":"url","label":"U","type":"url","default":"/"}]}
          ]
        }))

      {:ok, manifest: manifest}
    end

    test "a token can declare a container, with its nested fields", %{manifest: m} do
      assert [hero, links] = m.tokens
      assert hero.type == "object"
      assert [%{key: "title"}, %{key: "boxed"}] = hero.fields
      assert links.type == "list"
      assert links.item_label == "Link"
    end

    test "effective_tokens merges containers against their nested schema", %{manifest: m} do
      # No overrides: the object fills its nested defaults, the list renders the
      # default items it declares.
      assert %{"hero" => %{"title" => "Default title", "boxed" => true}, "links" => links} =
               Manifest.effective_tokens(m, %{})

      assert links == [%{"label" => "Home", "url" => "/"}]

      tokens =
        Manifest.effective_tokens(m, %{
          "hero" => %{"title" => "Custom", "boxed" => "false"},
          "links" => [%{"label" => "Docs", "url" => "/docs"}, %{"label" => "Blog"}]
        })

      assert tokens["hero"] == %{"title" => "Custom", "boxed" => false}

      # Every item is merged against the schema, so an unset subkey arrives with
      # its default rather than as a blank.
      assert tokens["links"] == [
               %{"label" => "Docs", "url" => "/docs"},
               %{"label" => "Blog", "url" => "/"}
             ]

      # A stored empty list is a deliberate "no items", not "unset".
      assert Manifest.effective_tokens(m, %{"links" => []})["links"] == []
    end

    test "a container token needs fields, and cannot nest another container" do
      assert {:error, errs} =
               Manifest.parse(
                 ~s({"name":"X","slug":"x","version":"1.0.0",) <>
                   ~s("tokens":[{"key":"hero","label":"H","type":"object"}]})
               )

      assert Enum.any?(errs, &String.contains?(&1, "tokens[0].fields"))

      assert {:error, errs} =
               Manifest.parse(
                 ~s({"name":"X","slug":"x","version":"1.0.0",) <>
                   ~s("tokens":[{"key":"hero","label":"H","type":"object","fields":[) <>
                   ~s({"key":"inner","label":"I","type":"list","fields":[]}]}]})
               )

      assert Enum.any?(errs, &String.contains?(&1, "tokens[0].fields[0].type"))
    end
  end
end
