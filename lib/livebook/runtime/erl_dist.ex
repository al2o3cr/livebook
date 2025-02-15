defmodule Livebook.Runtime.ErlDist do
  @moduledoc false

  # This module allows for initializing nodes connected using
  # Erlang Distribution with modules and processes necessary for evaluation.
  #
  # To ensure proper isolation between sessions,
  # code evaluation may take place in a separate Elixir runtime,
  # which also makes it easy to terminate the whole
  # evaluation environment without stopping Livebook.
  # This is what `Runtime.ElixirStandalone`, `Runtime.MixStandalone`
  # and `Runtime.Attached` do, so this module contains the shared
  # functionality they need.
  #
  # To work with a separate node, we have to inject the necessary
  # Livebook modules there and also start the relevant processes
  # related to evaluation. Fortunately Erlang allows us to send modules
  # binary representation to the other node and load them dynamically.
  #
  # For further details see `Livebook.Runtime.ErlDist.NodeManager`.

  # Modules to load into the connected node.
  @required_modules [
    Livebook.Evaluator,
    Livebook.Evaluator.IOProxy,
    Livebook.Evaluator.DefaultFormatter,
    Livebook.Completion,
    Livebook.Runtime.ErlDist,
    Livebook.Runtime.ErlDist.NodeManager,
    Livebook.Runtime.ErlDist.RuntimeServer,
    Livebook.Runtime.ErlDist.EvaluatorSupervisor,
    Livebook.Runtime.ErlDist.IOForwardGL,
    Livebook.Runtime.ErlDist.LoggerGLBackend
  ]

  @doc """
  Starts a runtime server on the given node.

  If necessary, the required modules are loaded
  into the given node and the node manager process
  is started with `node_manager_opts`.
  """
  @spec initialize(node(), keyword()) :: pid()
  def initialize(node, node_manager_opts \\ []) do
    unless modules_loaded?(node) do
      load_required_modules(node)
    end

    unless node_manager_started?(node) do
      start_node_manager(node, node_manager_opts)
    end

    start_runtime_server(node)
  end

  defp load_required_modules(node) do
    for module <- @required_modules do
      {_module, binary, filename} = :code.get_object_code(module)
      {:module, _} = :rpc.call(node, :code, :load_binary, [module, filename, binary])
    end
  end

  defp start_node_manager(node, opts) do
    :rpc.call(node, Livebook.Runtime.ErlDist.NodeManager, :start, [opts])
  end

  defp start_runtime_server(node) do
    Livebook.Runtime.ErlDist.NodeManager.start_runtime_server(node)
  end

  defp modules_loaded?(node) do
    :rpc.call(node, Code, :ensure_loaded?, [Livebook.Runtime.ErlDist.NodeManager])
  end

  defp node_manager_started?(node) do
    case :rpc.call(node, Process, :whereis, [Livebook.Runtime.ErlDist.NodeManager]) do
      nil -> false
      _pid -> true
    end
  end

  @doc """
  Unloads the previously loaded Livebook modules from the caller node.
  """
  def unload_required_modules() do
    for module <- @required_modules do
      # If we attached, detached and attached again, there may still
      # be deleted module code, so purge it first.
      :code.purge(module)
      :code.delete(module)
    end
  end
end
