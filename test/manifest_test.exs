defmodule MastheadCli.ManifestTest do
  use ExUnit.Case, async: true

  alias MastheadCli.Manifest

  describe "parse/1" do
    test "parses a valid manifest" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],"page_options":[]})
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

  describe "page option defaults and coercion" do
    setup do
      {:ok, m} =
        Manifest.from_map(%{
          "name" => "X",
          "slug" => "x",
          "version" => "1.0.0",
          "page_options" => [
            %{"key" => "show", "label" => "Show", "type" => "boolean", "default" => true},
            %{"key" => "n", "label" => "N", "type" => "number", "default" => 3}
          ]
        })

      %{manifest: m}
    end

    test "coerces declared types", %{manifest: m} do
      assert %{"show" => false, "n" => 7} =
               Manifest.merge_fields(m.page_options, %{"show" => "false", "n" => "7"})
    end

    test "preserves unknown keys (theme-switch resilience)", %{manifest: m} do
      assert %{"legacy" => "kept"} = Manifest.merge_fields(m.page_options, %{"legacy" => "kept"})
    end
  end

  describe "object/list tokens (tokens and options share one type set)" do
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

  describe "render_version and options" do
    test "defaults to beta, and a legacy metadata key parses into page_options" do
      json =
        ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],) <>
          ~s("metadata":[{"key":"layout","label":"L","type":"string","default":"a"}]})

      assert {:ok, m} = Manifest.parse(json)
      assert m.render_version == "beta"
      assert [%{key: "layout"}] = m.page_options
    end

    test "accepts v1 with page_options and post_options" do
      json =
        ~s({"name":"X","slug":"x","version":"1.0.0","render_version":"v1","tokens":[],) <>
          ~s("page_options":[{"key":"layout","label":"L","type":"string","default":"a"}],) <>
          ~s("post_options":[{"key":"cover","label":"C","type":"file","default":""}]})

      assert {:ok, m} = Manifest.parse(json)
      assert m.render_version == "v1"
      assert [%{key: "layout"}] = m.page_options
      assert [%{key: "cover", type: "file"}] = m.post_options
    end

    test "rejects an unknown render_version" do
      json = ~s({"name":"X","slug":"x","version":"1.0.0","render_version":"v9","tokens":[]})
      assert {:error, errs} = Manifest.parse(json)
      assert Enum.any?(errs, &String.contains?(&1, "render_version"))
    end

    test "rejects post_options on a beta theme, whose renderer cannot expose them" do
      json =
        ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],) <>
          ~s("post_options":[{"key":"cover","label":"C","type":"file","default":""}]})

      assert {:error, errs} = Manifest.parse(json)
      assert Enum.any?(errs, &String.contains?(&1, "post_options"))
    end

    test "reports field errors under the key the manifest actually used" do
      legacy =
        ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],) <>
          ~s("metadata":[{"key":"k","label":"K","type":"weird","default":""}]})

      named =
        ~s({"name":"X","slug":"x","version":"1.0.0","tokens":[],) <>
          ~s("page_options":[{"key":"k","label":"K","type":"weird","default":""}]})

      assert {:error, a} = Manifest.parse(legacy)
      assert {:error, b} = Manifest.parse(named)
      assert Enum.any?(a, &String.contains?(&1, "metadata[0].type"))
      assert Enum.any?(b, &String.contains?(&1, "page_options[0].type"))
    end
  end
end
