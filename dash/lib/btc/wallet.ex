defmodule Wallet do
  def generate_keypair() do
    {:ok, {private_key, public_key}} = RsaEx.generate_keypair
    {private_key, public_key}
  end

  def sign(message, private_key) do
    {:ok, signature} = RsaEx.sign(message, private_key)
    signature
  end

  def verify(message, signature, public_key) do 
    {:ok, valid} = RsaEx.verify(message, signature, public_key)
    valid
  end 
end