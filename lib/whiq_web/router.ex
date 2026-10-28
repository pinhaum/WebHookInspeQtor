defmodule WhiqWeb.Router do
  use WhiqWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WhiqWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", WhiqWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/bins", BinController, :create
    live "/bins/:token", BinLive
  end

  # No pipeline: captures must reach the controller exactly as sent (AD-001).
  scope "/h", WhiqWeb do
    match :*, "/:token", CaptureController, :capture
    match :*, "/:token/*path", CaptureController, :capture
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:whiq, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WhiqWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
