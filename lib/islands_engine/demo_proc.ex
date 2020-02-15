defmodule IslandsEngine.DemoProc do
  def loop() do
    receive do
      message -> IO.puts "Received #{inspect message}"
    end
    loop()
  end
end
