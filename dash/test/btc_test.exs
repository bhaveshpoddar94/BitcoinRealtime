defmodule BtcTest do
  use ExUnit.Case
  doctest Btc

  setup do
    miners = Btc.create_miners(2) |> Map.to_list()
    Enum.each(miners, 
      fn {mid, _mpub} -> 
        Miner.set_miners(mid, miners)
        Miner.set_parent(mid, self())
      end)
    %{miners: miners}
  end

  test "number of miners", %{miners: miners} do
    assert length(miners) == 2
  end

  test "valid initial state of miners", %{miners: miners} do
    [{mid, mpub}, {mid2, mpub2}] = miners
    state = Miner.get_state(mid)
    assert state[:public]     == mpub
    assert state[:blockchain] == []
    assert state[:txn]        == []
    assert state[:blockchain] == []
    assert state[:balance]    == 100
  end

  # zeroth transaction 
  test "genesis block creation", %{miners: miners} do
    # all miners should have one block, 
    # loop() listens for completion of mining
    [{mid, mpub}, {mid2, mpub2}] = miners
    txn = [mpub, mpub2, 2.3, DateTime.utc_now, 0.1]
    Miner.broadcast_transaction(mid, txn)
    len = loop(2, 0)
    
    blocks = Enum.map(miners, fn {mid, _mpub} -> Miner.get_blockchain(mid) end)
    [blockchain1, blockchain2] = blocks

    # Each miner should have one block in its blockchain
    assert length(blockchain1) == 1
    assert length(blockchain2) == 1

    # Each block should have one transaction
    assert length(hd(blockchain1)[:txn]) == 1
    assert length(hd(blockchain2)[:txn]) == 1
    
    # That single transaction should be the same in both blocks
    assert hd(blockchain1)[:txn] == hd(blockchain2)[:txn]
  end 

  def loop(total, acc) when acc >= total, do: acc 
  def loop(total, acc) do
    receive do
      {:len, len} -> loop(total, acc+len)
    end
  end
end

defmodule MinerTest do
  use ExUnit.Case
  doctest Miner

  setup do
    miners = Btc.create_miners(3) |> Map.to_list()
    Enum.each(miners, 
      fn {mid, _mpub} -> 
        Miner.set_miners(mid, miners)
        Miner.set_parent(mid, self())
      end)
    %{miners: miners}
  end

  test "valid hash calculation" do
    {hash, nonce} = Util.generate_proof("Hello World", "0000000000000000")

    # Check if hash starts with 2 zeroes
    assert String.slice(hash, 0..2) == "000"

    # Check if we can reproduce the hash 
    reprod = :crypto.hash(:sha256, "0000000000000000" <> "Hello World" <> nonce)
            |> Base.encode16 |> String.downcase
    assert reprod == hash
  end

  test "invalid hash calculation" do
    # Check for failure with different data
    {hash, nonce} = Util.generate_proof("Hello World", "0000000000000000")
    reprod = :crypto.hash(:sha256, "abc0000000def" <> "Hello World" <> nonce)
            |> Base.encode16 |> String.downcase
    assert reprod != hash
  end

  test "transaction 2 clients, 3 miners", %{miners: miners} do
    {mid, mpub}   = Enum.at(miners, 0)
    {mid1, mpub1} = Enum.at(miners, 1)
    {mid2, mpub2} = Enum.at(miners, 2)

    # List of transactions
    txn1 = [mpub, mpub2, 50, DateTime.utc_now, 0.1]
    txn2 = [mpub2, mpub, 10, DateTime.utc_now, 0.2]

    # Broadcast transactions
    Miner.broadcast_transaction(mid, txn1)
    Miner.broadcast_transaction(mid2, txn2)

    # Wait for blockchain to update
    len = loop(3*2, 0)

    state1 = Miner.get_state(mid)
    state2 = Miner.get_state(mid1)
    state3 = Miner.get_state(mid2)
    
    # check the account balances for both the clients after the simulation
    assert state1[:balance] == 60
    assert state3[:balance] == 140

    # check all miners have the same blockchain
    assert state1[:blockchain] == state2[:blockchain]
    assert state2[:blockchain] == state3[:blockchain]

    Miner.stop(mid)
    Miner.stop(mid1)
    Miner.stop(mid2)
  end

  # transaction scenario 2
  test "invalid transactions insufficient balance", %{miners: miners} do 
    # signing transaction with wrong private key 
    {mid, mpub}   = Enum.at(miners, 0)
    {mid2, mpub2} = Enum.at(miners, 2)

    # check if invalid transaction (insufficient funds) not added to block
    txn1 = [mpub, mpub2, 103, DateTime.utc_now, 0.9]
    Miner.broadcast_transaction(mid, txn1)
    
    :timer.sleep(1000)

    state1 = Miner.get_state(mid)
    state3 = Miner.get_state(mid2)

    # balance unchanged, same as initial balance
    assert state1[:balance] == 100
    assert state3[:balance] == 100

    # check all miners have the same blockchain
    assert state1[:blockchain] == state3[:blockchain]

  end

  test "add block method" do
    # when blockchain is empty, incoming block accepted
    miners = Btc.create_miners(1) |> Map.to_list()
    [{mid, mpub}] = miners
    Enum.each(miners, 
      fn {mid, _mpub} -> 
        Miner.set_miners(mid, miners)
        Miner.set_parent(mid, self())
      end)
    
    # add a genesis block
    {hash, nonce} = Util.generate_proof(inspect([]), "0000000000000000")
    payload = %{:hash => hash, :nonce => nonce, :txn => [], :prev_hash => "0000000000000000"}
    GenServer.cast(mid, {:add_block, mid, payload})

    # check if genesis block added
    :timer.sleep(100)
    state = Miner.get_state(mid)
    blockchain = state[:blockchain]
    assert length(blockchain) == 1
    assert hd(blockchain) == payload

    # add a valid block, generate a block using hash of genesis block as prev_hash
    {hash1, nonce1} = Util.generate_proof(inspect([]), hash)
    payload1 = %{:hash => hash1, :nonce => nonce1, :txn => [], :prev_hash => hash}
    GenServer.cast(mid, {:add_block, mid, payload1})

    # check if valid block added to the blockchain 
    :timer.sleep(100)
    state = Miner.get_state(mid)
    assert length(state[:blockchain]) == 2
    assert hd(state[:blockchain]) == payload1

    # add an invalid block, for example the genesis block 
    # and check that its not getting added to the chain
    GenServer.cast(mid, {:add_block, mid, payload})
    :timer.sleep(100)
    state = Miner.get_state(mid)
    assert length(state[:blockchain]) == 2
    assert hd(state[:blockchain]) == payload1

    Miner.stop(mid)
  end

  test "invalid transactions fake signature" do
    miners = Btc.create_miners(2) |> Map.to_list()
    [{mid, mpub}, {mid1, mpub1}] = miners
    Enum.each(miners, 
      fn {mid, _mpub} -> 
        Miner.set_miners(mid, miners)
        Miner.set_parent(mid, self())
      end)
    
    # signing transaction with wrong private key
    txn     = [mpub, mpub1, 3.4, DateTime.utc_now, 0.5] 
    state1  = Miner.get_state(mid1) 
    payload = [Wallet.sign(inspect(txn), state1[:private]), txn] 
    GenServer.cast(mid, {:add_transaction, payload}) 

    # check invalid transaction not added to block  
    :timer.sleep(100)
    state = Miner.get_state(mid)
    assert length(state[:txn]) == 0
    assert length(state[:blockchain]) == 0
  end

  def loop(total, acc) when acc >= total, do: acc 
  def loop(total, acc) do
    receive do
      {:len, len} -> 
        loop(total, acc+len)
    end
  end
end

# Wallet is a module that generates key pairs for nodes, 
# and signs and verifies transactions
defmodule WalletTest do
  use ExUnit.Case
  doctest Wallet

  setup do
    {priv, pub} = Wallet.generate_keypair()
    %{priv: priv, pub: pub}
  end

  test "valid signed message", %{priv: priv, pub: pub} do
    signature = Wallet.sign("FooBar", priv)
    assert Wallet.verify("FooBar", signature, pub) == true
  end

  test "invalid signed message", %{priv: priv, pub: pub} do
    {priv1, pub1} = Wallet.generate_keypair()
    signature = Wallet.sign("FooBar", priv)
    assert Wallet.verify("FooBar", signature, pub1) == false
  end
end