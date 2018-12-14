defmodule DashWeb.PageController do
  use DashWeb, :controller

  def index(conn, _params) do
    pid = run_simulation()
    render conn, "index.html"
  end

  defp run_simulation() do
    spawn fn -> Btc.init(100) end
  end
end
