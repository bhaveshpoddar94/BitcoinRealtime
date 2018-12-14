defmodule Btc do
  def init(n) do
    miners  = create_miners(n)

    # Give each miner the address of all other miners
    start_time = DateTime.utc_now
    Enum.each(miners, 
      fn {mid, _mpub} -> 
        Miner.set_miners(mid, miners)
        Miner.set_parent(mid, self())
      end)
    
    # select a random node to report stats
    {first_id, _fpub} = Enum.at(miners, 0)
    Miner.set_reporter(first_id)
  
    # generate 1000 transactions 
    Enum.each(1..1000,
      fn x -> 
        {sid, transaction} = create_transaction(miners)
        Miner.broadcast_transaction(sid, transaction)
        :timer.sleep(100)
      end)

    # Run a loop which waits for the simulation to end
    loop(n*1000, 0)
  end

  def create_miners(n) do
    Enum.map(1..n,
      fn x ->
        {private, public} = Wallet.generate_keypair
        pid = Miner.start_link(%{
          :private       => private,
          :public        => public,
          :blockchain    => [],
          :txn           => [],
          :balance       => 100,
          :reporter      => false,
        })
        IO.puts("Miner number #{x} created")
        {pid, public}
      end)
      |> Enum.into(%{})
  end

  def create_transaction(miners) do
    {sid, spub}  = Enum.random(miners)
    {_rid, rpub} = Enum.random(miners)
    amount = (:rand.uniform() * 10)/2 |> Float.round(2)
    tstamp = DateTime.utc_now
    fee = :rand.uniform
    {sid, [spub, rpub, amount, tstamp, fee]}
  end

  def loop(total, acc) when total <= acc, do: :ok 
  def loop(total, acc) do 
    receive do 
      {:len, len} -> 
        loop(total, acc+len)
    end
  end
end

# Btc.init()