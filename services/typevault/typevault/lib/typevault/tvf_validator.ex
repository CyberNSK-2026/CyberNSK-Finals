defmodule TypeVault.TVFValidator do
  import Bitwise

  def safe?(binary) when is_binary(binary), do: do_safe?(binary)

  defp do_safe?(<<>>), do: true

  defp do_safe?(<<0x04, len::16-little, rest::binary>>) do
    real_len = bxor(len, 0xCAFE)

    case rest do
      <<_body::binary-size(real_len), next::binary>> -> do_safe?(next)
      _ -> false
    end
  end

  defp do_safe?(<<opcode, rest::binary>>) when opcode in [0x01, 0x02, 0x03, 0x05, 0x06, 0xFE] do
    case skip_args(opcode, rest) do
      {:ok, next} -> do_safe?(next)
      :error -> false
    end
  end

  defp do_safe?(_), do: false

  defp skip_args(0x01, <<_::binary-size(4), next::binary>>), do: {:ok, next}
  defp skip_args(0x02, <<_::binary-size(8), next::binary>>), do: {:ok, next}
  defp skip_args(0x03, <<_::binary-size(4), next::binary>>), do: {:ok, next}
  defp skip_args(0x05, <<_::binary-size(1), next::binary>>), do: {:ok, next}
  defp skip_args(0x06, next), do: {:ok, next}
  defp skip_args(0xFE, <<_::binary-size(2), next::binary>>), do: {:ok, next}
  defp skip_args(_, _), do: :error
end
