defmodule Miner do
  use GenServer

  # Miner clientside
  def start_link(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state)
    pid
  end

  def get_blockchain(pid) do 
    GenServer.call(pid, :get_blockchain)
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def set_reporter(pid) do
    GenServer.cast(pid, {:set_reporter})
  end

  def set_miners(pid, miners) do 
    GenServer.cast(pid, {:set_miners, miners})
  end

  def set_parent(pid, parent) do 
    GenServer.cast(pid, {:set_parent, parent})
  end

  def broadcast_transaction(pid, transaction) do 
    GenServer.cast(pid, {:broadcast_transaction, transaction})
  end

  def add_transaction(pid, payload) do 
    GenServer.cast(pid, {:add_transaction, payload})
  end

  def add_block(pid, sender, block) do 
    GenServer.cast(pid, {:add_block, sender, block})
  end

  def stop(server) do
    GenServer.stop(server)
  end

  # Miner serverside
  def init(state) do
    {:ok, state}
  end

  def handle_call(:get_blockchain, _from, state) do
    {:reply, state[:blockchain], state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:set_reporter}, state) do
    new_state = Map.put(state, :reporter, true) |> Map.put(:time, DateTime.utc_now)
    {:noreply, new_state}
  end

  def handle_cast({:set_miners, miners}, state) do
    {:noreply, Map.put(state, :miners, miners)}
  end

  def handle_cast({:set_parent, parent}, state) do
    {:noreply, Map.put(state, :parent, parent)}
  end

  # Sign and broadcast transactions
  def handle_cast({:broadcast_transaction, transaction}, state) do
    signature = Wallet.sign(inspect(transaction), state[:private])
    payload   = [signature, transaction]
    Enum.each(state[:miners],
      fn {mid, _mpub} ->
        Miner.add_transaction(mid, payload)
      end)
    {:noreply, state}
  end

  # Verify and add an incoming transaction to state 
  def handle_cast({:add_transaction, payload}, state) do
    [signature, transaction] = payload
    [spub, _rpub, _amount, _tstamp, _fee] = transaction
    valid = (Wallet.verify(inspect(transaction), signature, spub) 
            && Util.sufficient_balance(state[:blockchain], transaction))
    
    new_transactions = 
      case valid do 
        true  -> [transaction | state[:txn]] 
        false -> state[:txn] 
      end 
      
    cond do
      Enum.empty?(state[:blockchain]) && valid -> 
        Util.send_block(state, new_transactions, "0000000000000000")
        {:noreply, Map.put(state, :txn, new_transactions)}
      Enum.empty?(state[:txn]) && valid -> 
        Util.send_block(state, new_transactions, hd(state[:blockchain]) |> Map.get(:hash))
        {:noreply, Map.put(state, :txn, new_transactions)}
      true -> 
        {:noreply, Map.put(state, :txn, new_transactions)}
    end
  end

  # 1. Verify and add an incoming block to the blockchain 
  # 2. Report block statistics to the websocket
  def handle_cast({:add_block, sender, block}, state) do 
    {new_chain, new_transactions, bal} = 
      cond do 
        Enum.empty?(state[:blockchain]) || Util.validblock?(block, hd(state[:blockchain]) |> Map.get(:hash)) -> 
          transactions = Enum.filter(state[:txn], fn t -> t not in block[:txn] end) 
          if !Enum.empty?(transactions) do Util.send_block(state, transactions, block[:hash]) end 
          
          # Calculate new balance
          [inc, dec] = Util.calculate_balance(state[:public], block)

          # Report block length to parent process
          par = Map.get(state, :parent, false)
          blen = length(block[:txn])
          if par != false do send(par, {:len, blen}) end

          # report stats to web interface
          if state[:reporter] do
            btcoins = Enum.reduce(block[:txn], 0, fn ([_s, _r, a, _t, _f], acc) -> acc + a end)
            fee = Enum.reduce(block[:txn], 0.0, fn ([_s, _r, _a, _t, f], acc) -> acc + f end)
            diff = Time.diff(block[:tstamp], state[:time])
            rate = diff/(length(state[:blockchain])+1)
            q = %{"response" => blen, "btcoins" => btcoins, "rate" => rate, "fee" => fee}
            DashWeb.Endpoint.broadcast!("room:bitcoin", "chain", q)
          end
          
          {[block | state[:blockchain]], transactions, state[:balance] + inc + dec}
        true -> 
          {state[:blockchain], state[:txn], state[:balance]}
      end 
    new_state = state 
    |> Map.put(:blockchain, new_chain)
    |> Map.put(:txn, new_transactions)
    |> Map.put(:balance, bal)
    {:noreply, new_state}
  end 
end
