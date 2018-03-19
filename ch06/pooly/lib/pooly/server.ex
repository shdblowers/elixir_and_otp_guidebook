defmodule Pooly.Server do
  @moduledoc nil

  use GenServer

  import Supervisor.Spec

  defmodule State do
    @moduledoc nil

    defstruct sup: nil, worker_sup: nil, size: nil, workers: nil, mfa: nil
  end

  # API

  def start_link(sup, pool_config) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: __MODULE__)
  end

  # Callbacks

  def init([sup, pool_config]) when is_pid(sup), do: init(pool_config, %State{sup: sup})
  def init([{:mfa, mfa} | rest], state), do: init(rest, %State{state | mfa: mfa})
  def init([{:size, size} | rest], state), do: init(rest, %State{state | size: size})
  def init([_other_option | rest], state), do: init(rest, state)

  def init([], state) do
    # send message to start worker supervisor
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  def handle_info(:start_worker_supervisor, state = %State{sup: sup, mfa: mfa, size: size}) do
    {:ok, worker_sup} = Supervisor.start_child(sup, supervisor_spec(mfa))
    workers = prepopulate(size, worker_sup)

    {:noreply, %State{state | worker_sup: worker_sup, workers: workers}}
  end

  defp supervisor_spec(mfa) do
    opts = [restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [mfa], opts)
  end

  # Private

  defp prepopulate(size, sup) when is_pid(sup) do
    prepopulate(size, sup, [])
  end

  defp prepopulate(size, _sup, workers) when size < 1 do
    workers
  end

  defp prepopulate(size, sup, workers) do
    prepopulate(size - 1, sup, [new_worker(sup) | workers])
  end

  """
  Because Pooly.WorkerSupervisor has already specified child spec by using the
  :simple_one_for_one restart strategy, you only need to pass additional
  arguments to start_child/2 below.
  """

  defp new_worker(sup) do
    {:ok, worker} = Supervisor.start_child(sup, [[]])

    worker
  end
end
