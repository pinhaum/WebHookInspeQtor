defmodule WhiqWeb.ByteFormatTest do
  use ExUnit.Case, async: true

  alias WhiqWeb.ByteFormat

  describe "body/1" do
    test "LIVE-09: an empty body is :empty" do
      assert ByteFormat.body("") == :empty
    end

    test "LIVE-07: a valid UTF-8 body is shown as text, unchanged" do
      assert ByteFormat.body("olá <script>") == {:text, "olá <script>"}
    end

    test "LIVE-08: a body that is not valid UTF-8 is a hex dump" do
      assert ByteFormat.body(<<0xFF, 0x00, 0x41>>) == {:hex, "00000000  ff 00 41"}
    end

    test "LIVE-15: invalid UTF-8 after the first byte hex-dumps the whole body" do
      assert ByteFormat.body("a" <> <<0xFF>>) == {:hex, "00000000  61 ff"}
    end
  end

  describe "hex_dump/1" do
    test "LIVE-08: 16 lowercase bytes per line, offset column past 0x0f" do
      bytes = :binary.list_to_bin(Enum.to_list(0..16))

      assert ByteFormat.hex_dump(bytes) ==
               "00000000  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f\n" <>
                 "00000010  10"
    end
  end

  describe "printable/1" do
    test "keeps valid UTF-8 unchanged" do
      assert ByteFormat.printable("text/plain; charset=utf-8 ç") == "text/plain; charset=utf-8 ç"
    end

    test "escapes each invalid byte as \\xNN and keeps the valid runs" do
      assert ByteFormat.printable("a" <> <<0xFF, 0xFE>> <> "b") == "a\\xff\\xfeb"
    end

    test "maps nil to an empty string" do
      assert ByteFormat.printable(nil) == ""
    end
  end
end
