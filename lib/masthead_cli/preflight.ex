defmodule MastheadCli.Preflight do
  @moduledoc """
  Verifies the Erlang/OTP runtime is compatible with what this escript was
  built against.

  An escript bundles compiled BEAM files but *not* the Erlang runtime — it
  runs under whatever `erl`/`escript` invokes it. BEAM files compiled on a
  newer OTP cannot be loaded by an older runtime: the loader rejects them
  with "corrupt atom table". If a module fails that way before `main/1`
  runs there is nothing we can do, but dependency modules load lazily, so a
  too-old runtime often gets past startup and then dies mid-request. We turn
  that into a clear, upfront message instead.

  Elixir is compiled into the escript, so there is no separately-installed
  Elixir to verify at run time — we record the build version for reporting
  (`masthead doctor`). The build-time Elixir requirement is enforced by the
  `elixir:` constraint in mix.exs when the escript is compiled.

  Set `MASTHEAD_SKIP_VERSION_CHECK=1` to bypass the run-time guard.
  """

  # Captured at compile time: the toolchain that produced this escript.
  @build_otp System.otp_release()
  @build_erts List.to_string(:erlang.system_info(:version))
  @build_elixir System.version()

  @bypass_env "MASTHEAD_SKIP_VERSION_CHECK"

  @doc "Versions of the toolchain this escript was built with."
  def build_info, do: %{otp: @build_otp, erts: @build_erts, elixir: @build_elixir}

  @doc "Versions of the runtime this escript is currently executing on."
  def runtime_info do
    %{
      otp: System.otp_release(),
      erts: List.to_string(:erlang.system_info(:version)),
      elixir: System.version()
    }
  end

  @doc """
  Returns `:ok`, or `{:error, message}` when the running OTP is older than
  the one this escript was built with — the configuration that produces
  "corrupt atom table" load failures.
  """
  def check do
    if bypassed?() do
      :ok
    else
      check_against(System.otp_release())
    end
  end

  @doc """
  Pure core of `check/0`: compares this escript's build OTP against the given
  runtime OTP release. Separated out so both directions are testable on a
  machine where the live runtime always equals the build.
  """
  def check_against(runtime_release) do
    if older?(major(@build_otp), major(runtime_release)) do
      {:error, message(@build_otp, runtime_release)}
    else
      :ok
    end
  end

  defp bypassed?, do: String.downcase(System.get_env(@bypass_env, "")) in ~w(1 true yes)

  # Only a confidently-older runtime blocks; unparseable releases pass through.
  defp older?(build, runtime) when is_integer(build) and is_integer(runtime), do: runtime < build
  defp older?(_build, _runtime), do: false

  # OTP releases have been plain integers ("27", "28") since OTP 17; anything
  # we can't parse we treat as unknown and don't block on.
  defp major(release) do
    case Integer.parse(to_string(release)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp message(build, runtime) do
    """
    masthead was built with Erlang/OTP #{build} but is running on OTP #{runtime}.

    BEAM files compiled on a newer OTP can't be loaded by an older runtime —
    you may hit "corrupt atom table" errors. Install Erlang/OTP #{build} or
    newer and make sure it comes first on your PATH. Check what you have with:

        erl -eval 'io:format("OTP ~s~n",[erlang:system_info(otp_release)]),halt().' -noshell

    Installed via Homebrew? `brew reinstall masthead` rebuilds against your
    current Erlang. Run `masthead doctor` for full version details.

    To bypass this check, set #{@bypass_env}=1.
    """
  end
end
