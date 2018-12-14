defmodule Util do
  def send_block(state, transactions, prev_hash) do
    {hash, nonce} = generate_proof(inspect(transactions), prev_hash)
    payload = %{
      :hash      => hash, 
      :nonce     => nonce, 
      :txn       => transactions, 
      :prev_hash => prev_hash,
      :tstamp    => DateTime.utc_now
    }
    Enum.map(state[:miners], fn {mid, _mpub} -> Miner.add_block(mid, self(), payload) end)
  end

  def generate_proof(txn, prev_hash, len \\ 9) do 
    nonce   = :crypto.strong_rand_bytes(len) |> Base.url_encode64 |> binary_part(0, len) |> String.downcase
    message = prev_hash <> txn <> nonce
    hash    = :crypto.hash(:sha256, message) |> Base.encode16 |> String.downcase
    cond do 
      String.slice(hash, 0..2) == "000" -> {hash, nonce}
      true -> generate_proof(txn, prev_hash)
    end 
  end

  def validblock?(block, prev_hash) do 
    message = prev_hash <> inspect(block[:txn]) <> block[:nonce]
    curr_hash = :crypto.hash(:sha256, message) |> Base.encode16 |> String.downcase
    curr_hash == block[:hash]
  end

  def sufficient_balance(blockchain, transaction) do
    [spub, rpub, amount, tstamp, fee] = transaction
    bal = Enum.reduce(blockchain, 100, 
      fn (block, acc) ->
        net = Enum.reduce(block[:txn], 0, 
                fn([s, r, a, t, f], acc1) -> 
                  if s == spub do acc1-a end
                  if r == spub do acc1+a else acc1 + 0 end
                end)
        acc + net
      end)
    if bal >= amount do true else false end
  end

  def calculate_balance(pub_key, block) do
    dec = Enum.reduce(block[:txn], 0, 
      fn ([s, r, a, t, f], acc) -> 
        case s do
          ^pub_key -> acc - a
          _        -> acc + 0
        end
      end)
    
    inc = Enum.reduce(block[:txn], 0, 
      fn ([s, r, a, t, f], acc) -> 
        case r do
          ^pub_key -> acc + a
          _        -> acc + 0
        end
      end)
    [inc, dec]
  end
end