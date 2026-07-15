defmodule MastheadCli.PreflightTest do
  use ExUnit.Case, async: true

  alias MastheadCli.Preflight

  describe "check_against/1" do
    setup do
      build = Preflight.build_info().otp
      {:ok, build: String.to_integer(build)}
    end

    test "passes when the runtime OTP equals the build", %{build: build} do
      assert Preflight.check_against(to_string(build)) == :ok
    end

    test "passes when the runtime OTP is newer than the build", %{build: build} do
      assert Preflight.check_against(to_string(build + 1)) == :ok
    end

    test "fails when the runtime OTP is older than the build", %{build: build} do
      assert {:error, message} = Preflight.check_against(to_string(build - 1))
      assert message =~ "corrupt atom table"
      assert message =~ "OTP #{build}"
      assert message =~ "OTP #{build - 1}"
    end

    test "passes when the runtime release can't be parsed" do
      assert Preflight.check_against("R16B03") == :ok
    end
  end

  describe "build_info/0 and runtime_info/0" do
    test "report the expected version fields" do
      for info <- [Preflight.build_info(), Preflight.runtime_info()] do
        assert %{otp: otp, erts: erts, elixir: elixir} = info
        assert is_binary(otp) and otp != ""
        assert is_binary(erts) and erts != ""
        assert is_binary(elixir) and elixir != ""
      end
    end
  end
end
