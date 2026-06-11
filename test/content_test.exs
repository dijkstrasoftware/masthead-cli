defmodule MastheadCli.ContentTest do
  use ExUnit.Case, async: true

  alias MastheadCli.Content

  test "markdown is rendered and sanitized" do
    html = Content.render_body("# Title\n\n[link](https://example.com)", "markdown")
    assert html =~ "Title</h1>"
    assert html =~ ~s|href="https://example.com"|
  end

  test "markdown escapes raw HTML in source" do
    html = Content.render_body("a <script>alert(1)</script> b", "markdown")
    refute html =~ "<script>"
  end

  test "html format keeps structural tags but strips scripts and styles" do
    html =
      Content.render_body(~s|<section class="x"><p>ok</p></section><script>x</script>|, "html")

    assert html =~ ~s|<section class="x">|
    assert html =~ "<p>ok</p>"
    refute html =~ "<script>"
  end

  test "html format strips inline style and event handlers" do
    html = Content.render_body(~s|<p style="color:red" onclick="x()">hi</p>|, "html")
    assert html =~ "hi"
    refute html =~ "style="
    refute html =~ "onclick"
  end

  test "nil body renders empty" do
    assert Content.render_body(nil, "markdown") == ""
  end
end
